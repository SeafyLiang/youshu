import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/main.dart';
import 'package:youshu/preferences_page.dart';
import 'package:youshu/store.dart';
import 'package:youshu/ui.dart';

LedgerStore _demoStore() {
  final s = LedgerStore();
  final l = freshLedger('日常账本');
  s.state['ledgers'] = [l];
  s.state['active'] = l['id'];
  final cat = s.choices('category', type: 'expense').first;
  l['entries'].add({
    'id': 'e-demo-1',
    'kind': 'entry',
    'data': {
      'type': 'expense',
      'amount': 2800,
      'original_amount_minor': 2800,
      'original_currency': 'CNY',
      'base_currency': 'CNY',
      'base_amount_minor': 2800,
      'date': today(),
      'time': '09:30',
      'category_id': cat['id'],
      'category': cat['data']['name'],
      'tag_ids': [],
      'account': '微信',
      'to_account': '',
      'note': '拿铁',
    },
  });
  return s;
}

void main() {
  testWidgets('偏好设置可切换三种主题风格并实时更新调色板', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async => null);

    final s = _demoStore();
    await t.pumpWidget(YoushuApp(s));
    await t.pumpAndSettle();

    // 默认深翠青瓷
    expect(
      AppPalette.of(t.element(find.byType(Home))).style,
      AppThemeStyle.emerald,
    );

    // 进入我的 -> 偏好设置
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await t.tap(find.text('偏好设置'));
    await t.pumpAndSettle();
    expect(find.byType(PreferencesPage), findsOneWidget);

    // 滚动并切换极简石墨黑
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('theme-style-mono')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const ValueKey('theme-style-mono')));
    await t.pumpAndSettle();
    expect(s.state['themeStyle'], 'mono');
    expect(
      AppPalette.of(t.element(find.byType(PreferencesPage))).style,
      AppThemeStyle.mono,
    );

    // 切换燕麦暖纸
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('theme-style-oat')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const ValueKey('theme-style-oat')));
    await t.pumpAndSettle();
    expect(s.state['themeStyle'], 'oat');
    expect(
      AppPalette.of(t.element(find.byType(PreferencesPage))).style,
      AppThemeStyle.oat,
    );

    // 切回深翠青瓷
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('theme-style-emerald')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('theme-style-emerald')));
    await t.pumpAndSettle();
    expect(s.state['themeStyle'], 'emerald');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('三种主题浅深色下首页紧凑布局与核心页无溢出', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async => null);

    for (final style in ['emerald', 'mono', 'oat']) {
      for (final mode in ['light', 'dark']) {
        final s = _demoStore();
        s.state['themeStyle'] = style;
        s.state['theme'] = mode;
        await t.pumpWidget(YoushuApp(s));
        await t.pumpAndSettle();

        // 校验流水首页紧凑度：第一条记录在首屏靠上位置（< 320pt）
        final bookTop = t.getTopLeft(find.text('日常账本')).dy;
        final firstEntryTop = t
            .getTopLeft(find.byKey(const ValueKey('entry-subtitle-e-demo-1')))
            .dy;
        expect(
          firstEntryTop - bookTop,
          lessThan(290),
          reason: '$style/$mode 首页首条记录距顶过远',
        );
        expect(t.takeException(), isNull, reason: '$style/$mode flow');

        // 切换分析（统计 + 预算）与记一笔
        await t.tap(find.text('分析').last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$style/$mode stats');
        await t.tap(find.text('预算').last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$style/$mode budget');

        await t.tap(find.byTooltip('记一笔'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$style/$mode record');
        await t.tap(find.byTooltip('返回'));
        await t.pumpAndSettle();
      }
    }
    await t.pumpWidget(const SizedBox());
  });

  test('主题风格写入 SQLite 偏好表并可重新读取恢复', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => createV2(db),
      ),
    );
    addTearDown(db.close);
    final s = _demoStore()..database = db;
    await s.persist();
    await s.setThemeStyle('oat');
    final row = (await db.query('preferences', where: 'id=1')).single;
    final prefs = jsonDecode(row['body'] as String) as Map<String, dynamic>;
    expect(prefs['themeStyle'], 'oat');
    expect(appThemeStyleOf(prefs['themeStyle']), AppThemeStyle.oat);
  });
}
