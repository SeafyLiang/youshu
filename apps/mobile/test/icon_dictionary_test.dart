import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/dictionary_page.dart';
import 'package:youshu/icon_catalog.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/store.dart';
import 'package:youshu/ui.dart';

import 'v062_test.dart' show fixture;

const imageData =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

Json categoryData(String name, String parent, String visual) => {
  'name': name,
  'type': 'expense',
  'parent_id': parent,
  'icon': 'category',
  'color': '#126C62',
  'order': 100,
  'archived': false,
  '_visualIcon': visual,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null),
  );

  Future<LedgerStore> store() async {
    final s = await fixture();
    addTearDown(() async {
      s.backupTimer?.cancel();
      await s.database!.close();
    });
    return s;
  }

  String parent(LedgerStore s) => dictionary(
    s.active,
    'category',
    type: 'expense',
  ).firstWhere((row) => row['data']['parent_id'] == '')['id'];

  test('连续创建默认与自选图标二级分类，随后编辑标签', () async {
    final s = await store(), pid = parent(s);
    await s.saveStyledDictionary(
      categoryData('默认子分类', pid, 'category'),
      kind: 'category',
    );
    await s.saveStyledDictionary(
      categoryData('自选子分类', pid, 'ant:apple'),
      kind: 'category',
    );
    final child = s
        .choices('category')
        .firstWhere((row) => row['data']['name'] == '自选子分类');
    expect(visualIcon(s.active, child), 'ant:apple');
    await s.saveStyledDictionary(
      {...child['data'] as Json, '_visualIcon': 'ant:coffee'},
      kind: 'category',
      existing: child,
    );
    await s.saveStyledDictionary({
      'name': '图标标签',
      'order': 0,
      'archived': false,
      'color': '#126C62',
      '_visualIcon': 'ant:gift',
    }, kind: 'tag');
    expect(s.active['icon_overrides'], isA<Map<String, dynamic>>());
    final restored = (await readState(s.database!))!['ledgers'][0];
    expect(restored['icon_overrides'][child['id']], 'ant:coffee');
  });

  test('旧动态Map保存上传图片并保留已有外观', () async {
    final s = await store(), pid = parent(s);
    s.active['icon_overrides'] = <dynamic, dynamic>{pid: 'ant:shop'};
    s.active['custom_icons'] = <dynamic, dynamic>{'custom:old': imageData};
    await s.saveStyledDictionary({
      ...categoryData('图片子分类', pid, 'custom:new'),
      '_customImage': imageData,
    }, kind: 'category');
    expect(s.active['icon_overrides'][pid], 'ant:shop');
    expect(s.active['custom_icons'], {
      'custom:old': imageData,
      'custom:new': imageData,
    });
    expect(s.active['custom_icons'], isA<Map<String, dynamic>>());
    IconCatalog.register(s.active);
    expect(IconCatalog.custom['custom:new'], base64Decode(imageData));
  });

  test('写库失败时恢复分类与原图标映射', () async {
    final s = await store(), pid = parent(s);
    final icons = <dynamic, dynamic>{pid: 'ant:shop'};
    final images = <dynamic, dynamic>{'custom:old': imageData};
    s.active['icon_overrides'] = icons;
    s.active['custom_icons'] = images;
    await s.persist();
    await s.database!.execute(
      "CREATE TRIGGER fail_icon BEFORE INSERT ON entries BEGIN SELECT RAISE(ABORT,'rollback'); END",
    );
    await expectLater(
      s.saveStyledDictionary({
        ...categoryData('失败子分类', pid, 'custom:new'),
        '_customImage': imageData,
      }, kind: 'category'),
      throwsA(isA<DatabaseException>()),
    );
    expect(s.active['icon_overrides'], icons);
    expect(s.active['custom_icons'], images);
    expect(
      s.choices('category').any((row) => row['data']['name'] == '失败子分类'),
      isFalse,
    );
    expect(
      (await readState(s.database!))!['ledgers'][0]['custom_icons'],
      images,
    );
  });

  testWidgets('实际二级分类入口选择图标后保存成功', (t) async {
    t.view.physicalSize = const Size(420, 948);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final s = (await t.runAsync(store))!;
    s.active['icon_overrides'] = <dynamic, dynamic>{parent(s): 'ant:shop'};
    await t.pumpWidget(
      MaterialApp(theme: appTheme(Brightness.light), home: DictionaryPage(s)),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('新建二级分类').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '图标修复验收');
    await t.tap(find.widgetWithText(ListTile, '图标'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'apple');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ant:apple')));
    await t.pumpAndSettle();
    await t.tap(find.text('保存').first);
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pumpAndSettle();
    final child = s
        .choices('category')
        .firstWhere((row) => row['data']['name'] == '图标修复验收');
    expect(visualIcon(s.active, child), 'ant:apple');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
