import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/main.dart';
import 'package:youshu/store.dart';
import 'package:youshu/ui.dart';
import 'package:youshu/ledger_scope.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/display_settings_page.dart';
import 'package:youshu/preferences_page.dart';

import 'v050_test.dart' show db, row;

Future<LedgerStore> fixture() async {
  final s = LedgerStore();
  s.database = await db();
  final book = freshLedger('日常账本');
  s.state['ledgers'] = [book];
  s.state['active'] = book['id'];
  final entry = row(book, 'e1', today(), 3800);
  entry['data']['category_id'] = dictionary(
    book,
    'category',
    type: 'expense',
  ).firstWhere((c) => c['data']['parent_id'] != '')['id'];
  (book['entries'] as List).add(entry);
  await s.persist();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null),
  );
  test('结余父子分类、标签和退款同口径；收支预算保持原数值', () async {
    final s = await fixture();
    final l = s.active;
    final original = s.records(l).first, cid = original['data']['category_id'];
    final parent = ledgerIndex(l).byId[cid]!['data']['parent_id'];
    final refund = row(l, 'r1', today(), 800, refund: 'e1');
    refund['data']['category_id'] = cid;
    (l['entries'] as List).addAll(<Json>[
      refund,
      entity('tag-x', 'tag', {'name': '报销', 'archived': false}),
      entity('inc', 'entry', {
        ...original['data'] as Json,
        'type': 'income',
        'amount': 10000,
        'base_amount_minor': 10000,
        'original_amount_minor': 10000,
        'category_id': dictionary(l, 'category', type: 'income').first['id'],
      }),
    ]);
    invalidateLedger(l);
    final raw = s.total(today(), 'expense'), budget = s.budgetSpent(today());
    expect(BalanceRule(l).total(s.records(l)), 7000);
    await s.setBalanceExclusions({parent}, {});
    expect(BalanceRule(l).total(s.records(l)), 10000);
    expect(s.total(today(), 'expense'), raw);
    expect(s.budgetSpent(today()), budget);
    original['data']['tag_ids'] = ['tag-x'];
    invalidateLedger(l);
    await s.setBalanceExclusions({}, {'tag-x'});
    expect(
      BalanceRule(l).total(s.records(l)),
      10000,
    ); // refund follows the original tag
    final restored = validateBackup({
      'schema': 5,
      'ledgers': [l],
    }).single;
    expect(BalanceRule(restored).total(ledgerIndex(restored).records), 10000);
    final read = (await readState(s.database!))!;
    expect(read['ledgers'][0]['balance_exclusions']['tags'], ['tag-x']);
    await s.setBalanceExclusions({}, {});
    expect(BalanceRule(l).total(s.records(l)), 7000);
    s.backupTimer?.cancel();
    await s.database!.close();
  });
  test('多账本同名分类按来源独立排除，规则修改刷新合并缓存', () async {
    final s = await fixture(), a = s.active, b = freshLedger('家庭');
    final e = row(b, 'b1', today(), 2000);
    e['data']['category_id'] = s.records(a).first['data']['category_id'];
    (b['entries'] as List).add(e);
    s.state['ledgers'] = [a, b];
    s.state['viewLedgers'] = [a['id'], b['id']];
    expect(BalanceRule(s.view).total(ledgerIndex(s.view).records), -5800);
    await s.setBalanceExclusions({
      s.records(a).first['data']['category_id'],
    }, {});
    expect(BalanceRule(s.view).total(ledgerIndex(s.view).records), -2000);
    final merged = composeLedgers([a, b], settingsOf(a), deduplicate: true);
    expect(BalanceRule(merged).total(ledgerIndex(merged).records), -5800);
    s.backupTimer?.cancel();
    await s.database!.close();
  });
  test('结余配置写入失败恢复原规则', () async {
    final s = await fixture();
    await s.database!.close();
    await expectLater(
      s.setBalanceExclusions({
        s.records(s.active).first['data']['category_id'],
      }, {}),
      throwsA(anything),
    );
    expect(BalanceRule(s.active).active, isFalse);
    s.backupTimer?.cancel();
  });
  testWidgets('字号连续预览不写入，松手一次保存并重启恢复', (t) async {
    final s = (await t.runAsync(fixture))!;
    await t.pumpWidget(YoushuApp(s));
    await t.pumpAndSettle();
    final context = t.element(find.byType(Home));
    Navigator.of(context)
        .push(AppPageRoute(builder: (_) => DisplaySettingsPage(s)));
    await t.pumpAndSettle();
    final slider = t.widget<Slider>(
      find.byKey(const ValueKey('font-scale-slider')),
    );
    expect(slider.divisions, isNull);
    slider.onChanged!(1.123);
    await t.pump();
    expect(s.fontPreview.value, 1.123);
    expect(s.state['fontScale'], isNull);
    expect(
      MediaQuery.textScalerOf(t.element(find.text('午餐'))).scale(14),
      closeTo(15.722, .001),
    );
    await t.runAsync(() async {
      slider.onChangeEnd!(1.123);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    });
    await t.pumpAndSettle();
    expect(s.fontScale, 1.123);
    expect(
      (await t.runAsync(() => readState(s.database!)))!['fontScale'],
      1.123,
    );
    await t.pumpWidget(const SizedBox());
    s.backupTimer?.cancel();
    await s.database!.close();
  });
  for (final size in [
    const Size(440, 956),
    const Size(420, 948),
    const Size(360, 812),
    const Size(720, 440),
  ]) {
    for (final scale in [.8, .95, 1.4]) {
      testWidgets('布局 ${size.width}x${size.height} 字号 $scale 系统1.6', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = size;
        t.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final s = (await t.runAsync(fixture))!;
        s.state['fontScale'] = scale;
        await t.pumpWidget(YoushuApp(s));
        await t.pumpAndSettle();
        expect(
          MediaQuery.textScalerOf(t.element(find.byType(Home))).scale(14),
          closeTo(14 * scale, .001),
        );
        for (final label in ['分析', '预算', '统计', '我的', '流水']) {
          await t.tap(find.text(label).last);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
        final context = t.element(find.byType(Home));
        Navigator.of(context)
            .push(AppPageRoute(builder: (_) => PreferencesPage(s)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        Navigator.of(t.element(find.byType(PreferencesPage))).pop();
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('记一笔'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        s.backupTimer?.cancel();
        await s.database!.close();
      });
    }
  }
  test('系统无障碍缩放是显式可选，透明系统栏保留正确明暗', () {
    expect(
      const AppTextScaler(TextScaler.linear(2), 1.1).scale(14),
      closeTo(30.8, .001),
    );
    for (final b in Brightness.values) {
      final style = appSystemBars(b);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(
        style.statusBarIconBrightness,
        b == Brightness.dark ? Brightness.light : Brightness.dark,
      );
    }
  });
}
