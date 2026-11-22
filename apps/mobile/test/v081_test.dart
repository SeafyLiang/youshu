import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youshu/display_dates.dart';
import 'package:youshu/belongings_domain.dart';
import 'package:youshu/belongings_links.dart';
import 'package:youshu/belongings_crop.dart';

Future<Uint8List> fixturePhoto() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(20, 10, 60, 60), Paint()..color = Colors.red);
  final picture = recorder.endRecording(),
      image = await picture.toImage(100, 80);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('跨年优先显示年份，包括一月一日的昨天', () {
    expect(
      flowDayLabel('2025-12-31', now: DateTime(2026, 1, 1)),
      '2025 年 12 月 31 日 · 周三',
    );
    expect(
      flowDayLabel('2026-01-01', now: DateTime(2026, 1, 1)),
      startsWith('今天'),
    );
    expect(
      flowDayLabel('2026-01-01', now: DateTime(2026, 1, 2)),
      startsWith('昨天'),
    );
    expect(
      flowDayLabel('2026-02-03', now: DateTime(2026, 6, 1)),
      '2 月 3 日 · 周二',
    );
    expect(recordDateLabel('2026-01-01'), '2026年1月1日');
  });
  test('年天仅改变展示，365天和整年边界', () {
    expect([1, 365, 366, 730, 731].map(bDuration).toList(), [
      '1 天',
      '365 天',
      '1年1天',
      '2年',
      '2年1天',
    ]);
    final item = Belonging({
      'purchase': '2024-02-29',
      'price': 73100,
      'state': '在用',
    });
    expect(item.days('2026-02-28'), 731);
    expect(dailyCost(item, [], now: '2026-02-28'), 100);
  });
  test('购物分享文案提取、去重、多候选与危险协议拒绝', () {
    expect(
      extractPurchaseUrls(
        '京东【商品】 https://item.jd.com/123.html?sku=1&order=2， 淘宝 https://m.tb.cn/abc。',
      ),
      ['https://item.jd.com/123.html?sku=1&order=2', 'https://m.tb.cn/abc'],
    );
    expect(
      extractPurchaseUrls(
        'https://mobile.yangkeduo.com/a https://mobile.yangkeduo.com/a',
      ),
      hasLength(1),
    );
    for (final value in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'https://user:pass@jd.com/',
      'https://',
      'https://a.com/ space',
    ]) {
      expect(validPurchaseUrl(value), false);
    }
    expect(validPurchaseUrl('http://item.jd.com/123.html'), true);
    expect(extractPurchaseUrls('只有口令没有网址'), isEmpty);
  });
  test('旧物品无需新增字段；非法链接与裁剪参数不可入库', () {
    final base = {
      'id': 'a',
      'name': '相机',
      'price': 100,
      'purchase': '2025-01-01',
      'category': '数码',
      'icon': 'camera',
      'state': '在用',
      'currency': 'CNY',
    };
    Belonging(base).validate();
    expect(Belonging(base).purchaseUrl, isNull);
    expect(
      () => Belonging({...base, 'purchaseUrl': 'taobao://order'}).validate(),
      throwsFormatException,
    );
    expect(
      () => Belonging({
        ...base,
        'coverEdit': {
          'rect': [0, 0, 2, 1],
          'subject': true,
        },
      }).validate(),
      throwsFormatException,
    );
  });
  testWidgets('自由矩形导出保留透明 PNG 与真实像素尺寸', (t) async {
    await t.runAsync(() async {
      final original = await fixturePhoto();
      final bytes = await cropBelongingImage(
        original,
        const Rect.fromLTWH(.1, 0, .8, 1),
      );
      final codec = await ui.instantiateImageCodec(bytes),
          image = (await codec.getNextFrame()).image;
      expect(image.width, 80);
      expect(image.height, 80);
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      expect(rgba[3], 0);
      expect(rgba[(30 * 80 + 30) * 4 + 3], 255);
      image.dispose();
      codec.dispose();
    });
  });
  testWidgets('八个裁剪边界可调、完成保存参数、再次打开原图并取消', (t) async {
    final original = (await t.runAsync(fixturePhoto))!;
    BelongingCropResult? result;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push(
                  c,
                  MaterialPageRoute<BelongingCropResult>(
                    builder: (_) => BelongingCropPage(original),
                  ),
                );
              },
              child: const Text('编辑'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('编辑'));
    await t.pump();
    await t.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
    await t.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pumpAndSettle();
    for (final pair in [
      (-1, -1),
      (0, -1),
      (1, -1),
      (-1, 0),
      (1, 0),
      (-1, 1),
      (0, 1),
      (1, 1),
    ]) {
      expect(
        find.byKey(Key('crop-handle-${pair.$1}-${pair.$2}')),
        findsOneWidget,
      );
    }
    await t.drag(
      find.byKey(const Key('crop-handle--1-0')),
      const Offset(45, 0),
    );
    await t.pump();
    await t.runAsync(() async {
      await (t
              .widget<TextButton>(find.widgetWithText(TextButton, '完成'))
              .onPressed!
          as dynamic)();
    });
    await t.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.rect.left, greaterThan(0));
    expect(result!.rect.height, 1);
    await t.tap(find.text('编辑'));
    await t.pump();
    await t.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(result, isNull);
  });
  testWidgets('自动主体提取不支持时保留原图并允许完成', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.seafy.yousu/system'),
          (call) async => {'status': 'unsupported'},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.seafy.yousu/system'),
            null,
          ),
    );
    final original = (await t.runAsync(fixturePhoto))!;
    await t.pumpWidget(
      MaterialApp(home: BelongingCropPage(original, autoSubject: true)),
    );
    await t.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pumpAndSettle();
    expect(find.text('此设备暂不支持主体提取，已保留原图'), findsOneWidget);
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, '完成')).onPressed,
      isNotNull,
    );
  });
}
