import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youshu/main.dart';
import 'package:youshu/store.dart';

void main() {
  testWidgets('系统主题运行时切换，深色大字体主要页面无布局异常', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async => null);
    final s = LedgerStore(), l = freshLedger('外观验收');
    s.state['ledgers'] = [l];
    s.state['active'] = l['id'];
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpWidget(YoushuApp(s));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('流水').last)).brightness,
      Brightness.light,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('流水').last)).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull, reason: 'overview');
    for (final page in ['流水', '分析', '预算', '统计', '我的']) {
      await tester.tap(find.text(page).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
    }
    await tester.tap(find.text('流水').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
