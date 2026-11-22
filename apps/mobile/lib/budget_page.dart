import 'dart:math' show max;

import 'budget_pool.dart';
import 'period_controls.dart';

import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';
import 'icon_catalog.dart';
import 'filter_picker.dart';

class BudgetPage extends StatefulWidget {
  final LedgerStore s;
  final String periodKey;
  final ValueChanged<int> onPeriod;
  final ValueChanged<String> onEdit;
  final void Function(String, EntryFilter, Set<String>, Json)? onDetails;
  const BudgetPage(
    this.s, {
    super.key,
    required this.periodKey,
    required this.onPeriod,
    required this.onEdit,
    this.onDetails,
  });
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  String mode = '月', key = '', day = '', scope = '';
  final expanded = <String>{};
  LedgerStore get s => widget.s;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(BudgetPage old) {
    super.didUpdateWidget(old);
    if (scope != s.active['id']) load();
  }

  void load() {
    scope = s.active['id'];
    final v = s.state['budgetViews']?[scope] as Map? ?? {};
    mode = v['mode'] ?? '月';
    key = v['period'] ?? widget.periodKey;
    day = v['day'] ?? today();
    expanded
      ..clear()
      ..addAll(List<String>.from(v['expanded'] ?? []));
  }

  void save() {
    (s.state.putIfAbsent('budgetViews', () => <String, dynamic>{})
        as Map)[scope] = {
      'mode': mode,
      'period': key,
      'day': day,
      'expanded': expanded.toList(),
    };
    if (s.database != null) {
      s.queueViewPreferences(
        onError: (Object e) {
          if (mounted) message(context, e);
        },
      );
    }
  }

  void change(int n) {
    final d = DateTime.parse(s.period(key).start);
    setState(() {
      key = dateKey(
        boundary(
          d.year + (mode == '年' ? n : 0),
          d.month + (mode == '年' ? 0 : n),
          settingsOf(s.active)['rules'].last['day'],
        ),
      );
      save();
    });
  }

  Future<void> globalBudget(bool yearly) async {
    if (s.active['role'] != 'owner') {
      message(context, '预算由所有者管理');
      return;
    }
    final controller = TextEditingController(
      text: s.display(
        settingsOf(s.active)[yearly ? 'yearly_budget' : 'monthly_budget'] ?? 0,
      ),
    );
    final value = await settledDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(yearly ? '默认全年预算' : '默认每月预算'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(suffixText: s.currency),
            ),
            const SizedBox(height: 12),
            Text(
              yearly ? '应用到本账本所有年份，月额度独立。' : '应用到所有历史与未来账期，重置月总额和每日额度，分类预算保留。',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('应用全部周期'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await s.setGlobalBudget(
        parseAmount(value, s.currency, zero: true),
        yearly: yearly,
      );
      if (mounted) {
        setState(() {});
        notifyApp('预算已应用');
      }
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> pickPeriod() async {
    final choice = await chooseMonth(context, s.period(key).start);
    if (choice != null && mounted) {
      setState(() {
        key = s.period(choice).start;
        save();
      });
    }
  }

  Future<void> edit(String category, {String? date}) async {
    if (s.active['role'] != 'owner') {
      message(context, '预算由所有者管理');
      return;
    }
    final amount = date == null
        ? s.budget(key, category)
        : s.dailyBudgets(key)[date] ?? 0;
    final controller = TextEditingController(text: s.display(amount));
    bool reset = false;
    final ok = await settledDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(date == null ? '设置预算' : '$date 预算'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(suffixText: s.currency),
              ),
              if (date == null && category == '全部')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: reset,
                  onChanged: (v) => set(() => reset = v!),
                  title: const Text('重置每日额度', style: TextStyle(fontSize: 13)),
                ),
            ],
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
    if (ok == true) {
      try {
        final n = parseAmount(controller.text, s.currency, zero: true);
        if (date == null) {
          await s.setBudget(key, category, n, resetDays: reset);
        } else {
          await s.setDailyBudget(date, n);
        }
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) message(context, e);
      }
    }
    controller.dispose();
  }

