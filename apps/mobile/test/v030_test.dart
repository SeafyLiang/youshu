import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/store.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/update_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(system, (call) async => null);
  test('筛选默认全选、取消全选为空、排除父分类覆盖子类与标签交集', () {
    final l = freshLedger('筛选');
    final parent = categoryId(l['id'], 'expense', '餐饮');
    (l['entries'] as List).add(
      entity('child', 'category', {
        'name': '咖啡',
        'type': 'expense',
        'parent_id': parent,
        'order': 50,
      }),
    );
    final rows = [
      entity('a', 'entry', {
        'date': '2026-11-06',
        'time': '08:00',
        'type': 'expense',
        'amount': 100,
        'category_id': 'child',
        'tag_ids': ['work'],
        'original_currency': 'CNY',
      }),
      entity('b', 'entry', {
        'date': '2026-11-06',
        'time': '09:00',
        'type': 'income',
        'amount': 200,
        'category_id': 'salary',
        'tag_ids': [],
        'original_currency': 'CNY',
      }),
    ];
    const p = BookPeriod('2026-11-01', '2026-12-01');
    final f = EntryFilter();
    expect(f.apply(l, rows, p).map((e) => e['id']), ['b', 'a']);
    f.restricted.add('分类');
    expect(f.apply(l, rows, p), isEmpty);
    f.categories.add(parent);
    expect(f.apply(l, rows, p).single['id'], 'a');
    f.excludedTags.add('work');
    expect(f.apply(l, rows, p), isEmpty);
    f.clear('categories');
    f.excludedCategories.add(parent);
    expect(f.apply(l, rows, p).single['id'], 'b');
    f.restricted.add('类型');
    expect(f.apply(l, rows, p), isEmpty);
    f.clear('types');
    expect(f.copy().apply(l, rows, p).single['id'], 'b');
  });
  test('退款限额、预算冲减、原单保护、删除撤销、恢复副本关联和落库', () async {
    final s = LedgerStore();
    s.database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onCreate: (db, _) => createV2(db),
        version: 1,
      ),
    );
    final l = freshLedger('退款');
    s.state['ledgers'] = [l];
    s.state['active'] = l['id'];
    await s.saveEntry({
      'type': 'expense',
      'amount': 10000,
      'date': today(),
      'time': '09:20',
      'category': '餐饮',
      'account': '未指定',
      'note': '午餐',
    });
    final original = s.records(l).single;
    await s.refund(original, 2500);
    expect(s.total(today(), 'expense'), 10000);
    expect(s.total(today(), 'income'), 2500);
    expect(s.refundable(original), 7500);
    await expectLater(s.refund(original, 7501), throwsFormatException);
    await expectLater(
      s.saveEntry(original['data'], existing: original, deleted: true),
      throwsFormatException,
    );
    final refund = s.records(l).firstWhere((e) => isRefund(e['data']));
    final restored = validateBackup(
      jsonDecode(
        jsonEncode({
          'schema': 3,
          'ledgers': [l],
        }),
      ),
    ).single;
    final entries = (restored['entries'] as List)
        .where((e) => e['kind'] == 'entry')
        .toList();
    expect(
      entries.firstWhere((e) => isRefund(e['data']))['data']['refund_of'],
      entries.firstWhere((e) => !isRefund(e['data']))['id'],
    );
    await s.saveEntry(refund['data'], existing: refund, deleted: true);
    expect(s.total(today(), 'expense'), 10000);
    await s.saveEntry(refund['data'], existing: refund);
    expect(s.total(today(), 'expense'), 10000);
    final saved = await readState(s.database!);
    expect(
      saved!['ledgers'][0]['entries'].where((e) => e['kind'] == 'entry').length,
      2,
    );
    await s.database!.close();
  });
  test('更新信息限制 HTTPS 同源和完整校验元数据', () {
    final valid = {
      'version': '0.3.0',
      'build': 4,
      'bytes': 100,
      'sha256': 'a' * 64,
      'url': '/site/downloads/youshu-0.3.0-4.apk',
    };
    expect(
      validateRelease(valid, Uri.parse(releaseEndpoint))['downloadUrl'],
      contains('${Uri.parse(releaseEndpoint).origin}/site/downloads/'),
    );
    for (final patch in [
      {'url': 'https://evil.invalid/app.apk'},
      {'url': 'http://youshu-site.894700104.xyz/app.apk'},
      {'sha256': 'bad'},
      {'bytes': -1},
      {'build': '4'},
    ]) {
      expect(
        () => validateRelease({...valid, ...patch}, Uri.parse(releaseEndpoint)),
        throwsA(anything),
      );
    }
  });
}
