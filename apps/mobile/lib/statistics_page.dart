import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';
import 'transactions.dart';

Map<String, int> aggregateStatistics(
  Json ledger,
  List<Json> rows,
  String type,
  String grouping,
  String currency,
) {
  final result = <String, int>{}, index = ledgerIndex(ledger);
  for (final e in rows) {
    final d = e['data'] as Json;
    if (cashFlowType(d) != type || (d['base_currency'] ?? 'CNY') != currency) {
      continue;
    }
    final c = index.byId[d['category_id']],
        parent = index.byId[c?['data']['parent_id']];
    final names = grouping == '标签'
        ? (d['tag_ids'] as List? ?? [])
              .map((id) => index.byId[id]?['data']['name'] as String? ?? '未命名')
              .toSet()
        : {
            grouping == '一级分类'
                ? (parent?['data']['name'] ??
                          c?['data']['name'] ??
                          d['category'] ??
                          '其他')
                      as String
                : '${parent == null ? '' : '${parent['data']['name']} / '}${categoryName(ledger, d)}',
          };
    for (final name in names.isEmpty ? {'无标签'} : names) {
      result[name] = (result[name] ?? 0) + cashFlowAmount(d);
    }
  }
  return Map.fromEntries(
    result.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs())),
  );
}

class StatisticBucket {
  final String id, label;
  int amount = 0;
  final Set<String> entries = {};
  StatisticBucket(this.id, this.label);
}

List<StatisticBucket> statisticBuckets(
  Json ledger,
  List<Json> rows,
  String type,
  String grouping,
  String currency,
) {
  final index = ledgerIndex(ledger), map = <String, StatisticBucket>{};
  for (final e in rows) {
    final d = e['data'] as Json;
    if (cashFlowType(d) != type || (d['base_currency'] ?? 'CNY') != currency) {
      continue;
    }
    final category = index.byId[d['category_id']],
        parent = index.byId[category?['data']['parent_id']];
    final values = <String, String>{};
    if (grouping == '标签') {
      for (final id in d['tag_ids'] ?? []) {
        values['tag:$id'] = index.byId[id]?['data']['name'] ?? '未命名';
      }
      if (values.isEmpty) values['tag:none'] = '无标签';
    } else {
      final c = grouping == '一级分类' ? (parent ?? category) : category;
      values['category:${c?['id'] ?? d['category_id']}'] =
          grouping == '二级分类' && parent != null
          ? '${parent['data']['name']} / ${categoryName(ledger, d)}'
          : c?['data']['name'] ?? categoryName(ledger, d);
    }
    for (final v in values.entries) {
      final b = map.putIfAbsent(v.key, () => StatisticBucket(v.key, v.value));
      b.amount += cashFlowAmount(d);
      b.entries.add(e['id']);
    }
  }
  return map.values.toList()
    ..sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
}

class StatisticsPage extends StatefulWidget {
  final LedgerStore s;
  final void Function(String, EntryFilter, Set<String>, Json)? onDetails;
  const StatisticsPage(this.s, {super.key, this.onDetails});
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  EntryFilter filter = EntryFilter();
  String periodKey = today(),
      type = 'expense',
      group = '一级分类',
      chart = '饼图',
      currency = '';
  String cacheKey = '', aggregateKey = '', selectedBucket = '';
  List<StatisticBucket> buckets = [];
  late ScrollController scroll;
  LedgerIndex? cacheIndex;
  List<Json> cacheRows = [], _aggregatedRows = [];
  LedgerStore get s => widget.s;
  String scopeId = '';
  int dictionaryRevision = 0;
  void loadScope() {
    dictionaryRevision = s.state['dictionaryRevision'] ?? 0;
    scopeId = s.view['id'];
    final saved = s.state['statisticsFilters']?[scopeId];
    filter = saved is Map
        ? EntryFilter.fromJson(Map<String, dynamic>.from(saved))
        : EntryFilter();
    final view = s.state['statisticsViews']?[scopeId] as Map? ?? {};
    periodKey = view['periodKey'] ?? today();
    type = view['type'] ?? 'expense';
    group = view['group'] ?? '一级分类';
    chart = view['chart'] ?? '饼图';
    currency = view['currency'] ?? '';
    selectedBucket = view['selected'] ?? '';
  }

