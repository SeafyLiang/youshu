import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'store.dart';
import 'ui.dart';
import 'record_page.dart';
import 'dictionary_page.dart';
import 'recurring_page.dart';

Json editableDefaults(Json fields) => {
  ...templateFields(fields),
  '_amount': fields['original_amount_minor'] == null
      ? ''
      : formatAmount(
          fields['original_amount_minor'],
          fields['original_currency'],
        ),
};
Json readDefaults(Json draft, {bool requiredAmount = false}) {
  final d = templateFields(draft);
  final text = (draft['_amount'] as String? ?? '').trim();
  d['original_amount_minor'] = text.isEmpty && !requiredAmount
      ? null
      : parseAmount(text, d['original_currency']);
  return d;
}

Json blankDefaults(LedgerStore s, {String type = 'expense'}) =>
    editableDefaults({
      'type': type,
      'category_id': s.choices('category', type: type).firstOrNull?['id'] ?? '',
      'account': '银行卡',
      'original_currency': s.currency,
      'tag_ids': <String>[],
      'note': '',
    });

Future<void> useRecordTemplate(
  BuildContext context,
  LedgerStore s,
  Json item,
) async {
  try {
    s.validateScheduleFields(item['fields']);
    await Navigator.push(
      context,
      AppPageRoute(
        builder: (_) => RecordPage(
          s,
          category: '',
          initialFields: templateFields(item['fields']),
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) message(context, e);
  }
}

Future<void> openTemplates(
  BuildContext context,
  LedgerStore s, {
  int tab = 0,
}) async {
  if (s.viewLedgers.length > 1) {
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择模板所属账本')),
            for (final b in s.ledgers)
              ListTile(
                title: Text(b['name']),
                onTap: () => Navigator.pop(c, b['id']),
              ),
          ],
        ),
      ),
    );
    if (id == null) return;
    await s.select(id, preserveView: true);
  }
  if (context.mounted) {
    await Navigator.push(
      context,
      AppPageRoute(builder: (_) => TemplatesPage(s, initialTab: tab)),
    );
  }
}

class TemplatesPage extends StatefulWidget {
  final LedgerStore s;
  final int initialTab;
  const TemplatesPage(this.s, {super.key, this.initialTab = 0});
  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  LedgerStore get s => widget.s;
  @override
  void initState() {
    super.initState();
    s.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(refresh);
    super.dispose();
  }

  Future<void> edit([Json? item]) async => Navigator.push(
    context,
    AppPageRoute(builder: (_) => TemplateEditor(s, existing: item)),
  );
  Future<void> change(Json item, String action) async {
    try {
      if (action == 'edit') {
        await edit(item);
        return;
      }
      if (action == 'remove') {
        if (!await approve(context, '移除模板？', '已有流水保持不变。')) return;
        await s.removeRecordTemplate(item['id']);
      } else if (action == 'pin') {
        await s.saveRecordTemplate({...item, 'pinned': item['pinned'] != true});
      } else {
        final ids = s.recordTemplates.map((t) => t['id'] as String).toList();
        final i = ids.indexOf(item['id']);
        final j = action == 'up' ? i - 1 : i + 1;
        if (j >= 0 && j < ids.length) {
          final temp = ids[i];
          ids[i] = ids[j];
          ids[j] = temp;
          await s.reorderRecordTemplates(ids);
        }
      }
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: widget.initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('常用模板'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '随手记'),
            Tab(text: '周期记账'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${s.active['name']} · 点模板记一笔',
                style: TextStyle(color: secondaryInk(context)),
              ),
              const SizedBox(height: 16),
              if (s.recordTemplates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    '把午餐、咖啡等常记内容存成模板。\n使用时只改金额，就能保存。',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final item in s.recordTemplates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassPanel(
                    child: ListTile(
                      leading: Icon(
                        item['pinned'] == true
                            ? CupertinoIcons.pin_fill
                            : CupertinoIcons.doc_text,
                        color: expenseInk(context),
                      ),
                      title: Text(item['name']),
                      subtitle: Text(
                        item['fields']['original_amount_minor'] == null
                            ? '每次填写金额'
                            : '${item['fields']['original_currency']} ${formatAmount(item['fields']['original_amount_minor'], item['fields']['original_currency'])}',
                      ),
                      onTap: s.canEdit
                          ? () => useRecordTemplate(context, s, item)
                          : null,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => change(item, v),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(
                            value: 'pin',
                            child: Text(
                              item['pinned'] == true ? '取消首页置顶' : '首页置顶',
                            ),
                          ),
                          const PopupMenuItem(value: 'up', child: Text('上移')),
                          const PopupMenuItem(value: 'down', child: Text('下移')),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('移除'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: s.canEdit ? () => edit() : null,
                icon: const Icon(Icons.add),
                label: const Text('新增随手记模板'),
              ),
              const SizedBox(height: 8),
              hint('首页按顺序展示最多 3 个置顶模板。'),
            ],
          ),
          RecurringList(s),
        ],
      ),
    ),
  );
}

