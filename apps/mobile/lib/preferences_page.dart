import 'dictionary_page.dart';
import 'display_settings_page.dart';
import 'haptics.dart';

import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';

class PreferencesPage extends StatelessWidget {
  final LedgerStore s;
  const PreferencesPage(this.s, {super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: s,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('外观与账本设置')),
      body: ListView(
        padding: EdgeInsets.all(pageGutter(context)),
        children: [
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '外观',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                AppSegmentControl<String>(
                  expand: true,
                  value: (s.state['theme'] as String?) ?? 'system',
                  items: const [
                    ('system', '系统'),
                    ('light', '浅色'),
                    ('dark', '深色'),
                  ],
                  onChanged: (v) => s.setTheme(v),
                ),
                const SizedBox(height: 14),
                Text(
                  '主题风格',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: secondaryInk(context),
                  ),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final current = appThemeStyleOf(s.state['themeStyle']);
                    final p = AppPalette.of(context);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '质感极简',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: p.ink3,
                            ),
                          ),
                        ),
                        for (final style in AppThemeStyle.classicThemes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Semantics(
                              selected: current == style,
                              button: true,
                              label: style.label,
                              child: InkWell(
                                key: ValueKey('theme-style-${style.id}'),
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => s.setThemeStyle(style.id),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: current == style
                                        ? p.brandSoft
                                        : p.surface2,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: current == style
                                          ? p.brandColor
                                          : p.border,
                                      width: current == style ? 1.3 : 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: style.swatch,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.7,
                                            ),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              style.label,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: p.ink,
                                              ),
                                            ),
                                            Text(
                                              style.subtitle,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: p.ink2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (current == style)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 19,
                                          color: p.brandColor,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                '手账萌宠 · 柔雾哑光',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: p.ink3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: p.brandSoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '6 款',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: p.brandColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (
                          var i = 0;
                          i < AppThemeStyle.cuteThemes.length;
                          i += 2
                        )
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i + 2 < AppThemeStyle.cuteThemes.length
                                  ? 8
                                  : 0,
                            ),
                            child: Row(
                              children: [
                                for (
                                  var j = i;
                                  j < i + 2 &&
                                      j < AppThemeStyle.cuteThemes.length;
                                  j++
                                ) ...[
                                  if (j > i) const SizedBox(width: 8),
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final style =
                                            AppThemeStyle.cuteThemes[j];
                                        final selected = current == style;
                                        final previewBg = p.isDark
                                            ? p.surface2
                                            : style.paperTint;
                                        return Semantics(
                                          selected: selected,
                                          button: true,
                                          label: style.label,
                                          child: InkWell(
                                            key: ValueKey(
                                              'theme-style-${style.id}',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            onTap: () =>
                                                s.setThemeStyle(style.id),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 160,
                                              ),
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    10,
                                                    9,
                                                    8,
                                                    9,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? p.brandSoft
                                                    : previewBg,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: selected
                                                      ? p.brandColor
                                                      : style.swatch.withValues(
                                                          alpha: p.isDark
                                                              ? 0.25
                                                              : 0.34,
                                                        ),
                                                  width: selected ? 1.5 : 0.9,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Container(
                                                              width: 9,
                                                              height: 9,
                                                              decoration:
                                                                  BoxDecoration(
                                                                    color: style
                                                                        .swatch,
                                                                    shape: BoxShape
                                                                        .circle,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              width: 5,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                style.label,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: TextStyle(
                                                                  fontSize:
                                                                      12.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: p.ink,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 3,
                                                        ),
                                                        Text(
                                                          style.badgeText,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: p.ink2,
                                                          ),
                                                        ),
                                                        if (selected) ...[
                                                          const SizedBox(
                                                            height: 3,
                                                          ),
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .check_circle_rounded,
                                                                size: 13,
                                                                color: p
                                                                    .brandColor,
                                                              ),
                                                              const SizedBox(
                                                                width: 3,
                                                              ),
                                                              Text(
                                                                '已启用',
                                                                style: TextStyle(
                                                                  fontSize: 9.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: p
                                                                      .brandColor,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  ThemeMascot(
                                                    style: style,
                                                    size: 42,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          panel(
            Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('每天自动更新汇率'),
                  subtitle: const Text('打开应用或切换币种时更新，断网使用本机汇率'),
                  value: s.state['autoRates'] != false,
                  onChanged: (value) async {
                    s.state['autoRates'] = value;
                    await s.persist(preferencesOnly: true);
                    if (value) {
                      try {
                        await s.updateRates();
                      } catch (_) {}
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "${s.referenceRates['source']} · ${s.referenceRates['date']}",
                  ),
                  subtitle: Text(
                    s.rateError.isEmpty ? '参考汇率用于新账目，已保存金额保持锁定' : s.rateError,
                  ),
                  trailing: TextButton(
                    onPressed: s.updatingRates
                        ? null
                        : () async {
                            try {
                              await s.updateRates(force: true);
                            } catch (_) {}
                          },
                    child: Text(s.updatingRates ? '更新中' : '立即更新'),
                  ),
                ),
              ],
            ),
          ),
          panel(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('字体与显示'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                AppPageRoute(builder: (_) => DisplaySettingsPage(s)),
              ),
            ),
          ),
          panel(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('结余计算'),
              subtitle: const Text('排除分类与标签'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                AppPageRoute(builder: (_) => BalanceSettingsPage(s)),
              ),
            ),
          ),
          panel(
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示结余'),
              value: s.state['showBalance'] != false,
              onChanged: (v) async {
                s.state['showBalance'] = v;
                await s.persist(preferencesOnly: true);
              },
            ),
          ),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '记账键盘触感',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                AppSegmentControl<String>(
                  expand: true,
                  value: (s.state['keyHaptic'] as String?) ?? 'light',
                  items: const [
                    ('off', '关闭'),
                    ('light', '轻'),
                    ('medium', '中'),
                    ('strong', '强'),
                  ],
                  onChanged: (value) async {
                    s.state['keyHaptic'] = value;
                    await keyFeedback(s);
                    await s.persist(preferencesOnly: true);
                  },
                ),
              ],
            ),
          ),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.active['name'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                space,
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('基准币种'),

                  trailing: Text(s.currency),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('月度记账周期'),
                  subtitle: Text(
                    '每月 ${settingsOf(s.active)['rules'].last['day']} 日起',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: s.active['role'] == 'owner'
                      ? () => cycle(context)
                      : null,
                ),

                space,
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('分类与标签'),

                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => DictionaryPage(s)),
                  ),
                ),
                space,
                DropdownButtonFormField<int>(
                  initialValue: s.state['weekStart'] ?? 0,
                  decoration: const InputDecoration(labelText: '日历一周起始日'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('星期日')),
                    DropdownMenuItem(value: 1, child: Text('星期一')),
                  ],
                  onChanged: (v) {
                    s.state['weekStart'] = v;
                    s.persist(preferencesOnly: true);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> cycle(BuildContext context) async {
    var day = settingsOf(s.active)['rules'].last['day'] as int;
    final chosen = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('月度周期起始日'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: day,
                items: List.generate(
                  31,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('每月 ${i + 1} 日'),
                  ),
                ),
                onChanged: (v) => set(() => day = v!),
              ),
              space,
              Text('应用于全部历史流水，交易日期不变。'),
              space,
              const Text('短月取最后一天，预算随所属月份调整。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, day),
              child: const Text('预览'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    final p = periodAt(today(), [
      {'day': chosen, 'effective': '2000-01-01'},
    ]);
    try {
      final budgets = await s.setCycle(chosen, preview: true);
      final changed = budgets
          .where((b) => b['data']['category_id'] == '')
          .map(
            (b) =>
                '${b['data']['start_date']}  ${s.display(b['data']['amount'])}',
          )
          .join('\n');
      if (!context.mounted) return;
      if (await approve(
        context,
        '确认账期调整',
        '本期 ${p.label}\n${changed.isEmpty ? '历史账期同步调整。' : changed}',
      )) {
        await s.setCycle(chosen);
      }
    } catch (e) {
      if (context.mounted) message(context, e);
    }
  }
}
