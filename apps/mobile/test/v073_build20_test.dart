import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/budget_page.dart';
import 'package:youshu/data_pages.dart';
import 'package:youshu/store.dart';

import 'v050_test.dart' show row;
import 'v060_test.dart' show alipay;
import 'v061_test.dart' show setup;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('跨月净退款、预算用尽与超支按非负剩余计算日均', (t) async {
    final s = LedgerStore();
    final book = freshLedger('月度');
    s.state['ledgers'] = [book];
    s.state['active'] = book['id'];
    final date = today(), now = DateTime.parse(date);
    final prev = dateKey(DateTime(now.year, now.month, 0));
    ledgerIndex(book).byId['settings']!['data']['monthly_budget'] = 30000;
    (book['entries'] as List).addAll(<Json>[
      row(book, 'purchase', prev, 10000),
      row(book, 'refund', date, 6000, refund: 'purchase'),
    ]);
    final left = periodDays(s.period(date))
        .where((d) => d.compareTo(date) >= 0)
        .length;
    Future<void> check(int available) async {
      invalidateLedger(book);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BudgetPage(
              s,
              periodKey: date,
              onPeriod: (_) {},
              onEdit: (_) {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('日均可用 ¥${s.display(available ~/ left)}'),
        findsOneWidget,
      );
    }

    await check(36000);
    (book['entries'] as List).add(row(book, 'exhaust', date, 36000));
    await check(0);
    (book['entries'] as List).add(row(book, 'overspend', date, 1));
    await check(0);
  });

  testWidgets('历史无指纹批次按选中的文件查看，恢复后只保留成员', (t) async {
    final s = LedgerStore();
    addTearDown(s.dispose);
    final book = freshLedger('旧账本');
    (book['entries'] as List).addAll(<Json>[
      row(book, 'first', '2026-11-01', 100),
      row(book, 'second', '2026-11-02', 200),
    ]);
    final history = [
      for (final id in ['first', 'second'])
        {
          'file': '$id.csv',
          'count': 1,
          'ids': [id],
          'ledger_ids': [book['id']],
        },
    ];
    s.state.addAll({
      'ledgers': [book],
      'active': book['id'],
      'importHistory': history,
    });
    await t.pumpWidget(MaterialApp(home: ImportHistoryPage(s)));
    await t.tap(find.text('first.csv'));
    await t.pumpAndSettle();
    expect(find.text('1.00'), findsOneWidget);
    expect(find.text('2.00'), findsNothing);
    final bundle = restoreBundle({
      'schema': 5,
      'ledgers': [book],
      'importHistory': history,
    });
    final restored = bundle['ledgers'].single as Json;
    final batch = (bundle['history'] as List).first as Json;
    expect(batch['refs'], isNull);
    final id = importBatchMemberIds(batch, restored).single;
    expect(ledgerIndex(restored).byId[id]!['data']['amount'], 100);
  });

  testWidgets('原始、Build19 已恢复和再次恢复的批次保留全部成员与独立撤销保护', (t) async {
    late LedgerStore s;
    await t.runAsync(() async {
      s = await setup(LedgerStore());
      addTearDown(s.dispose);
      addTearDown(s.database!.close);
      final batchInput = alipay('first');
      (batchInput['rows'] as List).add(
        (alipay('second')['rows'] as List).single,
      );
      await s.commitImportDraft(batchInput, target: s.active['id'], name: '');
      final edited = s.records(s.active).first;
      await s.saveEntry({
        ...edited['data'] as Json,
        'note': '改过',
      }, existing: edited);
      final old = s.importBatches.first;
      expect((await s.previewImportUndo(old)).count, 1);

      // Recreate Build 19's restored shape: original import IDs, a restored
      // ledger with new IDs, and only the unchanged row in its fingerprint map.
      await s.restorePreview(
        await s.inspectBackupFile(await s.exportBackupFile(), 'original.json'),
      );
      final historical = s.importBatches.first..remove('members');
      final copy = s.ledgers.last;
      expect((historical['refs'][copy['id']] as Map).length, 1);
      expect(
        importBatchMemberIds(historical, copy)
            .intersection(s.records(copy).map((e) => e['id'] as String).toSet())
            .length,
        2,
      );
      await s.persist();
      await s.restorePreview(
        await s.inspectBackupFile(
          await s.exportBackupFile(),
          'legacy-copy.json',
        ),
      );
      final restored = s.ledgers.last, batch = s.importBatches.first;
      expect(
        importBatchMemberIds(batch, restored),
        s.records(restored).map((e) => e['id']).toSet(),
      );
      final undo = await s.previewImportUndo(batch);
      expect(undo.count, 1);
      expect(undo.kept, 1);
      await s.undoImportBatch(undo);
      final current = s.allLedgers.singleWhere(
        (b) => b['id'] == restored['id'],
      );
      expect(s.records(current).single['data']['note'], '改过');
      expect(s.trashEntries(current).length, 1);
    });
    await t.pumpWidget(MaterialApp(home: ImportHistoryPage(s)));
    await t.tap(find.text('alipay.csv').first);
    await t.pumpAndSettle();
    expect(find.text('导入批次'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
    expect(find.textContaining('已移除'), findsOneWidget);
  });
}