class TemplateEditor extends StatefulWidget {
  final LedgerStore s;
  final Json? existing, source;
  const TemplateEditor(this.s, {super.key, this.existing, this.source});
  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  late final TextEditingController name;
  late Json draft;
  late bool pinned;
  bool saving = false;
  late final String bookId;
  @override
  void initState() {
    super.initState();
    bookId = widget.s.active['id'];
    name = TextEditingController(text: widget.existing?['name'] ?? '');
    draft = widget.existing != null
        ? editableDefaults(widget.existing!['fields'])
        : widget.source != null
        ? editableDefaults(widget.source!)
        : blankDefaults(widget.s);
    pinned = widget.existing?['pinned'] ?? true;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      if (widget.s.active['id'] != bookId) {
        throw const FormatException('账本已切换，请重新打开');
      }
      final item = {
        'id': widget.existing?['id'] ?? uuid.v4(),
        'name': name.text.trim(),
        'fields': readDefaults(draft),
        'pinned': pinned,
        'order': widget.existing?['order'] ?? widget.s.recordTemplates.length,
      };
      final duplicate = widget.s.recordTemplates.any(
        (t) => t['id'] != item['id'] && t['name'] == item['name'],
      );
      if (duplicate &&
          !await approve(
            context,
            '更新同名模板？',
            '已有“${item['name']}”模板，继续会更新它的默认字段。',
          )) {
        return;
      }
      await widget.s.saveRecordTemplate(item, replaceName: duplicate);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? '新增随手记模板' : '编辑模板')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.s.active['name'],
            style: TextStyle(color: expenseInk(context)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: '模板名称',
              hintText: '例如午餐',
            ),
          ),
          DefaultsForm(widget.s, draft, onChanged: () => setState(() {})),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('置顶到首页'),
            value: pinned,
            onChanged: (v) => setState(() => pinned = v),
          ),
          hint('金额可留空。每次使用取当前日期，改本次账目不影响模板。'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '保存中…' : '保存模板'),
          ),
        ],
      ),
    ),
  );
}

class DefaultsForm extends StatelessWidget {
  final LedgerStore s;
  final Json draft;
  final VoidCallback onChanged;
  final bool amountRequired;
  const DefaultsForm(
    this.s,
    this.draft, {
    super.key,
    required this.onChanged,
    this.amountRequired = false,
  });
  @override
  Widget build(BuildContext context) {
    final cats = s.choices('category', type: draft['type']);
    final valid = cats.any((c) => c['id'] == draft['category_id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: draft['type'],
          decoration: const InputDecoration(labelText: '收支方向'),
          items: const [
            DropdownMenuItem(value: 'expense', child: Text('支出')),
            DropdownMenuItem(value: 'income', child: Text('收入')),
          ],
          onChanged: (v) {
            draft['type'] = v;
            draft['category_id'] = '';
            onChanged();
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: ValueKey('${draft['type']}/${draft['category_id']}'),
          initialValue: valid ? draft['category_id'] : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '分类'),
          hint: const Text('请选择可用分类'),
          items: cats
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c['id'],
                  child: Text(categoryName(s.active, {'category_id': c['id']})),
                ),
              )
              .toList(),
          onChanged: (v) {
            draft['category_id'] = v;
            onChanged();
          },
        ),
        TextButton(
          onPressed: () async {
            await Navigator.push(
              context,
              AppPageRoute(
                builder: (_) => DictionaryPage(s, initialType: draft['type']),
              ),
            );
            onChanged();
          },
          child: const Text('管理分类与标签'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                key: ValueKey(
                  'amount-${draft['original_currency']}-${draft['original_amount_minor']}',
                ),
                initialValue: draft['_amount'],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: amountRequired ? '每期金额' : '预填金额（可留空）',
                ),
                onChanged: (v) => draft['_amount'] = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: draft['original_currency'],
                decoration: const InputDecoration(labelText: '币种'),
                items: currencies.keys
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  draft['original_currency'] = v;
                  onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          initialValue: draft['account'],
          maxLength: 50,
          decoration: const InputDecoration(labelText: '收付账户'),
          onChanged: (v) => draft['account'] = v.trim(),
        ),
        TextFormField(
          initialValue: draft['note'],
          maxLength: 500,
          decoration: const InputDecoration(labelText: '备注（可留空）'),
          onChanged: (v) => draft['note'] = v,
        ),
        if (s.choices('tag').isNotEmpty)
          Wrap(
            spacing: 6,
            children: [
              for (final t in s.choices('tag'))
                FilterChip(
                  label: Text(t['data']['name']),
                  selected: (draft['tag_ids'] as List).contains(t['id']),
                  onSelected: (v) {
                    final list = List<String>.from(draft['tag_ids']);
                    v ? list.add(t['id']) : list.remove(t['id']);
                    draft['tag_ids'] = list;
                    onChanged();
                  },
                ),
            ],
          ),
        for (final id
            in (draft['tag_ids'] as List)
                .where((id) => !s.choices('tag').any((t) => t['id'] == id))
                .toList())
          InputChip(
            label: const Text('已停用标签'),
            onDeleted: () {
              (draft['tag_ids'] as List).remove(id);
              onChanged();
            },
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('更多字段'),
          children: [
            for (final f in {
              'member': '成员',
              'merchant': '商家',
              'project': '项目',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  initialValue: draft[f.key] ?? '',
                  maxLength: 50,
                  decoration: InputDecoration(labelText: f.value),
                  onChanged: (v) => draft[f.key] = v,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