  Future<void> exclude(String kind) async {
    final cats = s.choices('category', type: 'expense', archived: true),
        tags = s.choices('tag', archived: true),
        settings = settingsOf(s.active);
    final catSet = Set<String>.from(
          settings['budget_excluded_categories'] ?? [],
        ),
        tagSet = Set<String>.from(settings['budget_excluded_tags'] ?? []);
    final options = kind == '分类' ? cats : tags;
    final value = await Navigator.push<Set<String>>(
      context,
      AppPageRoute(
        builder: (_) => FilterTreePicker(
          title: '排除$kind',
          labels: {for (final e in options) e['id']: e['data']['name']},
          categories: kind == '分类' ? cats : [],
          selected: kind == '分类' ? catSet : tagSet,
        ),
      ),
    );
    if (value != null) {
      try {
        await s.setBudgetExclusions(
          kind == '分类' ? value : catSet,
          kind == '标签' ? value : tagSet,
        );
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) message(context, e);
      }
    }
  }

  void detail(String date, {String? category}) {
    final p = s.period(key),
        idx = ledgerIndex(s.active),
        settings = settingsOf(s.active),
        excluded = Set<String>.from(
          settings['budget_excluded_categories'] ?? [],
        ),
        tags = Set<String>.from(settings['budget_excluded_tags'] ?? []);
    for (final c in idx.byKind['category'] ?? <Json>[]) {
      if (excluded.contains(c['data']['parent_id'])) excluded.add(c['id']);
    }
    final ids = idx.records
        .where((e) {
          final d = e['data'] as Json,
              source = isRefund(d)
                  ? (idx.byId[d['refund_of']]?['data'] ?? d)
                  : d;
          return d['type'] == 'expense' &&
              p.contains(d['date']) &&
              (date.isEmpty || d['date'] == date) &&
              !excluded.contains(source['category_id']) &&
              !(source['tag_ids'] as List).any(tags.contains) &&
              (category == null ||
                  source['category_id'] == category ||
                  idx.byId[source['category_id']]?['data']['parent_id'] ==
                      category);
        })
        .map((e) => e['id'] as String)
        .toSet();
    final f = EntryFilter()
      ..start = date.isEmpty ? p.start : date
      ..end = date.isEmpty
          ? p.end
          : dateKey(DateTime.parse(date).add(const Duration(days: 1)));
    f.detailRule = {'kind': 'budget', 'category': category};
    widget.onDetails?.call('预算明细', f, ids, s.active);
  }

  Widget budgetOverview(
    int spent,
    int limit,
    String title,
    VoidCallback settings, {
    String? compliance,
    String? horizon,
    int? daysLeft,
  }) {
    final p = AppPalette.of(context);
    final accent = budgetColor(context, spent, limit);
    final remPct = limit <= 0
        ? null
        : ((limit - spent) / limit * 100).round();
    return GlassPanel(
      radius: isAndroidPlatform ? 22 : 20,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      limit <= 0
                          ? '$title预算未设置'
                          : '$title${spent > limit ? '超支' : '剩余'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: p.ink2,
                      ),
                    ),
                    if (remPct != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          spent > limit
                              ? '超 ${(-remPct).abs()}%'
                              : '余 ${remPct.clamp(0, 100)}%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabularFigures,
                            color: accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: p.surface2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 4,
                  ),
                  minimumSize: const Size(44, 28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: settings,
                child: const Text('设置'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MarkerHighlight(
              height: 10,
              bottom: 3,
              child: Text(
                limit <= 0
                    ? '—'
                    : '${moneySymbol(s.currency)}${s.display((limit - spent).abs())}',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                  fontFeatures: tabularFigures,
                  color: accent,
                ),
              ),
            ),
          ),
          SizedBox(height: p.style.isCute ? 22 : 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final progress = limit <= 0
                  ? 0.0
                  : (spent / limit).clamp(0.0, 1.0);
              final track = ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  color: accent,
                  backgroundColor: p.segmentTrack,
                ),
              );
              if (!p.style.isCute) return track;
              final mascotLeft = (constraints.maxWidth * progress - 15)
                  .clamp(0.0, (constraints.maxWidth - 30).clamp(0.0, 9999.0));
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  track,
                  Positioned(
                    left: mascotLeft,
                    top: -25,
                    child: IgnorePointer(
                      child: ThemeMascot(
                        style: p.style,
                        size: 30,
                        mood: spent > limit
                            ? MascotMood.curious
                            : MascotMood.happy,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                '预算 ${limit <= 0 ? '未设置' : '${moneySymbol(s.currency)}${s.display(limit)}'}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontFeatures: tabularFigures,
                  color: p.ink2,
                ),
              ),
              Text(
                '已用 ${moneySymbol(s.currency)}${s.display(spent)}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontFeatures: tabularFigures,
                  color: p.ink2,
                ),
              ),
            ],
          ),
          if (compliance != null || daysLeft != null) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (compliance != null) hint(compliance),
                if (horizon != null) hint(horizon),
                if (daysLeft != null) ...[
                  hint('距账期结束 $daysLeft 天（含今天）'),
                  if (limit > 0)
                    Text(
                      '日均可用 ${moneySymbol(s.currency)}${s.display(max(0, limit - spent) ~/ daysLeft)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularFigures,
                        color: p.brandColor,
                      ),
                    ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget summary(String period, int limit, int spent) {
    return BudgetPool(
      spent: spent,
      limit: limit,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${DateTime.parse(s.period(period).start).month}月',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                s.display(spent),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: budgetColor(context, spent, limit),
                ),
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                limit <= 0
                    ? '未设预算'
                    : '${spent > limit ? '超' : '余'} ${s.display((limit - spent).abs())}',
                style: TextStyle(
                  fontSize: 10,
                  color: budgetColor(context, spent, limit),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = s.period(key),
        cats = s.choices('category', type: 'expense', archived: true),
        q = budgetQuery(s.active, p);
    final now = today(),
        dates = periodDays(p),
        allocation = mode == '日' ? s.dailyBudgets(key) : const <String, int>{},
        year = DateTime.parse(p.start).year,
        periods = [
          for (var m = 1; m <= 12; m++)
            dateKey(
              boundary(year, m, settingsOf(s.active)['rules'].last['day']),
            ),
        ];
    final annual = mode == '年'
        ? [for (final k in periods) (k, s.budget(k, '全部'), s.budgetSpent(k))]
        : const <(String, int, int)>[];
    return PeriodSwipe(
      onChange: change,
      child: CustomScrollView(
        key: PageStorageKey('budget-$scope-$mode'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppSegmentControl<String>(
                          expand: true,
                          value: mode,
                          items: const [('年', '年'), ('月', '月'), ('日', '日')],
                          itemPadding: const EdgeInsets.symmetric(vertical: 6),
                          onChanged: (v) => setState(() {
                            mode = v;
                            save();
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: '预算排除',
                        onSelected: (v) {
                          if (v == '全月') {
                            globalBudget(false);
                          } else if (v == '全年') {
                            globalBudget(true);
                          } else {
                            exclude(v);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: '全月',
                            child: Text('默认每月预算'),
                          ),
                          const PopupMenuItem(
                            value: '全年',
                            child: Text('默认全年预算'),
                          ),
                          const PopupMenuItem(value: '分类', child: Text('排除分类')),
                          const PopupMenuItem(value: '标签', child: Text('排除标签')),
                        ],
                        icon: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppPalette.of(c).card,
                            border: Border.all(
                              color: AppPalette.of(c).borderStrong,
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 17,
                            color: AppPalette.of(c).ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => change(-1),
                          icon: const Icon(Icons.chevron_left, size: 19),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: pickPeriod,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              mode == '年' ? '$year 年' : p.label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => change(1),
                          icon: const Icon(Icons.chevron_right, size: 19),
                        ),
                      ),
                    ],
                  ),
                  if (mode != '年')
                    budgetOverview(
                      s.budgetSpent(key),
                      s.budget(key, '全部'),
                      '本期',
                      () => edit('全部'),
                      daysLeft: p.contains(now)
                          ? dates
                                .where((date) => date.compareTo(now) >= 0)
                                .length
                          : null,
                      compliance: mode == '日'
                          ? '未超预算天数 ${dates.where((date) {
                              final limit = allocation[date] ?? 0;
                              return limit > 0 && (q.days[date] ?? 0) <= limit;
                            }).length}/${dates.length}'
                          : null,
                      horizon: mode == '日' ? '含未来日期' : null,
                    ),
                  if (mode == '年') ...[
                    budgetOverview(
                      annual.fold<int>(0, (n, month) => n + month.$3),
                      s.yearlyBudget ??
                          annual.fold<int>(0, (n, month) => n + month.$2),
                      '年度',
                      () => globalBudget(true),
                      compliance:
                          '未超预算月数 ${annual.where((month) => month.$2 > 0 && month.$3 <= month.$2).length}/12',
                      horizon: '含未来月份',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '月度预算',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (c, constraints) {
                        final scale = MediaQuery.textScalerOf(c).scale(12) / 12;
                        return GridView.count(
                          padding: EdgeInsets.zero,
                          crossAxisCount:
                              constraints.maxWidth >= 320 && scale <= 1.2
                              ? 3
                              : 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          mainAxisExtent: 82 * scale.clamp(1, 1.6),
                          children: [
                            for (final (period, limit, spent) in annual)
                              InkWell(
                                onTap: () => setState(() {
                                  key = period;
                                  mode = '月';
                                  save();
                                }),
                                borderRadius: BorderRadius.circular(16),
                                child: summary(period, limit, spent),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Center(child: hint('水位表示预算使用比例')),
                  ],
                  if (mode == '日') ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        for (final w in ['一', '二', '三', '四', '五', '六', '日'])
                          Expanded(
                            child: Center(
                              child: Text(
                                w,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: secondaryInk(c),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (c) {
                        final offset = DateTime.parse(p.start).weekday - 1;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisExtent:
                                    30 + MediaQuery.textScalerOf(c).scale(26),
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 5,
                              ),
                          itemCount: offset + dates.length,
                          itemBuilder: (c, i) {
                            if (i < offset) return const SizedBox.shrink();
                            final date = dates[i - offset],
                                spent = q.days[date] ?? 0,
                                limit = allocation[date] ?? 0,
                                future = date.compareTo(now) > 0;
                            return InkWell(
                              onTap: () => setState(() {
                                day = date;
                                save();
                              }),
                              child: BudgetPool(
                                spent: spent,
                                limit: limit,
                                selected: day == date,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 7,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '${DateTime.parse(date).day}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: future
                                              ? secondaryInk(c)
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      if (!future || spent != 0)
                                        FittedBox(
                                          child: Text(
                                            s.display(spent),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: budgetColor(
                                                c,
                                                spent,
                                                limit,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    if (p.contains(day))
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: GlassPanel(
                          radius: isAndroidPlatform ? 18 : 16,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              day,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                            subtitle: Text(
                              '已用 ${s.display(q.days[day] ?? 0)} · 预算 ${s.display(allocation[day] ?? 0)}',
                              style: const TextStyle(
                                fontFeatures: tabularFigures,
                              ),
                            ),
                            trailing: Wrap(
                              children: [
                                TextButton(
                                  onPressed: () => edit('全部', date: day),
                                  child: const Text('额度'),
                                ),
                                TextButton(
                                  onPressed: () => detail(day),
                                  child: const Text('流水'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (mode == '月') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          '分类预算',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.of(c).ink2,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => detail(''),
                          child: const Text('查看流水'),
                        ),
                      ],
                    ),
                    GlassPanel(
                      radius: isAndroidPlatform ? 20 : 18,
                      child: Builder(
                        builder: (c) {
                          final pal = AppPalette.of(c);
                          final roots = cats
                              .where((e) => e['data']['parent_id'] == '')
                              .toList();
                          return Column(
                            children: [
                              for (var idx = 0; idx < roots.length; idx++) ...[
                                if (idx > 0)
                                  Divider(
                                    height: 1,
                                    indent: 14,
                                    endIndent: 14,
                                    color: pal.border,
                                  ),
                                Builder(
                                  builder: (c) {
                                    final root = roots[idx];
                                    final spent = q.categories[root['id']] ?? 0;
                                    final limit = s.budget(key, root['id']);
                                    final ratio = limit <= 0
                                        ? 0.0
                                        : (spent / limit).clamp(0.0, 1.0);
                                    final barColor = budgetColor(
                                      c,
                                      spent,
                                      limit,
                                    );
                                    return Column(
                                      children: [
                                        InkWell(
                                          onTap: () => setState(() {
                                            if (!expanded.add(root['id'])) {
                                              expanded.remove(root['id']);
                                            }
                                            save();
                                          }),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                CategoryBadge(
                                                  name: root['data']['name'],
                                                  icon: visualIcon(
                                                    s.active,
                                                    root,
                                                  ),
                                                  color: root['data']['color'],
                                                  size: 34,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              root['data']['name'],
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        13.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Text(
                                                            '${s.display(spent)} / ${s.display(limit)}',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontFeatures:
                                                                  tabularFigures,
                                                              color: pal.ink2,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              99,
                                                            ),
                                                        child:
                                                            LinearProgressIndicator(
                                                              value: ratio,
                                                              minHeight: 4,
                                                              color: barColor,
                                                              backgroundColor:
                                                                  pal.border,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: () =>
                                                      edit(root['id']),
                                                  icon: Icon(
                                                    Icons.edit_outlined,
                                                    size: 16,
                                                    color: pal.ink3,
                                                  ),
                                                ),
                                                Icon(
                                                  expanded.contains(root['id'])
                                                      ? Icons.expand_less
                                                      : Icons.expand_more,
                                                  size: 18,
                                                  color: pal.ink3,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (expanded.contains(root['id']))
                                          Container(
                                            color: pal.surface2,
                                            padding: const EdgeInsets.only(
                                              left: 22,
                                              right: 8,
                                            ),
                                            child: Column(
                                              children: [
                                                for (final child in cats.where(
                                                  (e) =>
                                                      e['data']['parent_id'] ==
                                                      root['id'],
                                                ))
                                                  ListTile(
                                                    dense: true,
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                        ),
                                                    leading: CatalogIcon(
                                                      visualIcon(
                                                        s.active,
                                                        child,
                                                      ),
                                                      size: 19,
                                                      color: pal.ink2,
                                                    ),
                                                    title: Text(
                                                      child['data']['name'],
                                                      style: const TextStyle(
                                                        fontSize: 12.5,
                                                      ),
                                                    ),
                                                    subtitle: Text(
                                                      '${s.display(q.categories[child['id']] ?? 0)} / ${s.display(s.budget(key, child['id']))}',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontFeatures:
                                                            tabularFigures,
                                                      ),
                                                    ),
                                                    onTap: () => detail(
                                                      '',
                                                      category: child['id'],
                                                    ),
                                                    trailing: IconButton(
                                                      onPressed: () =>
                                                          edit(child['id']),
                                                      icon: Icon(
                                                        Icons.edit_outlined,
                                                        size: 16,
                                                        color: pal.ink3,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
    );
  }
}
