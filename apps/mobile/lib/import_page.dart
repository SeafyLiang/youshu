import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import 'payment_import.dart';
import 'store.dart';
import 'ui.dart';

class ImportPage extends StatefulWidget {
  final LedgerStore store;
  final Json? initialDraft;
  const ImportPage(this.store, {super.key, this.initialDraft});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  Json? draft;
  bool working = false;
  String target = '', view = '全部';
  final selected = <String>{};
  final name = TextEditingController(text: '导入账本');
  LedgerStore get s => widget.store;
  List<Json> get rows => (draft?['rows'] as List? ?? []).cast<Json>();
  @override
  void initState() {
    super.initState();
    target = s.canEdit ? s.active['id'] : '';
    if (widget.initialDraft case final initial?) loadDraft(initial);
  }

  Json copyDraft(Json value) => jsonDecode(jsonEncode(value)) as Json;

  void loadDraft(Json value) {
    draft = copyDraft(value);
    target = draft!['target'] ?? target;
    selected.clear();
    view = '全部';
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    if (working) return;
    setState(() => working = true);
    try {
      await task();
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> save() async {
    if (draft != null) {
      draft!['target'] = target;
      await s.saveImportDraft(copyDraft(draft!));
    }
  }

  Future<void> choose() => run(() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    if (f == null) return;
    final out = BytesBuilder(copy: false);
    await for (final b in f.readAsByteStream()) {
      if (out.length + b.length > 20 * 1024 * 1024) {
        throw const FormatException('文件不能超过20MB');
      }
      out.add(b);
    }
    final p = await compute(parseImportFile, (out.takeBytes(), f.name));
    final existing = (s.state['importDrafts'] as List? ?? [])
        .where((e) => e['id'] == p['id'])
        .firstOrNull;
    loadDraft(
      existing ?? await compute(reviewImport, (p, s.importMatchRows())),
    );
    await save();
  });
  Future<void> commit(Map<String, String> needsReview) => run(() async {
    if (!await approve(
      context,
      '导入 ${rows.where((r) => r['status'] == 'ready' && !needsReview.containsKey(r['id'])).length} 笔',
      '待核对记录保留在草稿中。',
    )) {
      return;
    }
    final prepared = copyDraft(draft!);
    for (final row in (prepared['rows'] as List).cast<Json>()) {
      final reason = needsReview[row['id']];
      if (row['status'] == 'ready' && reason != null) {
        row['status'] = 'review';
        row['reason'] = reason;
      }
    }
    final count = await s.commitImportDraft(
      prepared,
      target: target,
      name: name.text,
    );
    loadDraft(
      (s.state['importDrafts'] as List).firstWhere(
        (d) => d['id'] == draft!['id'],
      ),
    );
    if (mounted) {
      message(context, '已保存 $count 笔流水 · 已保留导入记录');
    }
  });
  List<Json> get choices => dictionary(
    s.ledgers.where((l) => l['id'] == target).firstOrNull ?? s.active,
    'category',
  );
  String get targetCurrency =>
      s.ledgers
          .where((book) => book['id'] == target)
          .map((book) => settingsOf(book)['base_currency'] as String)
          .firstOrNull ??
      'CNY';

  Map<String, String> blockedRows() {
    final base = targetCurrency;
    final blocked = <String, String>{};
    final missing = <String, bool>{};
    for (final r in rows) {
      if (r['status'] != 'ready' ||
          r['refund'] == true ||
          r['currency'] == base ||
          (r['manual_fx_base'] == base && r['manual_fx_rate'] is String)) {
        continue;
      }
      final date = (r['dateTime'] as String).substring(0, 10);
      if (missing.putIfAbsent(
        '${r['currency']}/$date',
        () => s.cachedQuote(r['currency'], base, date) == null,
      )) {
        blocked[r['id']] = '缺少本机汇率，请补填';
      }
    }
    for (final r in rows) {
      if (r['status'] == 'ready' &&
          r['refund'] == true &&
          blocked.containsKey(r['refund_of'])) {
        blocked[r['id']] = '原消费待核对，核对后再导入退款';
      }
    }
    return blocked;
  }

  Future<void> edit(List<Json> values) async {
    if (values.isEmpty) return;
    final single = values.length == 1 ? values.first : null;
    final base = targetCurrency,
        foreign =
            single != null &&
            single['refund'] != true &&
            single['currency'] != targetCurrency;
    final manual = TextEditingController(
      text: single != null && single['manual_fx_base'] == base
          ? single['manual_fx_rate'] as String?
          : null,
    );
    final account = TextEditingController(text: single?['account'] ?? ''),
        note = TextEditingController(text: single?['note'] ?? ''),
        tags = TextEditingController(
          text: (single?['tags'] as List? ?? []).join('、'),
        );
    String? cat;
    String refund = single?['refund_of'] ?? '',
        decision = single?['status'] == 'skipped' ? 'skipped' : 'ready';
    final candidates = [
      ...s.importMatchRows().where((e) => e['ledger_id'] == target),
      ...rows,
    ];
    final unique = <String, Json>{
      for (final e in candidates)
        if (single != null &&
            e['type'] == 'expense' &&
            e['deleted'] != true &&
            e['refund'] != true &&
            e['status'] != 'skipped' &&
            e['id'] != single['id'] &&
            e['currency'] == single['currency'] &&
            e['amount'] >= single['amount'] &&
            e['dateTime'].compareTo(single['dateTime']) <= 0)
          e['id']: e,
    };
    if (!unique.containsKey(refund)) refund = '';
    final accepted = await settledDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(single == null ? '调整 ${values.length} 笔' : '核对账目'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (single != null) ...[
                    Text(
                      '${single['dateTime']} · ${single['currency']} ${formatAmount(single['amount'], single['currency'])}',
                    ),
                    Text(
                      single['reason'] ?? '',
                      style: TextStyle(color: secondaryInk(c)),
                    ),
                    if (single['refund'] != true)
                      for (final existing
                          in candidates
                              .where(
                                (e) =>
                                    (single['candidates'] as List? ??
                                            [single['existing_id']])
                                        .contains(e['id']),
                              )
                              .take(5))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '已有 · ${existing['dateTime']} · ${formatAmount(existing['amount'], existing['currency'])}\n${existing['note'] ?? ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryInk(c),
                            ),
                          ),
                        ),
                    const SizedBox(height: 12),
                  ],
                  if (single?['refund'] == true)
                    DropdownButtonFormField<String>(
                      initialValue: refund,
                      decoration: const InputDecoration(labelText: '原消费'),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('选择原消费')),
                        for (final e in unique.values)
                          DropdownMenuItem(
                            value: e['id'],
                            child: Text(
                              '${e['dateTime'].substring(0, 10)} · ${formatAmount(e['amount'], e['currency'])} · ${e['note'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => set(() => refund = v!),
                    ),
                  if (single?['refund'] != true)
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: '分类（不选则保留）'),
                      isExpanded: true,
                      items: [
                        for (final e in choices)
                          DropdownMenuItem(
                            value: e['id'],
                            child: Text(
                              '${e['data']['type'] == 'income' ? '收入' : '支出'} · ${choices.where((p) => p['id'] == e['data']['parent_id']).firstOrNull?['data']['name'] ?? ''} / ${e['data']['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => cat = v,
                    ),
                  TextField(
                    controller: account,
                    decoration: const InputDecoration(labelText: '账户'),
                  ),
                  TextField(
                    controller: tags,
                    decoration: const InputDecoration(labelText: '标签（顿号分隔）'),
                  ),
                  if (single != null)
                    TextField(
                      controller: note,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '备注'),
                    ),
                  if (foreign)
                    TextField(
                      controller: manual,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '每 1 ${single['currency']} 折 $base',
                        helperText: '可补填手动汇率',
                      ),
                    ),
                  if (single != null)
                    DropdownButtonFormField<String>(
                      initialValue: decision,
                      items: [
                        DropdownMenuItem(
                          value: 'ready',
                          child: Text(
                            single['existing_id'] != null ? '保留已有记录' : '确认导入',
                          ),
                        ),
                        const DropdownMenuItem(
                          value: 'skipped',
                          child: Text('跳过'),
                        ),
                        const DropdownMenuItem(
                          value: 'review',
                          child: Text('稍后核对'),
                        ),
                      ],
                      onChanged: (v) => decision = v!,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      try {
        final labels = tags.text
            .split(RegExp('[、,，]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        if (labels.length > 40 ||
            labels.any((e) => e.length > 50) ||
            account.text.length > 50 ||
            note.text.length > 500) {
          throw const FormatException('字段内容过长');
        }
        final previous = copyDraft(draft!);
        for (final r in values) {
          if (cat != null &&
              choices.firstWhere((e) => e['id'] == cat)['data']['type'] !=
                  r['type']) {
            throw const FormatException('分类需与收支类型一致');
          }
        }
        if (single?['refund'] == true &&
            decision == 'ready' &&
            refund.isEmpty) {
          throw const FormatException('请选择原消费，或保留待核对');
        }
        final manualRate = manual.text.trim();
        if (foreign &&
            manualRate.isNotEmpty &&
            convertAmount(
                  single['amount'],
                  single['currency'],
                  base,
                  manualRate,
                ) <=
                0) {
          throw const FormatException('手动汇率折算的金额须大于 0');
        }
        for (final r in values) {
          if (cat != null) {
            final e = choices.firstWhere((e) => e['id'] == cat);
            r['category'] = e['data']['name'];
            r['parent'] =
                choices
                    .where((p) => p['id'] == e['data']['parent_id'])
                    .firstOrNull?['data']['name'] ??
                e['data']['name'];
          }
          if (account.text.trim().isNotEmpty) {
            r['account'] = account.text.trim();
          }
          if (tags.text.isNotEmpty || single != null) r['tags'] = labels;
          if (single != null) {
            r['note'] = note.text;
            r['refund_of'] = refund;
            r['status'] = r['existing_id'] != null && decision == 'ready'
                ? 'duplicate'
                : decision;
            r['reviewed'] = decision != 'review';
            if (foreign) {
              if (manualRate.isEmpty) {
                r.remove('manual_fx_rate');
                r.remove('manual_fx_base');
              } else {
                r['manual_fx_rate'] = manualRate;
                r['manual_fx_base'] = base;
              }
            }
          }
        }
        try {
          await save();
        } catch (_) {
          draft = previous;
          rethrow;
        }
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) message(context, e);
      }
    }
    account.dispose();
    tags.dispose();
    note.dispose();
    manual.dispose();
  }

  String statusLabel(Json r, Map<String, String> blocked) =>
      switch (r['status']) {
        'ready' when blocked.containsKey(r['id']) => '待核对',
        'ready' => '可导入',
        'review' => '待核对',
        'duplicate' => '已重复',
        'imported' => '已导入',
        _ => '已跳过',
      };
  @override
  Widget build(BuildContext c) {
    final blocked = blockedRows();
    final counts = <String, int>{};
    for (final r in rows) {
      final status = statusLabel(r, blocked);
      counts.update(status, (count) => count + 1, ifAbsent: () => 1);
    }
    final visible = rows
            .where((r) => view == '全部' || statusLabel(r, blocked) == view)
            .toList(),
        writable = s.ledgers
            .where((l) => ['owner', 'editor'].contains(l['role']))
            .toList();
    if (target.isNotEmpty && !writable.any((l) => l['id'] == target)) {
      target = '';
    }
    return PopScope(
      canPop: !working,
      child: Scaffold(
        appBar: AppBar(
          title: Text(draft == null ? '导入账单' : '核对账单'),
          actions: [
            if (draft != null && widget.initialDraft == null)
              TextButton(
                onPressed: working ? null : () => setState(() => draft = null),
                child: const Text('换一份文件'),
              ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (working) const LinearProgressIndicator(),
                    if (draft == null) ...[
                      GlassPanel(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            for (final item in [
                              '支付宝 · CSV',
                              '微信支付 · XLSX',
                              '随手记 · XLSX',
                            ])
                              ListTile(
                                leading: const Icon(Icons.file_open_outlined),
                                title: Text(item),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: working ? null : choose,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (final d
                          in (s.state['importDrafts'] as List? ?? []).reversed)
                        ListTile(
                          title: Text(d['file']),
                          subtitle: Text(
                            '${(d['rows'] as List).where((r) => r['status'] == 'review').length} 笔待核对',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => loadDraft(d)),
                        ),
                    ] else ...[
                      GlassPanel(
                        radius: 18,
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(
                            draft!['file'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('${rows.length} 笔账单 · 已保存到本机草稿'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final currency
                          in rows.map((r) => r['currency'] as String).toSet())
                        Text(
                          '$currency · 支出 ${formatAmount(rows.where((r) => r['status'] == 'ready' && r['currency'] == currency && r['type'] == 'expense' && r['refund'] != true).fold<int>(0, (n, r) => n + (r['amount'] as int)), currency)} · 收入 ${formatAmount(rows.where((r) => r['status'] == 'ready' && r['currency'] == currency && (r['type'] == 'income' || r['refund'] == true)).fold<int>(0, (n, r) => n + (r['amount'] as int)), currency)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryInk(c),
                          ),
                        ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: ValueKey(target),
                        initialValue: target,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '导入到'),
                        items: [
                          for (final l in writable)
                            DropdownMenuItem(
                              value: l['id'],
                              child: Text(l['name']),
                            ),
                          const DropdownMenuItem(
                            value: '',
                            child: Text('新建人民币账本'),
                          ),
                        ],
                        onChanged: working
                            ? null
                            : (v) => run(() async {
                                final previous = target;
                                target = v!;
                                try {
                                  await save();
                                } catch (_) {
                                  target = previous;
                                  rethrow;
                                }
                              }),
                      ),
                      if (target.isEmpty)
                        TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: '账本名称'),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final status in [
                            '全部',
                            '可导入',
                            '待核对',
                            '已重复',
                            if (counts.containsKey('已跳过')) '已跳过',
                            if (counts.containsKey('已导入')) '已导入',
                          ])
                            ChoiceChip(
                              label: Text(
                                '$status ${status == '全部' ? rows.length : counts[status] ?? 0}',
                              ),
                              selected: view == status,
                              onSelected: (_) => setState(() => view = status),
                            ),
                        ],
                      ),
                      if ((draft!['errors'] as List).isNotEmpty)
                        Text(
                          (draft!['errors'] as List).take(20).join('\n'),
                          style: TextStyle(
                            color: Theme.of(c).colorScheme.error,
                          ),
                        ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              if (selected.length == visible.length) {
                                selected.clear();
                              } else {
                                selected.addAll(
                                  visible
                                      .where(
                                        (r) => ![
                                          'imported',
                                          'duplicate',
                                        ].contains(r['status']),
                                      )
                                      .map((r) => r['id'] as String),
                                );
                              }
                            }),
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => edit(
                                    rows
                                        .where(
                                          (r) => selected.contains(r['id']),
                                        )
                                        .toList(),
                                  ),
                            child: Text('批量调整 ${selected.length}'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => run(() async {
                                    final previous = copyDraft(draft!);
                                    for (final r in rows.where(
                                      (r) => selected.contains(r['id']),
                                    )) {
                                      r['status'] = 'skipped';
                                      r['reviewed'] = true;
                                    }
                                    try {
                                      await save();
                                      selected.clear();
                                    } catch (_) {
                                      draft = previous;
                                      rethrow;
                                    }
                                  }),
                            child: const Text('跳过'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (draft != null)
              SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (c, i) {
                  final r = visible[i];
                  return ListTile(
                    leading: Checkbox(
                      value: selected.contains(r['id']),
                      onChanged: ['imported', 'duplicate'].contains(r['status'])
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                selected.add(r['id']);
                              } else {
                                selected.remove(r['id']);
                              }
                            }),
                    ),
                    title: Text(
                      '${r['category']} · ${formatAmount(r['amount'], r['currency'])} ${r['currency']}',
                    ),
                    subtitle: Text(
                      '${r['dateTime']} · ${statusLabel(r, blocked)}\n${blocked[r['id']] ?? r['note']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap:
                        working ||
                            ['imported', 'duplicate'].contains(r['status'])
                        ? null
                        : () => edit([r]),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
        bottomNavigationBar: draft == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: working || (counts['可导入'] ?? 0) == 0
                        ? null
                        : () => commit(blocked),
                    child: Text('导入 ${counts['可导入'] ?? 0} 笔'),
                  ),
                ),
              ),
      ),
    );
  }
}
