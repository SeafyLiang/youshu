import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'store.dart';
import 'ui.dart';
import 'ledger_scope.dart';
import 'merge_fx.dart';

Json _compose((List<Json>, Json) input) =>
    composeLedgers(input.$1, input.$2, deduplicate: true);

class MergePage extends StatefulWidget {
  final LedgerStore store;
  final Set<String> ids;
  final String name;
  const MergePage(
    this.store, {
    super.key,
    required this.ids,
    required this.name,
  });
  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  Json? composed, preview;
  Map<String, Json> rates = {};
  bool working = false;
  String error = '';
  Map<String, List<String>> missing = {};
  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    setState(() => working = true);
    try {
      final books = widget.store.ledgers
          .where((l) => widget.ids.contains(l['id']))
          .toList();
      composed = await compute(_compose, (books, settingsOf(books.first)));
      try {
        rates = await widget.store.mergeRates(composed!);
      } catch (e) {
        error = '$e';
      }
      missing = {};
      for (final e in widget.store.records(composed!)) {
        final d = e['data'] as Json;
        if (d['base_currency'] != 'CNY' &&
            !isRefund(d) &&
            fxCurrency(d) != 'CNY' &&
            !rates.containsKey(fxKey(d))) {
          (missing[fxCurrency(d)] ??= []).add(d['date']);
        }
      }
      missing = {
        for (final e in missing.entries)
          e.key: (e.value.toSet().toList()..sort()),
      };
      if (missing.isEmpty) {
        preview = await compute(convertMergedCny, (composed!, rates));
        error = '';
      }
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> manual(String currency) async {
    final controller = TextEditingController();
    final ok = await settledDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$currency → CNY'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '每 1 $currency 折人民币',
            helperText: '用于缺失汇率的 ${missing[currency]!.length} 个日期',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('采用手动汇率'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      convertAmount(100, currency, 'CNY', controller.text);
      if (double.parse(controller.text) <= 0) {
        throw const FormatException('汇率须大于0');
      }
      for (final date in missing[currency]!) {
        rates['$currency/$date'] = {
          'rate': controller.text,
          'date': date,
          'source': 'manual',
        };
      }
      missing.remove(currency);
      if (missing.isEmpty) {
        preview = await compute(convertMergedCny, (composed!, rates));
        error = '';
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('合并预览')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (working) const LinearProgressIndicator(),
        Text(
          widget.name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        const Text('人民币 · 历史汇率快照'),
        if (error.isNotEmpty)
          Text(error, style: TextStyle(color: Theme.of(c).colorScheme.error)),
        for (final e in missing.entries)
          ListTile(
            title: Text('${e.key} · ${e.value.length} 个日期'),
            subtitle: Text('${e.value.first} — ${e.value.last}'),
            trailing: TextButton(
              onPressed: () => manual(e.key),
              child: const Text('补录'),
            ),
          ),
        if (preview != null)
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.store.records(preview!).length} 笔'),
                for (final type in ['expense', 'income'])
                  Text(
                    '${type == 'expense' ? '支出' : '收入'}  ¥ ${formatAmount(widget.store.records(preview!).where((e) => cashFlowType(e['data']) == type).fold<int>(0, (n, e) => n + cashFlowAmount(e['data'])), 'CNY')}',
                    style: const TextStyle(fontSize: 24),
                  ),
                const SizedBox(height: 12),
                const Text('原账本与预算保留', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (error.isNotEmpty)
          TextButton(
            onPressed: working ? null : prepare,
            child: const Text('重试获取汇率'),
          ),
        FilledButton(
          onPressed: working || preview == null
              ? null
              : () async {
                  setState(() => working = true);
                  try {
                    await widget.store.mergeLedgers(
                      widget.ids,
                      widget.name,
                      rates: rates,
                    );
                    if (c.mounted) Navigator.pop(c);
                  } catch (e) {
                    if (c.mounted) message(c, e);
                  } finally {
                    if (mounted) setState(() => working = false);
                  }
                },
          child: const Text('生成人民币账本'),
        ),
      ],
    ),
  );
}
