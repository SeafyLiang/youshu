import 'package:flutter/material.dart';

import 'store.dart';
import 'transactions.dart';

class LedgerDetailPage extends StatelessWidget {
  final LedgerStore store;
  final Json ledger;
  final String title;
  final EntryFilter filter;
  final Set<String> ids;
  final Widget Function(Json) tile;
  const LedgerDetailPage({
    super.key,
    required this.store,
    required this.ledger,
    required this.title,
    required this.filter,
    required this.ids,
    required this.tile,
  });
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: store,
    builder: (c, _) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Transactions(
        store,
        periodKey: filter.start.isEmpty ? today() : filter.start,
        tile: tile,
        add: (_) {},
        initialFilter: filter,
        onlyIds: filter.detailRule == null ? ids : null,
        scopeLedger:
            store.ledgers.where((l) => l['id'] == ledger['id']).firstOrNull ??
            store.view,
        temporary: true,
      ),
    ),
  );
}
