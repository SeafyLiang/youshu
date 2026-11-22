import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youshu/haptics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/store.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/payment_import.dart';
import 'package:youshu/gb18030.dart';
import 'package:youshu/ledger_scope.dart';
import 'package:youshu/merge_fx.dart';
import 'package:youshu/statistics_page.dart';
import 'package:youshu/icon_catalog.dart';
import 'package:youshu/category_templates.dart';
import 'package:youshu/main.dart';
import 'package:youshu/transactions.dart';

import 'support/import_fixture.dart';
import 'v050_test.dart' show row, db;
import 'performance_test.dart' show largeStore;

const aliHeader = '交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,';
Json alipay([String id = 'A0001', String state = '等待确认收货']) => parseImportFile((
  Uint8List.fromList(
    utf8.encode(
      '说明\n$aliHeader\n2026-10-10 12:30:01,餐饮美食,测试商户,,午餐,支出,20.00,支付宝,$state,$id,,,\n',
    ),
  ),
  'alipay.csv',
));
const wxHeader = [
  '交易时间',
  '交易类型',
  '交易对方',
  '商品',
  '收/支',
  '金额(元)',
  '支付方式',
  '当前状态',
  '交易单号',
  '商户单号',
  '备注',
];
Json wechat() => parseImportFile((
  fixture([
    ['说明'],
    wxHeader,
    [
      '2026-10-10 12:30:00',
      '商户消费',
      '测试商户',
      '商品',
      '支出',
      '¥20.00',
      '零钱',
      '已退款(¥5.00)',
      'W001',
      'M001',
      '/',
    ],
    [
      '2026-10-11 13:00:00',
      '商户退款',
      '测试商户',
      '退款',
      '收入',
      '¥5.00',
      '零钱',
      '已退款¥5.00',
      'R001',
      '',
      '/',
    ],
  ], sheetName: 'Sheet1'),
  'wechat.xlsx',
));
Future<LedgerStore> store() async {
  final s = LedgerStore();
  s.database = await db();
  final l = freshLedger('测试');
  s.state['ledgers'] = [l];
  s.state['active'] = l['id'];
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  test('iOS触感档位、关闭与偏好恢复', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(system, null),
    );
    for (final level in ['off', 'light', 'medium', 'strong']) {
      s.state['keyHaptic'] = level;
      await keyFeedback(s);
    }
    expect(calls.map((c) => c.arguments), ['light', 'medium', 'strong']);
    await s.persist();
    expect((await readState(s.database!))!['keyHaptic'], 'strong');
  });
  test('GB18030严格解码、CSV换行引号及错误编码', () {
    expect(decodeGb18030([0xd6, 0xd0, 0xce, 0xc4]), '中文');
    expect(decodeGb18030([148, 57, 252, 54]), '😀');
    expect(() => decodeGb18030([0x81, 0x30]), throwsFormatException);
    expect(readCsv('a,"b,c","d\ne"\r\nx,y,z'), [
      ['a', 'b,c', 'd\ne'],
      ['x', 'y', 'z'],
    ]);
    expect(() => readCsv('a,"b'), throwsFormatException);
  });
  test('支付宝付款待收货正常，关闭交易跳过，稳定订单身份', () {
    final a = alipay(), b = alipay('A0001', '交易成功');
    expect(a['rows'].single['status'], 'ready');
    expect(a['rows'].single['key'], b['rows'].single['key']);
    expect(alipay('X', '交易关闭')['rows'].single['status'], 'skipped');
    final d = reviewImport((b, List<Json>.from(a['rows'])));
    expect(d['rows'].single['status'], 'review');
  });
  test('微信退款不重复计算，部分提交和草稿恢复', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    final d = reviewImport((wechat(), <Json>[]));
    expect(d['rows'][1]['status'], 'review');
    await s.saveImportDraft(d);
    expect(await s.commitImportDraft(d, target: s.active['id'], name: ''), 1);
    expect(s.total('2026-10', 'expense'), 2000);
    expect(s.total('2026-10', 'income'), 0);
    final recovered = LedgerStore()
      ..database = s.database
      ..state = (await readState(s.database!))!;
    final draft = Map<String, dynamic>.from(recovered.state['importDrafts'][0]);
    final refund = draft['rows'][1];
    refund['refund_of'] = draft['rows'][0]['id'];
    refund['status'] = 'ready';
    refund['reviewed'] = true;
    expect(
      await recovered.commitImportDraft(
        draft,
        target: recovered.active['id'],
        name: '',
      ),
      1,
    );
    expect(recovered.total('2026-10', 'expense'), 2000);
    expect(recovered.total('2026-10', 'income'), 500);
    final repeated = reviewImport((wechat(), recovered.importMatchRows()));
    expect(
      (repeated['rows'] as List).every((r) => r['status'] == 'duplicate'),
      isTrue,
    );
    final copy = validateBackup({'schema': 4, 'ledgers': recovered.ledgers})
        .single;
    expect(ledgerIndex(copy).refunds.length, 1);
  });
  test('相同金额疑似重复需确认，事务失败不留下半批数据', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    final d = alipay();
    await s.commitImportDraft(d, target: s.active['id'], name: '');
    final weak = reviewImport((alipay('other'), s.importMatchRows()));
    expect(weak['rows'].single['status'], 'review');
    final count = s.records(s.active).length;
    await s.database!.execute(
      "CREATE TRIGGER fail_import BEFORE INSERT ON entries WHEN new.kind='entry' BEGIN SELECT RAISE(FAIL,'forced'); END",
    );
    await expectLater(
      s.commitImportDraft(alipay('third'), target: s.active['id'], name: ''),
      throwsA(anything),
    );
    expect(s.records(s.active).length, count);
    expect((await readState(s.database!))!['importHistory'].length, 1);
  });
  test('每日分配守恒、修改一日不改变其他日、月额不足阻止保存', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    await s.setCycle(10);
    await s.setBudget('2024-02', '全部', 2901);
    final old = s.dailyBudgets('2024-02');
    expect(old.length, 29);
    expect(old.values.reduce((a, b) => a + b), 2901);
    await s.setDailyBudget('2024-02-15', 300);
    final next = s.dailyBudgets('2024-02');
    for (final e in old.entries) {
      if (e.key != '2024-02-15') expect(next[e.key], e.value);
    }
    expect(s.budget('2024-02', '全部'), 2901 + 300 - old['2024-02-15']!);
    await s.setBudget('2024-02', '全部', 4000);
    expect(s.dailyBudgets('2024-02')['2024-02-15'], 300);
    await expectLater(s.setBudget('2024-02', '全部', 200), throwsFormatException);
    await s.setCycle(1);
    expect(s.dailyBudgets('2024-02')['2024-02-15'], 300);
  });
  test('账期迁移保留邻月手动日额度，预览不写入；备份校验每日分配', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    await s.setBudget('2024-02', '全部', 2900);
    await s.setDailyBudget('2024-02-05', 500);
    final before = jsonEncode(s.active);
    final preview = await s.setCycle(10, preview: true);
    expect(jsonEncode(s.active), before);
    expect(preview.length, 2);
    await s.setCycle(10);
    expect(s.dailyBudgets('2024-02-05')['2024-02-05'], 500);
    final backup = {'schema': 4, 'ledgers': s.ledgers};
    expect(validateBackup(backup), hasLength(1));
    final corrupt = jsonDecode(jsonEncode(backup)) as Json;
    final b = (corrupt['ledgers'][0]['entries'] as List).firstWhere(
      (e) => e['kind'] == 'budget',
    );
    b['data']['daily_allocations']['2024-02-11'] = 99999;
    expect(() => validateBackup(corrupt), throwsFormatException);
  });
  test('预算排除父级与标签，退款跟随原消费且普通统计保持', () async {
    final s = await store();
    addTearDown(() => s.database!.close());
    final l = s.active, cat = dictionary(l, 'category', type: 'expense').first;
    final a = row(l, 'a', '2026-10-10', 2000),
        r = row(l, 'r', '2026-10-11', 500, refund: 'a');
    (l['entries'] as List).addAll(<Json>[a, r]);
    await s.persist();
    expect(s.budgetSpent('2026-10'), 1500);
    await s.setBudgetExclusions({cat['id']}, {});
    expect(s.budgetSpent('2026-10'), 0);
    expect(s.total('2026-10', 'expense'), 2000);
    expect(s.total('2026-10', 'income'), 500);
  });
  test('跨币合并人民币快照、退款比例、来源去重与原本不变', () {
    final usd = freshLedger('USD', currency: 'USD'), cny = freshLedger('CNY');
    final a = row(usd, 'a', '2026-10-10', 300),
        r1 = row(usd, 'r1', '2026-10-11', 100, refund: 'a'),
        r2 = row(usd, 'r2', '2026-10-12', 200, refund: 'a');
    for (final e in [a, r1, r2]) {
      e['data'].addAll({
        'base_currency': 'USD',
        'original_currency': 'USD',
        'currency_scale': 2,
        'fx_rate_date': e['data']['date'],
        'fx_source': 'identity',
        'fx_mode': 'identity',
      });
    }
    (usd['entries'] as List).addAll(<Json>[a, r1, r2]);
    final original = jsonEncode(usd);
    final composed = composeLedgers(
      [usd, cny],
      settingsOf(usd),
      deduplicate: true,
    );
    final converted = convertMergedCny((
      composed,
      {
        'USD/2026-10-10': {
          'rate': '7.123',
          'date': '2026-10-10',
          'source': 'manual',
        },
      },
    ));
    expect(settingsOf(converted)['base_currency'], 'CNY');
    expect(jsonEncode(usd), original);
    expect(
      ledgerIndex(converted).records
          .fold<int>(0, (n, e) => n + signedAmount(e['data'])),
      0,
    );
    expect(
      validateBackup({
        'schema': 4,
        'ledgers': [converted],
      }).length,
      1,
    );
  });
  test('重名分类按稳定ID聚合，维度明细合计一致，图标不重复', () {
    final l = freshLedger('统计'),
        cats = dictionary(l, 'category', type: 'expense');
    final a = row(l, 'a', '2026-10-10', 100),
        b = row(l, 'b', '2026-10-10', 200);
    b['data']['category_id'] = cats[1]['id'];
    cats[1]['data']['name'] = cats[0]['data']['name'];
    (l['entries'] as List).addAll(<Json>[a, b]);
    final buckets = statisticBuckets(l, [a, b], 'expense', '二级分类', 'CNY');
    expect(buckets.length, 2);
    expect(buckets.map((b) => b.id).toSet().length, 2);
    expect(buckets.fold<int>(0, (n, b) => n + b.amount), 300);
    expect(
      recommendedIconNames.values.toSet().length,
      recommendedIconNames.length,
    );
    l['icon_overrides'] = {cats.first['id']: 'ant:star'};
    expect(visualIcon(l, cats.first), 'ant:star');
  });
  test('6000/10000/20000热查询与预算增量写入', () async {
    final results = {};
    for (final count in [6000, 10000, 20000]) {
      final s = largeStore(count);
      s.database = await db();
      await s.persist();
      s.budgetSpent('2026-07');
      final w = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        s.budgetSpent('2026-07');
      }
      final warm = w.elapsedMicroseconds / 1000;
      expect(warm, lessThan(100));
      w.reset();
      await s.setBudget('2026-07', '全部', 123456);
      final save = w.elapsedMilliseconds;
      if (count == 10000) expect(save, lessThan(200));
      results['$count'] = {'warm_100_queries_ms': warm, 'budget_save_ms': save};
      await s.database!.close();
    }
    stdout.writeln(jsonEncode({'v060_performance': results}));
  });
  test('消费跨基准币去重后退款仍沿用来源基准，全额准确抵消', () {
    final usd = freshLedger('USD', currency: 'USD'), cny = freshLedger('CNY');
    final a = row(usd, 'a', '2026-10-10', 1000),
        r = row(usd, 'r', '2026-10-11', 1000, refund: 'a'),
        b = row(cny, 'b', '2026-10-10', 7123);
    for (final e in [a, r]) {
      e['data']['base_currency'] = 'USD';
      e['data']['original_currency'] = 'USD';
      e['data']['fx_mode'] = 'identity';
    }
    a['data']['source_key'] = 'alipay:purchase';
    b['data']['source_key'] = 'alipay:purchase';
    b['data']['original_currency'] = 'USD';
    b['data']['original_amount_minor'] = 1000;
    b['data']['fx_rate'] = '7.123';
    b['data']['fx_mode'] = 'auto';
    (usd['entries'] as List).addAll(<Json>[a, r]);
    (cny['entries'] as List).add(b);
    final l = convertMergedCny((
      composeLedgers([usd, cny], settingsOf(usd), deduplicate: true),
      <String, Json>{},
    ));
    expect(ledgerIndex(l).records.length, 2);
    expect(
      ledgerIndex(l).records
          .fold<int>(0, (n, e) => n + signedAmount(e['data'])),
      0,
    );
    expect(
      ledgerIndex(l).records
          .where((e) => isRefund(e['data']))
          .single['data']['amount'],
      7123,
    );
  });
  test('重叠平台订单跨币本合并优先保留人民币快照', () {
    final a = freshLedger('USD', currency: 'USD'), b = freshLedger('CNY');
    final x = row(a, 'a', '2026-10-10', 1000),
        y = row(b, 'b', '2026-10-10', 7123);
    for (final e in [x, y]) {
      e['data']['source_key'] = 'alipay:test';
      e['data']['original_currency'] = 'USD';
      e['data']['original_amount_minor'] = 1000;
    }
    x['data']['base_currency'] = 'USD';
    x['data']['fx_mode'] = 'identity';
    y['data']['fx_rate'] = '7.123';
    y['data']['fx_mode'] = 'auto';
    (a['entries'] as List).add(x);
    (b['entries'] as List).add(y);
    final merged = convertMergedCny((
      composeLedgers([a, b], settingsOf(a), deduplicate: true),
      <String, Json>{},
    ));
    expect(ledgerIndex(merged).records.length, 1);
    expect(ledgerIndex(merged).records.single['data']['amount'], 7123);
  });
  test('私有支付宝与微信完整真实样本只读解析', () {
    final paths = [
      Platform.environment['YOUSHU_ALIPAY'],
      Platform.environment['YOUSHU_WECHAT'],
    ];
    if (paths.any((p) => p == null)) return;
    final expectedPath = Platform.environment['YOUSHU_EXPECTATIONS'];
    final expected = expectedPath == null
        ? <String, dynamic>{}
        : jsonDecode(File(expectedPath).readAsStringSync()) as Json;
    for (final path in paths) {
      final f = File(path!),
          d = parseImportFile((f.readAsBytesSync(), f.uri.pathSegments.last));
      expect(d['errors'], isEmpty);
      expect((d['rows'] as List).length, d['platform'] == 'alipay' ? 33 : 25);
      for (final r in d['rows']) {
        if (expected.isNotEmpty) {
          final e = expected[r['key']];
          expect(e, isNotNull);
          expect(r['amount'], e['amount']);
          expect(r['dateTime'], e['dateTime']);
          expect(r['source_status'], e['state']);
        }
        expect(r['original'], isNotEmpty);
        expect(r['dateTime'].length, 19);
        expect(r['amount'], greaterThanOrEqualTo(0));
      }
      final review = reviewImport((d, <Json>[]));
      if (d['platform'] == 'wechat') {
        expect(
          (review['rows'] as List).where((r) => r['refund'] == true).length,
          1,
        );
      }
    }
  });
  testWidgets('全部时间列表可跨月浏览，不受旧加载窗口限制', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final s = largeStore(12), now = DateTime.now();
    var i = 0;
    for (final e in s.records(s.active)) {
      e['data']['date'] = dateKey(DateTime(now.year, now.month - i++, 1));
    }
    invalidateLedger(s.active);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null);
    await t.pumpWidget(YoushuApp(s));
    await t.pumpAndSettle();
    final state = t.state<TransactionsState>(find.byType(Transactions)),
        start = state.visiblePeriod;
    for (var n = 0; n < 4; n++) {
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -550));
      await t.pumpAndSettle();
    }
    expect(state.queryRows(s.period(today())).length, 12);
    expect(state.visiblePeriod.compareTo(start), lessThan(0));
    expect(state.filter.start, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('四Tab记忆、预算视图与统计下钻返回', (t) async {
    t.view.physicalSize = const Size(430, 932);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final s = largeStore(100);
    for (final e in s.records(s.active)) {
      e['data']['date'] = today();
    }
    invalidateLedger(s.active);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null);
    await t.pumpWidget(YoushuApp(s));
    await t.pumpAndSettle();
    await t.tap(find.text('分析').last);
    await t.pumpAndSettle();
    await t.tap(find.text('预算').last);
    await t.pumpAndSettle();
    await t.tap(find.text('年').last);
    await t.pumpAndSettle();
    expect(find.text('1月'), findsOneWidget);
    await t.tap(find.text('统计').last);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('条形图').first);
    await t.pumpAndSettle();
    await t.tap(find.text('分析').last);
    await t.pumpAndSettle();
    await t.tap(find.text('预算').last);
    await t.pumpAndSettle();
    expect(find.text('1月'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('流水').last);
    await t.pumpAndSettle();
    await t.tap(find.text('按月'));
    await t.pumpAndSettle();
    expect(
      t.state<TransactionsState>(find.byType(Transactions)).monthly,
      isTrue,
    );
  });
}
