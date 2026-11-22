import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/main.dart';
import 'package:youshu/preferences_page.dart';
import 'package:youshu/store.dart';
import 'package:youshu/ui.dart';

LedgerStore _demoStore083() {
  final s = LedgerStore();
  final l = freshLedger('日常账本');
  s.state['ledgers'] = [l];
  s.state['active'] = l['id'];
  final cat = s.choices('category', type: 'expense').first;
  l['entries'].add({
    'id': 'e-demo-083',
    'kind': 'entry',
    'data': {
      'type': 'expense',
      'amount': 3200,
      'original_amount_minor': 3200,
      'original_currency': 'CNY',
      'base_currency': 'CNY',
      'base_amount_minor': 3200,
      'date': today(),
      'time': '10:15',
      'category_id': cat['id'],
      'category': cat['data']['name'],
      'tag_ids': [],
      'account': '微信',
      'to_account': '',
      'note': '抹茶拿铁',
    },
  });
  return s;
}

void main() {
  testWidgets('偏好设置分组展示 3 套极简 + 6 套柔雾哑光萌宠主题并支持实时切换', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async => null);

    final s = _demoStore083();
    await t.pumpWidget(YoushuApp(s));
    await t.pumpAndSettle();

    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await t.tap(find.text('偏好设置'));
    await t.pumpAndSettle();
    expect(find.byType(PreferencesPage), findsOneWidget);

    for (final style in AppThemeStyle.cuteThemes) {
      final target = find.byKey(ValueKey('theme-style-${style.id}'));
      await t.scrollUntilVisible(
        target,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(target);
      await t.pumpAndSettle();
      await t.tap(target);
      await t.pumpAndSettle();
      expect(s.state['themeStyle'], style.id);
      final pal = AppPalette.of(t.element(find.byType(PreferencesPage)));
      expect(pal.style, style);
      expect(pal.style.isCute, isTrue);
      expect(pal.markerSwipe, isNotNull);
    }

    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('6 套柔雾哑光萌宠主题浅深色下紧凑首页与核心页零溢出', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async => null);

    for (final style in AppThemeStyle.cuteThemes) {
      for (final mode in ['light', 'dark']) {
        final s = _demoStore083();
        s.state['themeStyle'] = style.id;
        s.state['theme'] = mode;
        await t.pumpWidget(YoushuApp(s));
        await t.pumpAndSettle();

        // 0.8.3 更紧凑首页：首条流水距账本名更紧凑（< 235pt）
        final bookTop = t.getTopLeft(find.text('日常账本')).dy;
        final firstEntryTop = t
            .getTopLeft(find.byKey(const ValueKey('entry-subtitle-e-demo-083')))
            .dy;
        expect(
          firstEntryTop - bookTop,
          lessThan(235),
          reason: '${style.id}/$mode 首页紧凑度未达标 (${firstEntryTop - bookTop})',
        );
        expect(find.byType(ThemeMascot), findsWidgets);
        expect(t.takeException(), isNull, reason: '${style.id}/$mode flow');

        // 分析 · 预算（含萌宠进度条跟随）
        await t.tap(find.text('分析').last);
        await t.pumpAndSettle();
        await t.tap(find.text('预算').last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '${style.id}/$mode budget');

        // 记一笔（支出/收入表情切换）
        await t.tap(find.byTooltip('记一笔'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '${style.id}/$mode record');
        await t.tap(find.text('收入').first);
        await t.pumpAndSettle();
        expect(
          t.takeException(),
          isNull,
          reason: '${style.id}/$mode record-income',
        );
        await t.tap(find.byTooltip('返回'));
        await t.pumpAndSettle();
      }
    }
    await t.pumpWidget(const SizedBox());
  });

  test('柔雾哑光萌宠主题持久化写入 SQLite 并可完整恢复', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => createV2(db),
      ),
    );
    addTearDown(db.close);
    final s = _demoStore083()..database = db;
    await s.persist();

    for (final style in AppThemeStyle.cuteThemes) {
      await s.setThemeStyle(style.id);
      final row = (await db.query('preferences', where: 'id=1')).single;
      final prefs = jsonDecode(row['body'] as String) as Map<String, dynamic>;
      expect(prefs['themeStyle'], style.id);
      expect(appThemeStyleOf(prefs['themeStyle']), style);
    }
  });
}
