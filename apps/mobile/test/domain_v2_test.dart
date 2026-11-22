import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/store.dart';
import 'package:youshu/local_database.dart';

void main() {
  final fixtures = jsonDecode(
    File('../../tests/fixtures/domain-v2.json').readAsStringSync(),
  ) as Json;
  for (final f in fixtures['amounts']) {
    test('跨端金额 ${f['from']} ${f['minor']}', () {
      expect(
        convertAmount(f['minor'], f['from'], f['to'], f['rate']),
        f['expected'],
      );
    });
  }
  for (final f in fixtures['periods']) {
    test('跨端账期 ${f['date']} ${f['day']}', () {
      final p = periodAt(
        f['date'],
        f['rules'] ??
            [
              {'day': f['day'], 'effective': '2000-01-01'},
            ],
      );
      expect(p.start, f['start']);
      expect(p.end, f['end']);
    });
  }
  test('28–31日起始连续五年无漏日或重叠', () {
    for (final day in [1, 10, 28, 29, 30, 31]) {
      final rules = [
        {'day': day, 'effective': '2000-01-01'},
      ];
      var d = DateTime(2023);
      while (d.isBefore(DateTime(2028))) {
        final p = periodAt(dateKey(d), rules);
        expect(p.contains(dateKey(d)), true);
        expect(periodAt(p.end, rules).start, p.end);
        d = d.add(const Duration(days: 1));
      }
    }
  });
  test('金额不能使用浮点、零汇率或日元小数', () {
    expect(() => parseAmount('1.1', 'JPY'), throwsFormatException);
    expect(() => convertAmount(100, 'USD', 'CNY', '0'), throwsFormatException);
    expect(formatAmount(123, 'JPY'), '123');
    expect(formatAmount(-5, 'CNY'), '-0.05');
  });
  test('分类改名、父分类、标签任一全部和转账方向组合', () {
    final l = freshLedger('筛选');
    final parent = dictionary(l, 'category', type: 'expense').first['id'];
    (l['entries'] as List).add(
      entity('child', 'category', {
        'name': '聚餐',
        'type': 'expense',
        'parent_id': parent,
        'order': 50,
        'archived': false,
      }),
    );
    final rows = <Json>[
      for (final id in ['a', 'b', 'c'])
        entity(id, 'entry', {
          'date': '2026-11-05',
          'type': id == 'c' ? 'transfer' : 'expense',
          'amount': id == 'b' ? 500 : 100,
          'original_amount_minor': id == 'b' ? 500 : 100,
          'original_currency': 'CNY',
          'category_id': id == 'c' ? '' : 'child',
          'category': '旧分类名',
          'tag_ids': id == 'a' ? ['trip', 'work'] : ['trip'],
          'account': '微信',
          'to_account': id == 'c' ? '现金' : '',
          'note': '午饭',
        }),
    ];
    final p = BookPeriod('2026-11-01', '2026-12-01');
    final f = EntryFilter()
      ..categories = {parent}
      ..types = {'expense'}
      ..tags = {'work', 'trip'}
      ..allTags = true;
    expect(f.apply(l, rows, p).map((e) => e['id']), ['a']);
    f.allTags = false;
    expect(f.apply(l, rows, p).length, 2);
    f.min = 200;
    expect(f.apply(l, rows, p).single['id'], 'b');
    f.clear('amount');
    f.keyword = '聚餐';
    expect(f.apply(l, rows, p).length, 2);
    final t = EntryFilter()
      ..types = {'transfer'}
      ..accounts = {'现金'}
      ..accountSide = 'to';
    expect(t.apply(l, rows, p).single['id'], 'c');
    t.accountSide = 'from';
    expect(t.apply(l, rows, p), isEmpty);
  });
  test('v1 pending 迁移保留编号修订和原始金额，v2恢复保持引用', () {
    final Json raw = {
      'id': 'legacy',
      'name': '旧账',
      'shared': true,
      'role': 'owner',
      'entries': [
        entity('old', 'entry', {
          'type': 'expense',
          'date': '2026-11-06',
          'amount': 1234,
          'category': '餐饮',
          'account': '现金',
        }, revision: 3),
      ],
      'pending': [
        {
          'operation_id': 'pending-one',
          'id': 'old',
          'kind': 'entry',
          'base_revision': 2,
          'data': {
            'type': 'expense',
            'date': '2026-11-06',
            'amount': 1234,
            'category': '餐饮',
            'account': '现金',
          },
        },
      ],
    };
    final l = migrateLedger(raw);
    expect(l['pending'][0]['operation_id'], 'pending-one');
    expect(l['pending'][0]['base_revision'], 2);
    expect(l['pending'][0]['data']['base_amount_minor'], 1234);
    expect(raw['entries'][0]['data'].containsKey('base_amount_minor'), false);
    final copy = validateBackup({
      'schema': 2,
      'ledgers': [l],
    }).single;
    final e = (copy['entries'] as List).firstWhere((e) => e['kind'] == 'entry');
    expect(e['data']['category_id'], l['entries'][0]['data']['category_id']);
    expect(copy['pending'], isEmpty);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  test('实际 SQLite 升级保留 state；outbox 写入失败时流水原子回滚', () async {
    final dir = Directory.systemTemp.createTempSync('yousu-migration-');
    final path = '${dir.path}/state.db';
    var db = await openDatabase(
      path,
      version: 1,
      onCreate: (d, _) => d.execute(
        'CREATE TABLE state(id INTEGER PRIMARY KEY,body TEXT NOT NULL)',
      ),
    );
    final old = {
      'schema': 1,
      'active': 'legacy',
      'lastBackup': '',
      'ledgers': [
        {
          'id': 'legacy',
          'name': '旧账',
          'shared': false,
          'role': 'owner',
          'entries': [
            entity('one', 'entry', {
              'date': '2026-11-06',
              'type': 'expense',
              'amount': 1234,
              'account': '微信',
              'category': '餐饮',
            }),
          ],
          'pending': <dynamic>[],
        },
      ],
    };
    final body = jsonEncode(old);
    await db.insert('state', {'id': 1, 'body': body});
    await db.close();
    db = await openLedgerDatabase(path);
    final migrated = (await readState(db))!;
    expect(migrated['schema'], 2);
    expect((await db.query('state')).single['body'], body);
    expect((await db.query('entries', where: "kind='entry'")).length, 1);
    await db.execute(
      "CREATE TRIGGER fail_outbox BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT,'test atomic rollback'); END",
    );
    migrated['ledgers'][0]['entries'][0]['data']['amount'] = 999;
    migrated['ledgers'][0]['pending'] = [
      {'operation_id': 'failure'},
    ];
    await expectLater(
      db.transaction((txn) => writeState(txn, migrated)),
      throwsA(isA<DatabaseException>()),
    );
    final entry = jsonDecode(
      (await db.query('entries', where: "kind='entry'")).single['body']
          as String,
    );
    expect(entry['data']['amount'], 1234);
    await db.close();
    dir.deleteSync(recursive: true);
  });
  test('迁移格式失败时数据库版本与旧快照保留', () async {
    final dir = Directory.systemTemp.createTempSync('yousu-rollback-'),
        path = '${Directory.systemTemp.path}/unused';
    final file = '${dir.path}/bad.db';
    var db = await openDatabase(
      file,
      version: 1,
      onCreate: (d, _) => d.execute(
        'CREATE TABLE state(id INTEGER PRIMARY KEY,body TEXT NOT NULL)',
      ),
    );
    await db.insert('state', {'id': 1, 'body': 'invalid json'});
    await db.close();
    await expectLater(openLedgerDatabase(file), throwsA(anything));
    db = await openDatabase(file);
    expect(await db.getVersion(), 1);
    expect((await db.query('state')).single['body'], 'invalid json');
    await db.close();
    dir.deleteSync(recursive: true);
    expect(path, isNotEmpty);
  });
}
