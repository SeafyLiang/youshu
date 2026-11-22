import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';

Future<Set<String>?> pickLedgers(
  BuildContext context,
  LedgerStore s, {
  bool merge = false,
}) {
  final selected = merge
      ? <String>{}
      : s.viewLedgers.map((l) => l['id'] as String).toSet();
  return glassSheet<Set<String>>(
    context,
    StatefulBuilder(
      builder: (c, set) => Scaffold(
        appBar: AppBar(
          title: Text(merge ? '合并流水' : '查看账本'),
          actions: [
            TextButton(
              onPressed: () => set(() {
                selected.clear();
                selected.addAll(s.ledgers.map((l) => l['id'] as String));
              }),
              child: const Text('全选'),
            ),
          ],
        ),
        body: ListView.builder(
          itemCount: s.ledgers.length,
          itemBuilder: (c, i) {
            final l = s.ledgers[i];
            return CheckboxListTile(
              value: selected.contains(l['id']),
              onChanged: (v) => set(() {
                v == true ? selected.add(l['id']) : selected.remove(l['id']);
              }),
              title: Text(l['name']),
              subtitle: Text(
                '${settingsOf(l)['base_currency']} · ${s.records(l).length} 笔',
              ),
              secondary: const Icon(Icons.menu_book_outlined),
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: selected.length < (merge ? 2 : 1)
                  ? null
                  : () => Navigator.pop(c, selected),
              child: Text(merge ? '下一步' : '查看 ${selected.length} 本'),
            ),
          ),
        ),
      ),
    ),
  );
}