  @override
  void didUpdateWidget(StatisticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (scopeId != s.view['id'] ||
        dictionaryRevision != (s.state['dictionaryRevision'] ?? 0)) {
      loadScope();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(
            (s.state['statisticsViews']?[scopeId]?['scroll'] as num? ?? 0)
                .toDouble(),
          );
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    loadScope();
    scroll = ScrollController(
      initialScrollOffset:
          (s.state['statisticsViews']?[scopeId]?['scroll'] as num? ?? 0)
              .toDouble(),
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void save() {
    (s.state.putIfAbsent('statisticsViews', () => <String, dynamic>{})
        as Map)[scopeId] = {
      'periodKey': periodKey,
      'type': type,
      'group': group,
      'chart': chart,
      'currency': currency,
      'selected': selectedBucket,
      'scroll': scroll.hasClients ? scroll.offset : 0,
    };
    (s.state.putIfAbsent('statisticsFilters', () => <String, dynamic>{})
        as Map)[scopeId] = filter
        .toJson();
    if (s.database != null) {
      s.queueViewPreferences(
        onError: (Object e) {
          if (mounted) message(context, e);
        },
      );
    }
  }

  Future<void> filters() async {
    final f = await glassSheet<EntryFilter>(
      context,
      FilterPage(
        s,
        filter,
        s.period(periodKey, ledger: s.view),
        ledger: s.view,
      ),
    );
    if (f != null && mounted) {
      setState(() {
        filter = f;
        save();
      });
    }
  }

  void openBucket(StatisticBucket b) {
    selectedBucket = b.id;
    save();
    final p = s.period(periodKey, ledger: s.view), f = filter.copy();
    if (f.start.isEmpty) {
      f.start = p.start;
      f.end = p.end;
    }
    f.detailRule = {
      'kind': 'statistics',
      'bucket': b.id,
      'group': group,
      'type': type,
      'currency': currency,
    };
    widget.onDetails?.call(b.label, f, b.entries, s.view);
  }

  void selectAt(Offset position, int magnitude, {bool persist = false}) {
    final d = position - const Offset(95, 95);
    if (d.distance < 55 || d.distance > 108) {
      return;
    }
    var a = (math.atan2(d.dy, d.dx) + math.pi / 2) % (math.pi * 2), sum = 0.0;
    for (final b in buckets) {
      sum += b.amount.abs() / magnitude * math.pi * 2;
      if (a <= sum) {
        if (selectedBucket != b.id) setState(() => selectedBucket = b.id);
        if (persist) save();
        break;
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = s.period(periodKey, ledger: s.view),
        index = ledgerIndex(s.view),
        key = '${p.id}:${jsonEncode(filter.toJson())}';
    if (cacheKey != key || !identical(index, cacheIndex)) {
      cacheKey = key;
      cacheIndex = index;
      cacheRows = filter.apply(s.view, index.records, p);
    }
    final currencies = s.viewLedgers
        .map((l) => settingsOf(l)['base_currency'] as String)
        .toSet()
        .toList();
    if (!currencies.contains(currency)) currency = currencies.first;
    final ag = '$key/$type/$group/$currency';
    if (aggregateKey != ag || !identical(cacheRows, _aggregatedRows)) {
      aggregateKey = ag;
      _aggregatedRows = cacheRows;
      buckets = statisticBuckets(s.view, cacheRows, type, group, currency);
    }
    final palette = AppPalette.of(c);
    final colors = palette.chartColors;
    final items = buckets.map((b) => MapEntry(b.id, b.amount)).toList(),
        total = items.fold<int>(0, (n, e) => n + e.value),
        magnitude = items.fold<int>(0, (n, e) => n + e.value.abs());
    final activeBucket = buckets
        .where((b) => b.id == selectedBucket)
        .firstOrNull;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        save();
        return false;
      },
      child: CustomScrollView(
        controller: scroll,
        key: const PageStorageKey('statistics'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 30,
                        height: 34,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: '统计上期',
                          onPressed: () => setState(() {
                            periodKey = dateKey(
                              DateTime.parse(
                                p.start,
                              ).subtract(const Duration(days: 1)),
                            );
                            filter.start = '';
                            filter.end = '';
                            save();
                          }),
                          icon: const Icon(Icons.chevron_left, size: 19),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: filters,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              filter.start.isEmpty
                                  ? p.label
                                  : '${filter.start} — ${dateKey(DateTime.parse(filter.end).subtract(const Duration(days: 1)))}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        height: 34,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: '统计下期',
                          onPressed: () => setState(() {
                            periodKey = p.end;
                            filter.start = '';
                            filter.end = '';
                            save();
                          }),
                          icon: const Icon(Icons.chevron_right, size: 19),
                        ),
                      ),
                      const SizedBox(width: 4),
                      CircleAction(
                        tooltip: '统计筛选',
                        onTap: filters,
                        icon: Icons.tune_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppSegmentControl<String>(
                        value: type,
                        items: const [('expense', '支出'), ('income', '收入')],
                        itemPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        fontSize: 11.5,
                        onChanged: (v) => setState(() {
                          type = v;
                          save();
                        }),
                      ),
                      for (final v in currencies)
                        if (currencies.length > 1)
                          ChoiceChip(
                            label: Text(v),
                            selected: currency == v,
                            onSelected: (_) => setState(() {
                              currency = v;
                              save();
                            }),
                          ),
                    ],
                  ),
                  if (filter.chips.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: filter.chips.entries
                            .map(
                              (e) => InputChip(
                                label: Text(e.value),
                                onDeleted: () => setState(() {
                                  filter.clear(e.key);
                                  save();
                                }),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  GlassPanel(
                    radius: isAndroidPlatform ? 22 : 20,
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surface2,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: palette.borderStrong,
                                  width: 0.7,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isDense: true,
                                  value: group,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: palette.ink,
                                  ),
                                  items: ['一级分类', '二级分类', '标签']
                                      .map(
                                        (v) => DropdownMenuItem(
                                          value: v,
                                          child: Text(v),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setState(() {
                                    group = v!;
                                    save();
                                  }),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: palette.segmentTrack,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final item in [
                                    ('饼图', Icons.donut_large_rounded),
                                    ('条形图', Icons.bar_chart_rounded),
                                  ])
                                    Tooltip(
                                      message: item.$1,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () => setState(() {
                                          chart = item.$1;
                                          save();
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: chart == item.$1
                                                ? palette.segmentActive
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Icon(
                                            item.$2,
                                            size: 16,
                                            color: chart == item.$1
                                                ? palette.ink
                                                : palette.ink3,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (group == '标签')
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: hint('多标签记录分别计入'),
                          ),
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(28),
                            child: Text('暂无记录'),
                          ),
                        if (chart == '条形图' && items.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  type == 'income' ? '本期总收入' : '本期总支出',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.ink3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '$currency ${formatAmount(total, currency)}',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.6,
                                      fontFeatures: tabularFigures,
                                      color: type == 'income'
                                          ? incomeInk(c)
                                          : expenseInk(c),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (chart == '饼图' && magnitude > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: SizedBox(
                              height: 186,
                              width: 186,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  GestureDetector(
                                    onTapUp: (e) => selectAt(
                                      e.localPosition,
                                      magnitude,
                                      persist: true,
                                    ),
                                    onLongPressEnd: (_) => save(),
                                    onLongPressStart: (e) =>
                                        selectAt(e.localPosition, magnitude),
                                    onLongPressMoveUpdate: (e) =>
                                        selectAt(e.localPosition, magnitude),
                                    child: SizedBox.expand(
                                      child: CustomPaint(
                                        painter: _PiePainter(
                                          items
                                              .map(
                                                (e) =>
                                                    e.value.abs() / magnitude,
                                              )
                                              .toList(),
                                          colors,
                                          selected: items.indexWhere(
                                            (e) => e.key == selectedBucket,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IgnorePointer(
                                    child: SizedBox(
                                      width: 108,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            activeBucket?.label ??
                                                (type == 'income'
                                                    ? '总收入'
                                                    : '总支出'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: palette.ink3,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              formatAmount(
                                                activeBucket?.amount ?? total,
                                                currency,
                                              ),
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                fontFeatures: tabularFigures,
                                                color: type == 'income'
                                                    ? incomeInk(c)
                                                    : palette.ink,
                                              ),
                                            ),
                                          ),
                                          if (activeBucket != null) ...[
                                            const SizedBox(height: 1),
                                            Text(
                                              '共 ${formatAmount(total, currency)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontFeatures: tabularFigures,
                                                color: palette.brandColor,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (activeBucket != null)
                          TextButton(
                            onPressed: () => openBucket(activeBucket),
                            style: TextButton.styleFrom(
                              backgroundColor: palette.brandSoft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: Text(
                              '${activeBucket.label} · ${formatAmount(activeBucket.amount, currency)} · 查看流水',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontFeatures: tabularFigures,
                                color: palette.brandColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (items.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: GlassPanel(
                  radius: isAndroidPlatform ? 20 : 18,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 14,
                            endIndent: 14,
                            color: palette.border,
                          ),
                        Builder(
                          builder: (c) {
                            final item = items[i],
                                ratio = magnitude == 0
                                    ? 0.0
                                    : item.value.abs() / magnitude;
                            final barColor = colors[i % colors.length];
                            return InkWell(
                              onTap: () => openBucket(buckets[i]),
                              onLongPress: () => setState(() {
                                selectedBucket = item.key;
                                save();
                              }),
                              child: Container(
                                color: selectedBucket == item.key
                                    ? barColor.withValues(alpha: 0.08)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                  horizontal: 14,
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 9,
                                          height: 9,
                                          decoration: BoxDecoration(
                                            color: barColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            buckets[i].label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          formatAmount(item.value, currency),
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: tabularFigures,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 44,
                                          child: Text(
                                            '${(ratio * 100).toStringAsFixed(1)}%',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFeatures: tabularFigures,
                                              color: palette.ink3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 7),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => setState(() {
                                        selectedBucket = item.key;
                                        save();
                                      }),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(99),
                                        child: LinearProgressIndicator(
                                          value: items.first.value == 0
                                              ? 0
                                              : item.value.abs() /
                                                    items.first.value.abs(),
                                          minHeight: chart == '条形图' ? 7 : 4.5,
                                          color: barColor,
                                          backgroundColor: palette.border,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 106)),
        ],
      ),
    );
  }
}

const chartColors = [
  Color(0xFF0E7460),
  Color(0xFFD97736),
  Color(0xFF3B82A6),
  Color(0xFF7E6BB5),
  Color(0xFFC95B6B),
  Color(0xFF5D9E6C),
  Color(0xFFC19D44),
  Color(0xFF668090),
];

class _PiePainter extends CustomPainter {
  final List<double> portions;
  final List<Color> colors;
  final int selected;
  _PiePainter(this.portions, this.colors, {this.selected = -1});
  @override
  void paint(Canvas canvas, Size size) {
    var start = -math.pi / 2;
    final rect = Rect.fromLTWH(16, 16, size.width - 32, size.height - 32);
    for (var i = 0; i < portions.length; i++) {
      final sweep = portions[i] * math.pi * 2;
      final gap = portions.length > 1 ? 0.055 : 0.0;
      final arc = math.max(0.001, sweep - gap);
      canvas.drawArc(
        rect,
        start + gap / 2,
        arc,
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeCap = portions.length > 1 ? StrokeCap.round : StrokeCap.butt
          ..strokeWidth = i == selected ? 26 : 19,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.portions.toString() != portions.toString() ||
      old.selected != selected ||
      old.colors != colors;
}
