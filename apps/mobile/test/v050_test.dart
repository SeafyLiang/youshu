import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/store.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/ledger_scope.dart';
import 'package:youshu/statistics_page.dart';
import 'package:youshu/filter_picker.dart';
import 'package:youshu/icon_catalog.dart';
import 'package:youshu/icon_names.dart';
import 'package:youshu/transactions.dart';

import 'performance_test.dart' show largeStore;

Future<Database> db() => databaseFactoryFfiNoIsolate.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(version: 2, onCreate: (d, _) => createV2(d)),
);
Json row(Json l, String id, String date, int amount, {String? refund}) =>
    entity(id, 'entry', {
      'type': 'expense',
      'date': date,
      'time': '12:30',
      'category_id': dictionary(l, 'category', type: 'expense').first['id'],
      'category': '餐饮',
      'tag_ids': <String>[],
      'account': '现金',
      'note': '测试',
      'amount': amount,
      'base_amount_minor': amount,
      'base_currency': 'CNY',
      'original_amount_minor': amount,
      'original_currency': 'CNY',
      'fx_rate': '1',
      'fx_mode': 'manual',
      'refund_of': ?refund,
    });
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  test('历史账期重新分组，预算迁移，缓存失效并可重新读取', () async {
    final s = LedgerStore(), l = freshLedger('历史');
    s.database = await db();
    addTearDown(() => s.database!.close());
    s.state['ledgers'] = [l];
    s.state['active'] = l['id'];
    (l['entries'] as List).addAll(<Json>[
      row(l, 'a', '2023-02-09', 100),
      row(l, 'b', '2023-02-10', 200),
      row(l, 'c', '2023-03-09', 300),
    ]);
    await s.persist();
    await s.setBudget('2023-02', '全部', 900);
    expect(s.total('2023-02', 'expense'), 300);
    await s.setCycle(10);
    expect(s.total('2023-02', 'expense'), 500);
    expect(s.total('2023-01', 'expense'), 100);
    expect(s.budget('2023-02', '全部'), 900);
    expect(s.records(l).map((e) => e['data']['date']).toSet(), {
      '2023-02-09',
      '2023-02-10',
      '2023-03-09',
    });
    expect(s.period('2023-02').start, '2023-02-10');
    await s.setCycle(31);
    expect(s.period('2023-02').start, '2023-02-28');
    expect(s.period('2024-02').start, '2024-02-29');
    expect(s.budget('2023-02', '全部'), 900);
    final reload = LedgerStore()..state = (await readState(s.database!))!;
    expect(reload.period('2023-02').id, s.period('2023-02').id);
    expect(reload.total('2023-02', 'expense'), 300);
    expect(l['cycle_history'].length, 2);
  });
  test('增量写库不重写未变流水，偏好保存不带账本，删除与失败可重试', () async {
    final d = await db(), writer = StateWriter(), s = largeStore(6000);
    addTearDown(d.close);
    await writer.write(d, encodePersistence((s.state, false)));
    expect(writer.lastEntryWrites, greaterThan(6000));
    await writer.write(d, encodePersistence((s.state, false)));
    expect(writer.lastEntryWrites, 0);
    final rows = s.active['entries'] as List, target = rows.last as Json;
    target['data'] = {...target['data'] as Json, 'note': '修改'};
    await writer.write(d, encodePersistence((s.state, false)));
    expect(writer.lastEntryWrites, 1);
    s.state['theme'] = 'dark';
    final pref = encodePersistence((s.state, true));
    expect(pref.containsKey('ledgers'), false);
    await writer.write(d, pref, preferencesOnly: true);
    expect(writer.lastEntryWrites, 0);
    rows.remove(target);
    await writer.write(d, encodePersistence((s.state, false)));
    expect(
      (await d.query('entries', where: 'id=?', whereArgs: [target['id']])),
      isEmpty,
    );
    final previous = writer.last;
    final bad =
        jsonDecode(jsonEncode(encodePersistence((s.state, false)))) as Json;
    bad['ledgers'][0]['entries']['invalid'] = {
      'kind': null,
      'book_date': null,
      'body': '{}',
    };
    await expectLater(writer.write(d, bad), throwsA(isA<DatabaseException>()));
    expect(identical(writer.last, previous), true);
    await writer.write(d, encodePersistence((s.state, false)));
    expect((await readState(d))!['theme'], 'dark');
  });
  test('多本查看保留来源，合并仅去重确切来源，退款/备份后关系完整', () {
    final a = freshLedger('甲'), b = freshLedger('乙');
    (a['entries'] as List).addAll(<Json>[
      row(a, 'a', '2026-11-01', 1000),
      row(a, 'r', '2026-11-02', 200, refund: 'a'),
    ]);
    (b['entries'] as List).addAll(<Json>[
      row(b, 'b', '2026-11-01', 1000),
      row(b, 's', '2026-11-03', 300, refund: 'b'),
      row(b, 'different', '2026-11-01', 1000),
    ]);
    a['import_manifest'] = {
      'rows': {
        'a': {'source_id': 'same-purchase'},
      },
    };
    b['import_manifest'] = {
      'rows': {
        'b': {'source_id': 'same-purchase'},
      },
    };
    final view = composeLedgers([a, b], settingsOf(a));
    expect(ledgerIndex(view).records.length, 5);
    expect(
      ledgerIndex(view).records.every((e) => e['source_ledger_id'] != null),
      true,
    );
    final merged = composeLedgers([a, b], settingsOf(a), deduplicate: true);
    final idx = ledgerIndex(merged);
    expect(idx.records.length, 4);
    for (final r in idx.records.where((e) => isRefund(e['data']))) {
      expect(idx.byId[r['data']['refund_of']], isNotNull);
    }
    expect(
      idx.records.fold<int>(0, (n, e) => n + signedAmount(e['data'])),
      1500,
    );
    final copy = validateBackup({
      'schema': 3,
      'ledgers': [merged],
    }).single;
    final again = composeLedgers(
      [merged, copy],
      settingsOf(a),
      deduplicate: true,
    );
    expect(ledgerIndex(again).records.length, 4);
  });
  test('统计退款计收入、多标签各自计入、分币种及分类排除', () {
    final l = freshLedger('图表'),
        a = row(l, 'a', '2026-11-01', 1000),
        r = row(l, 'r', '2026-11-02', 200, refund: 'a');
    (l['entries'] as List).addAll(<Json>[
      entity('tag1', 'tag', {'name': '旅行', 'order': 0}),
      entity('tag2', 'tag', {'name': '工作', 'order': 1}),
      a,
      r,
    ]);
    a['data']['tag_ids'] = ['tag1', 'tag2'];
    r['data']['tag_ids'] = ['tag1'];
    final stats = aggregateStatistics(
      l,
      ledgerIndex(l).records,
      'expense',
      '标签',
      'CNY',
    );
    expect(stats, {'旅行': 1000, '工作': 1000});
    expect(
      aggregateStatistics(l, ledgerIndex(l).records, 'income', '标签', 'CNY'),
      {'旅行': 200},
    );
    expect(
      aggregateStatistics(l, ledgerIndex(l).records, 'expense', '标签', 'USD'),
      isEmpty,
    );
    final f = EntryFilter()..excludedCategories = {a['data']['category_id']};
    expect(
      f.apply(
        l,
        ledgerIndex(l).records,
        const BookPeriod('2026-11-01', '2026-12-01'),
      ),
      isEmpty,
    );
  });
  test('混合基准币的金额范围和排序不直接混算', () {
    final c = freshLedger('人民币'), u = freshLedger('美元', currency: 'USD');
    final a = row(c, 'c', '2026-11-01', 20000),
        b = row(u, 'u', '2026-11-01', 10000);
    b['data']['base_currency'] = 'USD';
    b['data']['original_currency'] = 'USD';
    (c['entries'] as List).add(a);
    (u['entries'] as List).add(b);
    final view = composeLedgers([c, u], settingsOf(c)),
        p = const BookPeriod('2026-11-01', '2026-12-01');
    final f = EntryFilter()..min = 100;
    expect(
      f
          .apply(view, ledgerIndex(view).records, p)
          .map((e) => e['data']['base_currency']),
      ['CNY'],
    );
    f.originalAmount = true;
    f.currencies = {'USD'};
    expect(
      f
          .apply(view, ledgerIndex(view).records, p)
          .single['data']['base_currency'],
      'USD',
    );
    final sorted = (EntryFilter()..sort = 'amount_asc').apply(
      view,
      ledgerIndex(view).records,
      p,
    );
    expect(sorted.map((e) => e['data']['base_currency']), ['CNY', 'USD']);
  });

  test('图标库与上传验证，SVG 转为有限尺寸 PNG', () async {
    expect(antIconNames.length, 447);
    expect(
      () => sanitizeSvg('<svg><script>alert(1)</script></svg>'),
      throwsFormatException,
    );
    expect(
      () => sanitizeSvg('<svg><image href="https://example.com/a.png"/></svg>'),
      throwsFormatException,
    );
    final png = await iconPng(
      Uint8List.fromList(
        utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="10" fill="#126C62"/></svg>',
        ),
      ),
      'test.svg',
    );
    expect(IconCatalog.validPng(png), true);
    final ledger = {
      'custom_icons': {'custom:test': base64Encode(png)},
    };
    IconCatalog.register(ledger);
    expect(IconCatalog.custom['custom:test'], png);
  });
  testWidgets('父子筛选原位展开，6000 条流水仅构建可见项', (t) async {
    final parent = entity('p', 'category', {
          'name': '父级',
          'parent_id': '',
          'order': 1,
        }),
        child = entity('c', 'category', {
          'name': '子级',
          'parent_id': 'p',
          'order': 0,
        });
    await t.pumpWidget(
      MaterialApp(
        home: FilterTreePicker(
          title: '分类',
          labels: const {'c': '子级', 'p': '父级'},
          categories: [child, parent],
          selected: const {'p'},
        ),
      ),
    );
    expect(find.text('子级'), findsNothing);
    await t.tap(find.byTooltip('展开 父级'));
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.text('子级')).dy,
      greaterThan(t.getTopLeft(find.text('父级')).dy),
    );
    final s = largeStore(6000);
    s.state['transactionFilters'] = {
      s.active['id']:
          (EntryFilter()
                ..start = '2020-01-01'
                ..end = '2027-01-01')
              .toJson(),
    };
    var builds = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Transactions(
            s,
            periodKey: '2026-11',
            tile: (e) {
              builds++;
              return SizedBox(height: 62, child: Text(e['id']));
            },
            add: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(builds, lessThan(30));
    await t.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await t.pumpAndSettle();
    expect(builds, lessThan(60));
  });
}
