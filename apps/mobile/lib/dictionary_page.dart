import 'icon_catalog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'category_templates.dart';
import 'store.dart';
import 'ui.dart';

class DictionaryPage extends StatefulWidget {
  final LedgerStore s;
  final String initialType;
  const DictionaryPage(this.s, {super.key, this.initialType = 'expense'});
  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  String kind = 'category', query = '';
  late String type = widget.initialType;
  bool batch = false;
  final collapsed = <String>{}, selected = <String>{};
  final _editControllers = <TextEditingController>[];
  @override
  void dispose() {
    for (final controller in _editControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  LedgerStore get s => widget.s;
  bool get editable => s.active['role'] == 'owner' && !s.busy;
  List<Json> get rows =>
      s.choices(kind, type: kind == 'category' ? type : null, archived: true);

  Future<void> edit({Json? row, String parentId = ''}) async {
    if (!editable) return;
    final name = TextEditingController(text: row?['data']['name'] ?? '');
    _editControllers.add(name); // 等页面卸载后释放，避免弹层退出动画仍使用控制器。
    var parent = row?['data']['parent_id'] ?? parentId;
    String? customImage;
    var icon = visualIcon(s.active, row),
        color =
            row?['data']['color'] ?? (type == 'income' ? '#BD672D' : '#126C62');
    var hidden = row?['data']['archived'] == true;
    final hasChildren = rows.any((e) => e['data']['parent_id'] == row?['id']);
    final result = await glassSheet<Json>(
      context,
      StatefulBuilder(
        builder: (c, update) => Scaffold(
          appBar: AppBar(
            title: Text(
              '${row == null ? '新建' : '编辑'}${kind == 'tag'
                  ? '标签'
                  : parent == ''
                  ? '一级分类'
                  : '二级分类'}',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final value = name.text.trim();
                  if (value.isEmpty || value.length > 50) {
                    message(c, '名称需为 1–50 字');
                    return;
                  }
                  if (rows.any(
                    (e) =>
                        e['id'] != row?['id'] &&
                        e['data']['name'] == value &&
                        (kind == 'tag' || e['data']['parent_id'] == parent),
                  )) {
                    message(c, '同一层级已经有这个名称');
                    return;
                  }
                  Navigator.pop(c, {
                    'name': value,
                    'order': row?['data']['order'] ?? rows.length,
                    'archived': hidden,
                    'color': color,
                    '_visualIcon': icon,
                    '_customImage': customImage,
                    if (kind == 'category') ...{
                      'parent_id': parent,
                      'type': type,
                      'icon': row?['data']['icon'] ?? 'category',
                    },
                  });
                },
                child: const Text('保存'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: CategoryBadge(
                  icon: icon,
                  color: color,
                  name: name.text,
                  size: 56,
                ),
              ),
              space,
              TextField(
                controller: name,
                maxLength: 50,
                autofocus: false,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '给分类一个清楚的名字',
                ),
              ),
              space,
              if (kind == 'category') ...[
                DropdownButtonFormField<String>(
                  initialValue: parent,
                  decoration: const InputDecoration(labelText: '所属分类'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('一级分类')),
                    if (!hasChildren)
                      ...rows
                          .where(
                            (e) =>
                                e['data']['parent_id'] == '' &&
                                e['id'] != row?['id'],
                          )
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e['id'],
                              child: Text(e['data']['name']),
                            ),
                          ),
                  ],
                  onChanged: (v) => update(() => parent = v!),
                ),
                space,
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('图标'),
                leading: CatalogIcon(icon),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final choice = await Navigator.push<IconChoice>(
                    c,
                    AppPageRoute(
                      builder: (_) => IconPickerPage(s.active, icon),
                    ),
                  );
                  if (choice != null) {
                    update(() {
                      icon = choice.key;
                      customImage = choice.image;
                    });
                  }
                },
              ),
              const Text('颜色'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children:
                    ['#126C62', '#BD672D', '#4265A8', '#9862AC', '#AA5265']
                        .map(
                          (v) => Semantics(
                            label: '颜色 $v',
                            selected: color == v,
                            child: InkWell(
                              onTap: () => update(() => color = v),
                              borderRadius: BorderRadius.circular(22),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: dictionaryColor(v),
                                  shape: BoxShape.circle,
                                ),
                                child: color == v
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              if (row != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('隐藏'),
                  value: hidden,
                  onChanged: (v) => update(() => hidden = v),
                ),
              if (row != null)
                TextButton.icon(
                  onPressed: () => Navigator.pop(c, {'_delete': true}),
                  icon: Icon(
                    Icons.delete_outline,
                    color: Theme.of(c).colorScheme.error,
                  ),
                  label: Text(
                    '删除${kind == 'tag' ? '标签' : '分类'}',
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      height: .85,
    );
    if (result == null) return;
    if (result['_delete'] == true && row != null) {
      await deleteRow(row);
      return;
    }
    try {
      await s.saveStyledDictionary(result, kind: kind, existing: row);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> deleteRow(Json row) async {
    var replacement = '';
    final budgetPolicy = <String, bool>{}, balancePolicy = <String, bool>{};
    final hasChildren = rows.any((r) => r['data']['parent_id'] == row['id']);
    final candidates = rows
        .where(
          (r) =>
              r['id'] != row['id'] &&
              r['data']['archived'] != true &&
              (!hasChildren || r['data']['parent_id'] == ''),
        )
        .toList();
    String candidateLabel(Json candidate) {
      final parent = ledgerIndex(s.active).byId[candidate['data']['parent_id']];
      final name = candidate['data']['name'];
      return parent == null ? name : '${parent['data']['name']} / $name';
    }

    final confirmed = await glassSheet<bool>(
      context,
      StatefulBuilder(
        builder: (c, update) {
          DictionaryDeletion? plan;
          String? problem;
          try {
            plan = planDictionaryDeletion(
              s.active,
              row['id'],
              replacement,
              budgetPolicy: budgetPolicy,
              balancePolicy: balancePolicy,
            );
          } catch (error) {
            problem = error.toString().replaceFirst('FormatException: ', '');
          }
          final ready =
              plan != null &&
              budgetPolicy.keys.toSet().containsAll(plan.budgetConflicts) &&
              balancePolicy.keys.toSet().containsAll(plan.balanceConflicts);
          Widget policyChoice(String id, bool budget) {
            final policy = budget ? budgetPolicy : balancePolicy;
            final name = ledgerIndex(s.active).byId[id]?['data']['name'] ?? id;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<bool>(
                key: ValueKey(
                  '${budget ? 'budget' : 'balance'}-$id-$replacement',
                ),
                initialValue: policy[id],
                decoration: InputDecoration(
                  labelText: '$name · 迁移后${budget ? '预算' : '结余'}',
                ),
                items: const [
                  DropdownMenuItem(value: false, child: Text('计入')),
                  DropdownMenuItem(value: true, child: Text('排除')),
                ],
                onChanged: (value) => update(() => policy[id] = value!),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(title: Text('删除${row['data']['name']}')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: replacement,
                  decoration: InputDecoration(
                    labelText: kind == 'tag' ? '替代标签' : '替代分类',
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('未使用项可直接删除')),
                    for (final candidate in candidates)
                      DropdownMenuItem<String>(
                        value: candidate['id'],
                        child: Text(candidateLabel(candidate)),
                      ),
                  ],
                  onChanged: (value) => update(() {
                    replacement = value!;
                    budgetPolicy.clear();
                    balancePolicy.clear();
                  }),
                ),
                const SizedBox(height: 18),
                if (problem != null) Text(problem),
                if (plan != null) ...[
                  Text('迁移 ${plan.entryCount} 笔流水（含回收站），金额与日期保留。'),
                  for (final move in plan.moves)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(move),
                    ),
                  for (final budget in plan.budgets)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('预算合并 $budget'),
                    ),
                  for (final id in plan.budgetConflicts) policyChoice(id, true),
                  for (final id in plan.balanceConflicts)
                    policyChoice(id, false),
                  const SizedBox(height: 16),
                  const Text('删除后从分类与标签列表移除，历史归属按上述方案更新。'),
                ],
              ],
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FilledButton(
                  onPressed: ready ? () => Navigator.pop(c, true) : null,
                  child: const Text('确认迁移并删除'),
                ),
              ),
            ),
          );
        },
      ),
      height: .8,
    );
    if (confirmed != true) return;
    try {
      await s.deleteDictionary(
        row['id'],
        replacement,
        budgetPolicy: budgetPolicy,
        balancePolicy: balancePolicy,
      );
      if (mounted) {
        setState(() {});
        message(context, '已删除');
      }
    } catch (error) {
      if (mounted) message(context, error);
    }
  }

  Future<void> reorder(List<Json> list, int old, int next) async {
    if (!editable || query.isNotEmpty || batch) return;
    final ordered = [...list];
    ordered.insert(next, ordered.removeAt(old));
    try {
      await s.saveDictionaryBatch([
        for (var i = 0; i < ordered.length; i++)
          {
            ...ordered[i],
            'data': {...ordered[i]['data'] as Json, 'order': i},
          },
      ]);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> hideSelected(bool hidden) async {
    try {
      await s.saveDictionaryBatch([
        for (final e in rows)
          if (selected.contains(e['id']) ||
              selected.contains(e['data']['parent_id']))
            {
              ...e,
              'data': {...e['data'] as Json, 'archived': hidden},
            },
      ]);
      if (mounted) {
        setState(() {
          batch = false;
          selected.clear();
        });
      }
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Widget rowTile(Json e, {int? index, bool root = false}) {
    final d = e['data'];
    return ListTile(
      key: ValueKey(e['id']),
      dense: true,
      contentPadding: EdgeInsets.only(left: root ? 4 : 16, right: 0),
      leading: batch
          ? Checkbox(
              value: selected.contains(e['id']),
              onChanged: (v) => setState(
                () => v! ? selected.add(e['id']) : selected.remove(e['id']),
              ),
            )
          : CategoryBadge(
              icon: visualIcon(s.active, e),
              color: d['color'],
              name: d['name'],
              size: 34,
            ),
      title: Text(
        d['name'],
        style: TextStyle(
          fontWeight: root ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: d['archived'] == true ? const Text('已隐藏') : null,
      onTap: batch
          ? () => setState(
              () => selected.contains(e['id'])
                  ? selected.remove(e['id'])
                  : selected.add(e['id']),
            )
          : root
          ? () => setState(
              () => collapsed.contains(e['id'])
                  ? collapsed.remove(e['id'])
                  : collapsed.add(e['id']),
            )
          : () => edit(row: e),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (root && !batch)
            IconButton(
              tooltip: '展开或收起${d['name']}',
              onPressed: () => setState(
                () => collapsed.contains(e['id'])
                    ? collapsed.remove(e['id'])
                    : collapsed.add(e['id']),
              ),
              icon: Icon(
                collapsed.contains(e['id'])
                    ? Icons.expand_more
                    : Icons.expand_less,
                size: 19,
              ),
            ),
          if (editable && !batch)
            IconButton(
              tooltip: '编辑${d['name']}',
              onPressed: () => edit(row: e),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          if (editable && index != null && !batch && query.isEmpty)
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 36,
                height: 44,
                child: Icon(Icons.drag_handle, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget group(Json root, int index) {
    final children = rows
        .where(
          (e) =>
              e['data']['parent_id'] == root['id'] &&
              (query.isEmpty ||
                  root['data']['name'].contains(query) ||
                  e['data']['name'].contains(query)),
        )
        .toList();
    return Padding(
      key: ValueKey(root['id']),
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Column(
          children: [
            rowTile(root, root: true, index: index),
            if (!collapsed.contains(root['id']) || query.isNotEmpty) ...[
              const Divider(),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: children.length,
                itemBuilder: (_, i) => rowTile(children[i], index: i),
                onReorderItem: (a, b) => reorder(children, a, b),
              ),
              if (editable && !batch)
                TextButton.icon(
                  onPressed: () => edit(parentId: root['id']),
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('新建二级分类'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    final roots = list
        .where(
          (e) =>
              (kind == 'tag' || e['data']['parent_id'] == '') &&
              (query.isEmpty ||
                  e['data']['name'].contains(query) ||
                  list.any(
                    (c) =>
                        c['data']['parent_id'] == e['id'] &&
                        c['data']['name'].contains(query),
                  )),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类与标签'),
        actions: [
          if (editable)
            TextButton(
              onPressed: () => setState(() {
                batch = !batch;
                selected.clear();
              }),
              child: Text(batch ? '完成' : '批量'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        children: [
          CupertinoSlidingSegmentedControl<String>(
            groupValue: kind,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: .35),
            thumbColor: softSurface(context),
            children: const {
              'category': Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Text('分类'),
              ),
              'tag': Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Text('标签'),
              ),
            },
            onValueChanged: (value) {
              if (value != null) {
                setState(() {
                  kind = value;
                  selected.clear();
                  query = '';
                });
              }
            },
          ),
          space,
          if (kind == 'category') ...[
            Row(
              children: [
                ChoiceChip(
                  label: const Text('支出'),
                  selected: type == 'expense',
                  onSelected: (_) => setState(() {
                    type = 'expense';
                    selected.clear();
                  }),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('收入'),
                  selected: type == 'income',
                  onSelected: (_) => setState(() {
                    type = 'income';
                    selected.clear();
                  }),
                ),
                const Spacer(),
                Text(
                  '${list.length} 个分类',
                  style: TextStyle(color: secondaryInk(context), fontSize: 11),
                ),
              ],
            ),
            space,
          ],
          TextField(
            key: ValueKey(kind),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索名称',
            ),
            onChanged: (v) => setState(() => query = v.trim()),
          ),
          space,
          if (!editable) hint('当前账本的分类不可编辑。'),
          if (roots.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂无匹配项')),
            ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: roots.length,
            itemBuilder: (_, i) => kind == 'category'
                ? group(roots[i], i)
                : rowTile(roots[i], index: i),
            onReorderItem: (a, b) => reorder(roots, a, b),
          ),
          if (kind == 'category' && editable && !batch)
            TextButton.icon(
              icon: const Icon(Icons.auto_awesome_outlined, size: 17),
              label: const Text('补充推荐分类'),
              onPressed: () async {
                final additions = recommendedCategories(s.active);
                if (additions.isEmpty) {
                  message(context, '推荐分类已经齐全');
                  return;
                }
                if (!await approve(
                  context,
                  '补充 ${additions.length} 个分类',
                  '按用途添加两级分类，保留已有名称、顺序和隐藏状态。',
                )) {
                  return;
                }
                try {
                  await s.saveDictionaryBatch(additions);
                  if (mounted) setState(() {});
                } catch (e) {
                  if (context.mounted) message(context, e);
                }
              },
            ),
          hint('改名保留关联，隐藏保留历史。拖动右侧把手调整同级顺序。'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: batch
              ? Row(
                  children: [
                    Text('已选 ${selected.length}'),
                    const Spacer(),
                    TextButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => hideSelected(false),
                      child: const Text('显示'),
                    ),
                    FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => hideSelected(true),
                      child: const Text('隐藏'),
                    ),
                  ],
                )
              : FilledButton.icon(
                  onPressed: editable ? () => edit() : null,
                  icon: const Icon(Icons.add),
                  label: Text(kind == 'tag' ? '新建标签' : '新建一级分类'),
                ),
        ),
      ),
    );
  }
}
