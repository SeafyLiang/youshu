import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/main.dart';
import 'package:youshu/store.dart';
import 'package:youshu/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  testWidgets('记账落库、预算、多账本与删除闭环', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async => null);
    final s = LedgerStore();
    s.database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => createV2(db),
      ),
    );
    final l = freshLedger('验收日常');
    s.state['ledgers'] = [l];
    s.state['active'] = l['id'];
    await tester.pumpWidget(YoushuApp(s));
    await tester.pumpAndSettle();
    expect(find.text('从今天的第一笔开始'), findsOneWidget);
    await tester.tap(find.byTooltip('记一笔'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12.34');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存账目'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(s.total(today().substring(0, 7), 'expense'), 1234);
    final stored = jsonDecode(
      (await s.database!.query('entries', where: "kind='entry'")).single['body']
          as String,
    );
    expect(stored['data']['amount'], 1234);
    await tester.tap(find.text('分析'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预算'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '100.00');
    await tester.tap(find.text('保存'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(s.budget(today().substring(0, 7), '全部'), 10000);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('¥87.66'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .join('|'),
    );
    expect(find.text('本期剩余'), findsOneWidget);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账本管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建账本'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旅行');
    await tester.tap(find.text('保存'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('CNY · 人民币（默认）'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(s.active['name'], '旅行');
    expect(s.records(s.active), isEmpty);
    await tester.tap(find.text('验收日常'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('流水').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除账目'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(s.total(today().substring(0, 7), 'expense'), 0);
    expect(s.records(s.active), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await s.database!.close();
  });
}
