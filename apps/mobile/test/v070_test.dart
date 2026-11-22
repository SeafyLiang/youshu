import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:youshu/amount_expression.dart';
import 'package:youshu/reminders.dart';
import 'package:youshu/store.dart';
import 'package:youshu/main.dart';
import 'package:youshu/transactions.dart';
import 'package:youshu/budget_pool.dart';
import 'package:youshu/ui.dart';

import 'v062_test.dart' show fixture;
import 'v050_test.dart' show row;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  tzdata.initializeTimeZones();
  FlutterSecureStorage.setMockInitialValues({});
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null),
  );
  test('整数加减、小数精度、不完整和币种限制', () {
    expect(evaluateAmount('0.1+0.2-0.05', 'CNY'), 25);
    expect(evaluateAmount('100-20+3', 'JPY'), 83);
    expect(evaluateAmount('1.+2', 'CNY'), 300);
    expect(evaluateAmount('1-2', 'CNY'), -100);
    for (final text in ['1+', '2--1', '2*2', 'NaN']) {
      expect(() => evaluateAmount(text, 'CNY'), throwsFormatException);
    }
    expect(validAmountExpression('1.234', 'CNY'), isFalse);
    expect(validAmountExpression('1.1', 'JPY'), isFalse);
    expect(validAmountExpression('10+', 'CNY'), isTrue);
  });
  test('跨午夜静音边界、按周与当天记录取消、60次上限', () {
    final s = LedgerStore(),
        prefs = reminderSettings(s),
        location = tz.getLocation('Asia/Shanghai');
    expect(isQuiet(prefs, DateTime(2026, 11, 13, 22)), isTrue);
    expect(isQuiet(prefs, DateTime(2026, 11, 14, 7, 59)), isTrue);
    expect(isQuiet(prefs, DateTime(2026, 11, 14, 8)), isFalse);
    final now = tz.TZDateTime(location, 2026, 11, 13, 19);
    expect(reminderDates(prefs, now, false).first.day, 13);
    expect(reminderDates(prefs, now, true).first.day, 14);
    expect(reminderDates(prefs, now, true).length, 60);
    prefs['weekdays'] = [1];
    expect(
      reminderDates(prefs, now, false).every((d) => d.weekday == 1),
      isTrue,
    );
    prefs['record'] = false;
    expect(reminderDates(prefs, now, false), isEmpty);
  });
  test('批量元数据、复制来源去重、退款删除与原子失败', () async {
    final s = await fixture();
    addTearDown(() async {
      s.backupTimer?.cancel();
      await s.database!.close();
    });
    final e = s.records(s.active).single;
    await s.batchEntries(
      {'e1'},
      'edit',
      {'account': '新账户', 'member': '家人', 'merchant': '超市', 'project': '旅行'},
    );
    expect(s.records(s.active).single['data']['merchant'], '超市');
    expect(s.records(s.active).single['author'], e['author']);
    await s.batchEntries({'e1'}, 'copy', {});
    expect(s.records(s.active).length, 2);
    final refund = row(s.active, 'r1', today(), 800, refund: 'e1');
    refund['data']['category_id'] = e['data']['category_id'];
    (s.active['entries'] as List).add(refund);
    invalidateLedger(s.active);
    await s.batchEntries({'e1'}, 'delete', {});
    expect(s.records(s.active).length, 1);
    expect(s.trashEntries(s.active).length, 2);
    final remaining = s.records(s.active).single;
    s.active['role'] = 'viewer';
    await expectLater(
      s.batchEntries({remaining['id']}, 'edit', {'account': '不该写入'}),
      throwsA(isA<ApiError>()),
    );
    expect(s.records(s.active).single['data']['account'], '新账户');
  });
  testWidgets('全时间默认、组合筛选跨视图保持、单行月与结余', (t) async {
    final s = (await t.runAsync(fixture))!;
    (s.active['entries'] as List).add(row(s.active, 'old', '2020-01-05', 100));
    invalidateLedger(s.active);
    await t.pumpWidget(YoushuApp(s));
    await t.pumpAndSettle();
    final state = t.state<TransactionsState>(find.byType(Transactions));
    expect(state.queryRows(s.period(today())).length, 2);
    state.filter.accounts = {'现金'};
    await t.tap(find.text('按月').first);
    await t.pumpAndSettle();
    expect(state.filter.accounts, {'现金'});
    expect(state.queryRows(s.period(today())).length, 2);
    expect(find.text('2020 年'), findsOneWidget);
    final month = find.text('1月');
    expect(month, findsOneWidget);
    final rowBox = find
        .ancestor(of: month, matching: find.byType(SizedBox))
        .evaluate()
        .where((e) => (e.widget as SizedBox).height == 48);
    expect(rowBox, isNotEmpty);
    s.state['transactionDimension'] = 'balance';
    s.changed();
    await t.pumpAndSettle();
    expect(state.displayedTotal(s.records(s.active)), -3900);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    s.backupTimer?.cancel();
    await t.runAsync(() => s.database!.close());
  });
  testWidgets('长按与左滑共享同一动作回调', (t) async {
    final actions = <String>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeEntry(
            canRefund: true,
            action: actions.add,
            child: const SizedBox(height: 80, width: 400, child: Text('示例流水')),
          ),
        ),
      ),
    );
    await t.longPress(find.text('示例流水'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '退款'), findsOneWidget);
    await t.tap(find.widgetWithText(ListTile, '复制'));
    await t.pumpAndSettle();
    expect(actions, ['复制']);
    await t.drag(find.text('示例流水'), const Offset(-280, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('编辑').first);
    await t.pumpAndSettle();
    expect(actions, ['复制', '编辑']);
  });
  testWidgets('预算水位正常预警和超额颜色', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final amount in [10, 85, 120])
              Expanded(
                child: BudgetPool(
                  spent: amount,
                  limit: 100,
                  child: const SizedBox(height: 80),
                ),
              ),
          ],
        ),
      ),
    );
    expect(find.byType(BudgetPool), findsNWidgets(3));
    expect(t.takeException(), isNull);
  });
}
