import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';
import 'filter_picker.dart';

class DisplaySettingsPage extends StatefulWidget {
  final LedgerStore store;
  const DisplaySettingsPage(this.store, {super.key});
  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  LedgerStore get s => widget.store;
  late double scale = s.fontScale;
  bool saving = false;
  Future<void> save(double value) async {
    setState(() => saving = true);
    try {
      await s.setFontScale(value);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) {
        setState(() {
          scale = s.fontScale;
          saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    final preview = s.fontPreview.value;
    if (preview != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (s.fontPreview.value == preview) s.fontPreview.value = null;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('字体与显示')),
    body: ListView(
      padding: EdgeInsets.all(pageGutter(context)),
      children: [
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '字体大小',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${(scale * 100).round()}%',
                    key: const ValueKey('font-percent'),
                  ),
                ],
              ),
              Slider(
                key: const ValueKey('font-scale-slider'),
                min: .8,
                max: 1.4,
                value: scale,
                semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                onChanged: saving
                    ? null
                    : (v) {
                        setState(() => scale = v);
                        s.fontPreview.value = v;
                      },
                onChangeEnd: save,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  hint('小'),
                  TextButton(
                    onPressed: saving
                        ? null
                        : () {
                            setState(() => scale = defaultFontScale);
                            s.fontPreview.value = scale;
                            save(scale);
                          },
                    child: const Text('恢复默认'),
                  ),
                  hint('大'),
                ],
              ),
            ],
          ),
        ),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              hint('预览'),
              space,
              Row(
                children: [
                  const CategoryBadge(name: '餐饮'),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '午餐',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text('今天 12:30 · 日常账本', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(
                    '−38.00',
                    style: TextStyle(fontSize: 16, color: expenseInk(context)),
                  ),
                ],
              ),
              space,
              hint('流水、表单、弹窗同步调整'),
            ],
          ),
        ),
        panel(
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('跟随系统字号'),
            subtitle: const Text('开启后叠加系统的文字大小'),
            value: s.state['followSystemFont'] == true,
            onChanged: saving
                ? null
                : (v) async {
                    final before = s.state['followSystemFont'];
                    setState(() => s.state['followSystemFont'] = v);
                    try {
                      await s.persist(preferencesOnly: true);
                    } catch (e) {
                      s.state['followSystemFont'] = before;
                      if (context.mounted) message(context, e);
                    }
                    if (mounted) setState(() {});
                  },
          ),
        ),
      ],
    ),
  );
}

class BalanceSettingsPage extends StatelessWidget {
  final LedgerStore s;
  const BalanceSettingsPage(this.s, {super.key});
  Future<void> choose(BuildContext context, String kind) async {
    final book = s.active;
    final config = book['balance_exclusions'] as Map? ?? {};
    final cats = Set<String>.from(config['categories'] ?? []);
    final tags = Set<String>.from(config['tags'] ?? []);
    final rows = s.choices(kind == '分类' ? 'category' : 'tag', archived: true);
    final value = await Navigator.push<Set<String>>(
      context,
      AppPageRoute(
        builder: (_) => FilterTreePicker(
          title: '排除$kind',
          labels: {for (final e in rows) e['id']: e['data']['name']},
          categories: kind == '分类' ? rows : [],
          selected: kind == '分类' ? cats : tags,
        ),
      ),
    );
    if (value == null || !context.mounted) return;
    try {
      if (s.active['id'] != book['id']) {
        throw const FormatException('账本已切换，请重新选择');
      }
      await s.setBalanceExclusions(
        kind == '分类' ? value : cats,
        kind == '标签' ? value : tags,
      );
      if (context.mounted) notifyApp('结余规则已保存');
    } catch (e) {
      if (context.mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: s,
    builder: (context, _) {
      final config = s.active['balance_exclusions'] as Map? ?? {};
      return Scaffold(
        appBar: AppBar(title: const Text('结余计算')),
        body: ListView(
          padding: EdgeInsets.all(pageGutter(context)),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: hint(s.active['name']),
            ),
            panel(
              Column(
                children: [
                  for (final item in [
                    ('分类', 'categories', Icons.category_outlined),
                    ('标签', 'tags', Icons.sell_outlined),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(item.$3),
                      title: Text('排除${item.$1}'),
                      subtitle: Text(
                        (config[item.$2] as List? ?? []).isEmpty
                            ? '不排除'
                            : '已选 ${(config[item.$2] as List).length} 项',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => choose(context, item.$1),
                    ),
                ],
              ),
            ),
            hint('仅影响本账本结余和日历配色。分类包含子分类，标签命中任意一项即排除；退款跟随原消费。收支总额和预算不变。'),
            if (BalanceRule(s.active).active)
              TextButton(
                onPressed: () async {
                  try {
                    await s.setBalanceExclusions({}, {});
                  } catch (e) {
                    if (context.mounted) message(context, e);
                  }
                },
                child: const Text('清空排除'),
              ),
          ],
        ),
      );
    },
  );
}
