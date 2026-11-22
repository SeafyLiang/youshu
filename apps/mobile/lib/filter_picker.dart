import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';

class FilterTreePicker extends StatefulWidget {
  final String title;
  final Map<String, String> labels;
  final List<Json> categories;
  final Set<String> selected;
  const FilterTreePicker({
    super.key,
    required this.title,
    required this.labels,
    required this.categories,
    required this.selected,
  });
  @override
  State<FilterTreePicker> createState() => _FilterTreePickerState();
}

class _FilterTreePickerState extends State<FilterTreePicker> {
  late final Set<String> selected = {
    ...widget.selected,
    for (final c in widget.categories)
      if (widget.selected.contains(c['data']['parent_id'])) c['id'] as String,
  };
  final expanded = <String>{};
  late final byId = {for (final c in widget.categories) c['id']: c};
  late final children = <String, List<String>>{
    for (final c in widget.categories)
      if (c['data']['parent_id'] == '')
        c['id']: [
          for (final t in widget.categories)
            if (t['data']['parent_id'] == c['id'] &&
                widget.labels.containsKey(t['id']))
              t['id'],
        ],
  };
  @override
  Widget build(BuildContext c) {
    final items = <String>[];
    for (final id in widget.labels.keys) {
      final parent = byId[id]?['data']['parent_id'] ?? '';
      if (parent != '' && widget.labels.containsKey(parent)) continue;
      items.add(id);
      if (expanded.contains(id)) items.addAll(children[id] ?? []);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('选择${widget.title}'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (selected.containsAll(widget.labels.keys)) {
                selected.clear();
              } else {
                selected.addAll(widget.labels.keys);
              }
            }),
            child: Text(
              selected.containsAll(widget.labels.keys) ? '取消全选' : '全选',
            ),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (c, i) {
          final id = items[i], kids = children[id] ?? [], d = byId[id]?['data'];
          final parent = d?['parent_id'] ?? '', root = parent == '';
          final picked = selected.contains(id),
              partial = !picked && kids.any(selected.contains);
          return Container(
            key: ValueKey('filter-node-$id'),
            margin: EdgeInsets.fromLTRB(root ? 14 : 34, root ? 8 : 0, 14, 0),
            decoration: BoxDecoration(
              color: root
                  ? Theme.of(c).colorScheme.primaryContainer
                        .withValues(alpha: .45)
                  : softSurface(c),
              borderRadius: BorderRadius.circular(root ? 16 : 8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: kids.isEmpty
                      ? Icon(
                          root
                              ? Icons.label_outline
                              : Icons.subdirectory_arrow_right,
                          size: 18,
                          color: secondaryInk(c),
                        )
                      : IconButton(
                          tooltip: expanded.contains(id)
                              ? '收起 ${widget.labels[id]}'
                              : '展开 ${widget.labels[id]}',
                          onPressed: () => setState(() {
                            if (!expanded.add(id)) expanded.remove(id);
                          }),
                          icon: Icon(
                            expanded.contains(id)
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                        ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => toggle(id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        widget.labels[id]!,
                        style: TextStyle(
                          fontSize: root ? 14 : 13,
                          fontWeight: root
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
                if (kids.isNotEmpty)
                  Text(
                    '${kids.where(selected.contains).length}/${kids.length}',
                    style: TextStyle(fontSize: 10, color: secondaryInk(c)),
                  ),
                Checkbox(
                  tristate: true,
                  value: partial ? null : picked,
                  onChanged: (_) => toggle(id),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => Navigator.pop(c, selected),
            child: const Text('确定'),
          ),
        ),
      ),
    );
  }

  void toggle(String id) => setState(() {
    final kids = children[id] ?? [];
    if (selected.contains(id)) {
      selected.remove(id);
      selected.removeAll(kids);
    } else {
      selected.add(id);
      selected.addAll(kids);
    }
    final parent = byId[id]?['data']['parent_id'];
    if (parent != null && parent != '') selected.remove(parent);
  });
}
