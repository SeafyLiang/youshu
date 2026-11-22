import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youshu/store.dart';
import 'package:youshu/transactions.dart';
import 'package:youshu/ui.dart';

void main() {
  testWidgets('分类选择默认全选，取消全选后应用为空，关闭弹层不修改原条件', (t) async {
    t.view.physicalSize = const Size(430, 932);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final s = LedgerStore(), l = freshLedger('筛选');
    s.state['ledgers'] = [l];
    s.state['active'] = l['id'];
    final original = EntryFilter();
    EntryFilter? result;
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await glassSheet<EntryFilter>(
                  c,
                  FilterPage(
                    s,
                    original,
                    const BookPeriod('2026-11-01', '2026-12-01'),
                  ),
                );
              },
              child: const Text('筛选'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('筛选'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('分类', skipOffstage: false),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('分类'));
    await t.pumpAndSettle();
    expect(
      t
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((e) => e.value == true),
      true,
    );
    expect(find.byType(Checkbox), findsWidgets);
    await t.tap(find.text('取消全选').hitTestable());
    await t.pumpAndSettle();
    expect(
      t
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((e) => e.value == false),
      true,
    );
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    await t.tap(find.text('应用筛选'));
    await t.pumpAndSettle();
    expect(result!.restricted.contains('分类'), true);
    expect(result!.categories, isEmpty);
    expect(original.restricted, isEmpty);
  });
}
