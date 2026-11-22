import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';

class BatchPage extends StatefulWidget {
  final LedgerStore store;
  final Set<String> ids;
  const BatchPage(this.store, this.ids, {super.key});
  @override
  State<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends State<BatchPage> {
  LedgerStore get s => widget.store;
  final selected = <String>{};
  bool working = false;
  List<Json> get rows =>
      s.records(s.active).where((e) => widget.ids.contains(e['id'])).toList();
  Future<void> edit() async {
    final changes = <String, dynamic>{};
    final drafts = <String, String>{};
    final fields = {
      'account': '账户',
      'member': '成员',
      'merchant': '商家',
      'project': '项目',
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(c).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '批量编辑 · ${selected.length} 笔',
                  style: const TextStyle(fontSize: 18),
                ),
                const Text('只修改选定字段，其他内容保留。'),
                DropdownButtonFormField<String>(
                  initialValue: '',
                  decoration: const InputDecoration(labelText: '分类'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('不修改')),
                    for (final e in s.choices('category'))
                      DropdownMenuItem(
                        value: e['id'],
                        child: Text(
                          '${e['data']['type'] == 'income' ? '收入' : '支出'} · ${e['data']['name']}',
                        ),
                      ),
                  ],
                  onChanged: (v) => update(() {
                    if (v == null || v.isEmpty) {
                      changes.remove('category_id');
                    } else {
                      changes['category_id'] = v;
                    }
                  }),
                ),
                for (final f in fields.entries)
                  Row(
                    children: [
                      Checkbox(
                        value: changes.containsKey(f.key),
                        onChanged: (v) => update(() {
                          if (v == true) {
                            changes[f.key] = drafts[f.key] ?? '';
                          } else {
                            changes.remove(f.key);
                          }
                        }),
                      ),
                      Expanded(
                        child: TextFormField(
                          enabled: changes.containsKey(f.key),
                          decoration: InputDecoration(
                            labelText: f.value,
                            hintText: '留空表示清空',
                          ),
                          maxLength: 50,
                          onChanged: (v) {
                            drafts[f.key] = v;
                            changes[f.key] = v.trim();
                          },
                        ),
                      ),
                    ],
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('修改标签'),
                  subtitle: const Text('替换为所选标签，未选择时清空'),
                  value: changes.containsKey('tag_ids'),
                  onChanged: (v) => update(() {
                    if (v == true) {
                      changes['tag_ids'] = <String>[];
                    } else {
                      changes.remove('tag_ids');
                    }
                  }),
                ),
                if (changes.containsKey('tag_ids'))
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in s.choices('tag'))
                        FilterChip(
                          label: Text(e['data']['name']),
                          selected: (changes['tag_ids'] as List).contains(
                            e['id'],
                          ),
                          onSelected: (v) => update(() {
                            final ids = changes['tag_ids'] as List;
                            v ? ids.add(e['id']) : ids.remove(e['id']);
                          }),
                        ),
                    ],
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '分类仅应用到同收支类型且无退款的流水；账户不修改转账。成员为归属标签，不改变记录作者和共享权限。',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                FilledButton(
                  onPressed: changes.isEmpty
                      ? null
                      : () => Navigator.pop(c, true),
                  child: const Text('预览修改'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (!await approve(
      context,
      '修改 ${selected.length} 笔？',
      '${changes.entries.map((e) {
        final label = {'category_id': '分类', 'tag_ids': '标签', ...fields}[e.key];
        final value = e.key == 'category_id'
            ? (ledgerIndex(s.active).byId[e.value]?['data']['name'])
            : e.key == 'tag_ids'
            ? (e.value as List).map((id) => ledgerIndex(s.active).byId[id]?['data']['name']).join('、')
            : e.value;
        return '$label → ${value == '' ? '清空' : value}';
      }).join('\n')}\n不适用的字段跳过，未勾选的字段保留。',
    )) {
      return;
    }
    await perform('edit', changes);
  }

  Future<void> perform(String action, [Json changes = const {}]) async {
    if (working || selected.isEmpty) return;
    if (action != 'edit' &&
        !await approve(
          context,
          '${action == 'copy' ? '复制' : '删除'} ${selected.length} 笔？',
          action == 'copy'
              ? '保留日期生成独立流水，退款不能直接复制。'
              : '关联退款一起移入回收站，30天内可恢复。${selected.any(s.hasRecurringLink) ? '\n所选流水包含周期关联，本期保留已处理状态，恢复流水后关联仍保留。' : ''}',
        )) {
      return;
    }
    setState(() => working = true);
    try {
      await s.batchEntries(selected, action, changes);
      if (mounted) {
        setState(() => selected.clear());
        notifyApp('批量操作完成');
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !working,
    child: Scaffold(
      appBar: AppBar(
        title: Text('批量操作 · ${selected.length}'),
        actions: [
          TextButton(
            onPressed: working
                ? null
                : () => setState(
                    () => selected.length == rows.length
                        ? selected.clear()
                        : selected.addAll(rows.map((e) => e['id'] as String)),
                  ),
            child: const Text('全选'),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: working,
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (c, i) {
            final e = rows[i], d = e['data'];
            return CheckboxListTile(
              value: selected.contains(e['id']),
              onChanged: (v) => setState(
                () => v == true
                    ? selected.add(e['id'])
                    : selected.remove(e['id']),
              ),
              title: Text(categoryName(s.active, d)),
              subtitle: Text('${d['date']} · ${d['account']}'),
              secondary: Text(s.display(d['amount'])),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: selected.isEmpty || working ? null : edit,
                  child: const Text('编辑'),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: selected.isEmpty || working
                      ? null
                      : () => perform('copy'),
                  child: const Text('复制'),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: selected.isEmpty || working
                      ? null
                      : () => perform('delete'),
                  child: const Text('删除'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
