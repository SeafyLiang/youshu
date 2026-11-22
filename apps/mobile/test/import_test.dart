import 'dart:convert';
import 'dart:io';

import 'support/import_fixture.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/bill_import.dart';
import 'package:youshu/category_templates.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  Future<LedgerStore> store() async {
    final s = LedgerStore();
    s.database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: (d, _) => createV2(d)),
    );
    final l = freshLedger('已有账本');
    s.state['ledgers'] = [l];
    s.state['active'] = l['id'];
    await s.persist();
    return s;
  }

  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null),
  );
  test('解析真实结构、保留同值的合法重复行，来源 ID 稳定', () {
    final bytes = fixture([headings, entry(), entry()]);
    final a = parseBillXlsx(bytes, 'test.xlsx'),
        b = parseBillXlsx(bytes, 'renamed.xlsx');
    expect(a.errors, isEmpty);
    expect(a.rows.length, 2);
    expect(a.rows.first.amount, 1234);
    expect(a.rows.first.dateTime, '2020-02-29 23:59:59');
    expect(a.rows.first.id, b.rows.first.id);
    expect(a.rows.first.id, isNot(a.rows.last.id));
  });
  test('阻止负金额、精度损失、非法日期、未知币种、重复来源 ID；零金额显式报告', () {
    final p = parseBillXlsx(
      fixture([
        headings,
        entry(amount: '0.00'),
        entry(amount: '-1'),
        entry(amount: '1.001'),
        entry(date: '2023-02-29 12:00:00'),
        entry(currency: 'XYZ'),
        entry(id: 'same'),
        entry(id: 'same'),
      ]),
      'test.xlsx',
    );
    expect(p.errors.length, 5);
    expect(p.zeroRows.length, 1);
    expect(p.valid.length, 1);
    expect(
      () => parseBillXlsx(Uint8List.fromList([1, 2, 3]), 'bad.xlsx'),
      throwsFormatException,
    );
  });
  test('完整事务导入，多币种分账，重复文件及整理版不会重复', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    final p = parseBillXlsx(
      fixture([
        headings,
        entry(id: 'a'),
        entry(currency: 'USD', id: 'b'),
        entry(amount: '0', id: 'z'),
      ]),
      'test.xlsx',
    );
    await expectLater(
      s.importBills(p, skipZero: false, name: '历史'),
      throwsFormatException,
    );
    expect(s.ledgers.length, 1);
    expect(await s.importBills(p, skipZero: true, name: '历史'), 2);
    expect(s.ledgers.length, 3);
    expect(s.records(s.ledgers.first), isEmpty);
    expect(s.ledgers.skip(1).map((l) => settingsOf(l)['base_currency']), [
      'CNY',
      'USD',
    ]);
    await expectLater(
      s.importBills(p, skipZero: true, name: '重导'),
      throwsFormatException,
    );
    final organized = parseBillXlsx(
      fixture([
        headings,
        entry(id: 'a'),
        entry(currency: 'USD', id: 'b'),
      ], sheetName: '有数导入'),
      '整理.xlsx',
    );
    await expectLater(
      s.importBills(organized, skipZero: true, name: '重导'),
      throwsFormatException,
    );
    final loaded = await readState(s.database!);
    expect((loaded!['ledgers'] as List).length, 3);
    final restored = validateBackup({
      'schema': 3,
      'ledgers': s.ledgers.skip(1).toList(),
    });
    final next = LedgerStore();
    next.state['ledgers'] = restored;
    next.state['active'] = restored.first['id'];
    expect(next.importedIds.contains(p.rows.first.id), isTrue);
    expect(restored.first['import_manifest']['zero_rows'].length, 1);
  });
  test('数据库中途失败回滚内存和磁盘；小组件失败不撤销已成功写入', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    final p = parseBillXlsx(fixture([headings, entry()]), 'test.xlsx');
    final before = jsonEncode(s.state);
    await s.database!.execute(
      "CREATE TRIGGER fail_import BEFORE INSERT ON entries WHEN NEW.kind='entry' BEGIN SELECT RAISE(FAIL,'injected'); END",
    );
    await expectLater(
      s.importBills(p, skipZero: true, name: '历史'),
      throwsA(isA<DatabaseException>()),
    );
    expect(jsonEncode(s.state), before);
    expect((await s.database!.query('ledgers')).length, 1);
    await s.database!.execute('DROP TRIGGER fail_import');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          system,
          (_) async => throw PlatformException(code: 'widget-unavailable'),
        );
    expect(await s.importBills(p, skipZero: true, name: '历史'), 1);
    expect(s.ledgers.length, 2);
  });
  test('推荐分类补充幂等，保留用户名称；隐藏父分类也隐藏子分类选择入口', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    expect(recommendedCategories(s.active), isEmpty);
    final root = s
        .choices('category')
        .firstWhere(
          (e) => e['data']['name'] == '餐饮' && e['data']['parent_id'] == '',
        );
    final child = s
        .choices('category')
        .firstWhere((e) => e['data']['parent_id'] == root['id']);
    await s.saveEntry(
      {...root['data'] as Json, 'archived': true},
      kind: 'category',
      existing: root,
    );
    expect(s.choices('category').any((e) => e['id'] == child['id']), isFalse);
    expect(
      s.choices('category', archived: true).any((e) => e['id'] == child['id']),
      isTrue,
    );
  });

  // 私人文件只在显式传入环境变量时运行；不把账单或金额写入测试输出。
  final source = Platform.environment['YOUSHU_PRIVATE_SOURCE'],
      normalized = Platform.environment['YOUSHU_PRIVATE_NORMALIZED'];
  if (source != null && normalized != null) {
    test('私有完整账单逐笔、总额和批量数据库核对', () async {
      final a = parseBillXlsx(File(source).readAsBytesSync(), '原账单.xlsx');
      final b = parseBillXlsx(File(normalized).readAsBytesSync(), '整理版.xlsx');
      expect(a.errors, isEmpty);
      expect(b.errors, isEmpty);
      expect(a.sourceCount, b.sourceCount);
      final index = {for (final r in a.rows) r.id: r};
      for (final r in b.rows) {
        final old = index[r.id]!;
        expect(
          [r.amount, r.currency, r.dateTime, r.type, r.note],
          [old.amount, old.currency, old.dateTime, old.type, old.note],
        );
      }
      for (final cur in a.currencyCodes) {
        for (final type in ['expense', 'income']) {
          expect(a.total(cur, type), b.total(cur, type));
        }
      }
      final s = await store();
      addTearDown(() => s.database!.close());
      expect(
        await s.importBills(b, skipZero: true, name: '核对'),
        b.valid.length,
      );
      final loaded = await readState(s.database!);
      final count = (loaded!['ledgers'] as List)
          .expand((l) => l['entries'] as List)
          .where((e) => e['kind'] == 'entry')
          .length;
      expect(count, b.valid.length);
      final watch = Stopwatch()..start();
      for (final l in s.ledgers) {
        for (final category in dictionary(l, 'category', type: 'expense')) {
          s.total(today(), 'expense', ledger: l, category: category['id']);
        }
      }
      final queryMs = watch.elapsedMilliseconds;
      watch.reset();
      await s.setBudget(today(), '全部', 100000);
      final saveMs = watch.elapsedMilliseconds;
      stdout.writeln(
        jsonEncode({
          'private_sample_query_ms': queryMs,
          'private_sample_budget_save_ms': saveMs,
        }),
      );
      expect(queryMs, lessThan(1000));
      expect(
        validateBackup({'schema': 3, 'ledgers': s.ledgers}).length,
        s.ledgers.length,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
