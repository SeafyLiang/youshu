import 'display_dates.dart';
import 'budget_pool.dart';
import 'batch_page.dart';
import 'data_pages.dart';
import 'period_controls.dart';

import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show setEquals;

import 'store.dart';
import 'ui.dart';
import 'filter_picker.dart';

class Transactions extends StatefulWidget {
  final LedgerStore s;
  final EntryFilter? initialFilter;
  final Set<String>? onlyIds;
  final bool Function(Json)? includeRecord;
  final Json? scopeLedger;
  final bool temporary;
  final ValueChanged<String>? onVisiblePeriod;
  final String periodKey;
  final Widget? summary, bookPicker, shortcuts;
  final Widget Function(Json) tile;
  final void Function(String) add;
  const Transactions(
    this.s, {
    super.key,
    required this.periodKey,
    this.summary,
    this.shortcuts,
    this.bookPicker,
    this.initialFilter,
    this.onlyIds,
    this.includeRecord,
    this.scopeLedger,
    this.temporary = false,
    this.onVisiblePeriod,
    required this.tile,
    required this.add,
  });
  @override
  State<Transactions> createState() => TransactionsState();
}

class TransactionsState extends State<Transactions> {
  EntryFilter filter = EntryFilter();
  bool calendar = false, collapsed = false, monthly = false;
  bool get balanceMode => s.state['transactionDimension'] == 'balance';
  int displayedTotal(List<Json> rows) =>
      balanceMode ? BalanceRule(ledger).total(rows) : sum(rows, 'expense');
  final moreController = OverlayPortalController();
  final moreLink = LayerLink();
  void closeMore() {
    if (moreController.isShowing) moreController.hide();
  }

  final Set<String> foldedDays = {}, openMonths = {};
  late String selected, month, scopeId;
  final search = TextEditingController();
  late ScrollController scroll;
  String loadedStart = '', loadedEnd = '', visiblePeriod = '';
  bool extending = false;
  final anchors = <String, GlobalKey>{};
  int dictionaryRevision = 0;
  String get modeKey => calendar
      ? 'calendar'
      : monthly
      ? 'monthly'
      : 'list';
  LedgerStore get s => widget.s;
  Json get ledger => widget.scopeLedger ?? s.view;
  @override
  void initState() {
    super.initState();
    loadScope();
    scroll = ScrollController(
      initialScrollOffset: widget.temporary
          ? 0
          : ((s.state['transactionViews']?[scopeId]?['modes']?[modeKey]?['offset']
                        as num?) ??
                    0)
                .toDouble(),
    );
  }

  void loadScope() {
    dictionaryRevision = s.state['dictionaryRevision'] ?? 0;
    scopeId = ledger['id'];
    if (widget.temporary) {
      final initialPeriod = s.period(widget.periodKey, ledger: ledger);
      visiblePeriod = initialPeriod.start;
      loadedStart = initialPeriod.start;
      loadedEnd = initialPeriod.end;
      filter = widget.initialFilter!.copy();
      selected = filter.start.isEmpty ? initialPeriod.start : filter.start;
      month = selected.substring(0, 7);
      search.text = filter.keyword;
      return;
    }
    filter = EntryFilter();
    calendar = monthly = collapsed = false;
    foldedDays.clear();
    openMonths.clear();
    final saved = s.state['transactionFilters']?[scopeId];
    if (saved is Map) {
      filter = EntryFilter.fromJson(Map<String, dynamic>.from(saved));
    }
    final p = s.period(widget.periodKey, ledger: ledger);
    loadedStart = p.start;
    loadedEnd = p.end;
    visiblePeriod = '${today().substring(0, 7)}-01';
    selected = p.contains(today()) ? today() : p.start;
    month = selected.substring(0, 7);
    search.text = filter.keyword;
    final view = s.state['transactionViews']?[ledger['id']];
    if (view is Map) {
      calendar = view['calendar'] == true;
      monthly = view['monthly'] == true;
      foldedDays.addAll(List<String>.from(view['foldedDays'] ?? []));
      openMonths.addAll(List<String>.from(view['openMonths'] ?? []));
      final v = view['modes']?[modeKey] as Map? ?? {};
      loadedStart = v['loadedStart'] ?? loadedStart;
      loadedEnd = v['loadedEnd'] ?? loadedEnd;
      visiblePeriod = v['visiblePeriod'] ?? visiblePeriod;
      selected = v['selected'] ?? selected;
      month = v['month'] ?? month;
    }
    if (visiblePeriod != p.start) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onVisiblePeriod?.call(visiblePeriod);
      });
    }
  }

  @override
  void didUpdateWidget(Transactions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (scopeId != ledger['id'] ||
        dictionaryRevision != (s.state['dictionaryRevision'] ?? 0)) {
      loadScope();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(
            ((s.state['transactionViews']?[scopeId]?['modes']?[modeKey]?['offset']
                        as num?) ??
                    0)
                .toDouble(),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    search.dispose();
    super.dispose();
  }

  int sum(List<Json> rows, String type) => rows
      .where((e) => cashFlowType(e['data']) == type)
      .fold(0, (n, e) => n + cashFlowAmount(e['data']));
  String compact(int n) => n / unit(s.currency) >= 10000
      ? '${(n / unit(s.currency) / 10000).toStringAsFixed(1)}万'
      : formatAmount(n, s.currency);
  Future<void> filters() async {
    final value = await glassSheet<EntryFilter>(
      context,
      FilterPage(
        s,
        filter,
        s.period(widget.periodKey, ledger: ledger),
        ledger: ledger,
      ),
    );
    if (value != null) {
      setState(() {
        filter = value;
        saveFilter();
        search.text = filter.keyword;
        if (filter.start.isNotEmpty) {
          selected = filter.start;
          month = selected.substring(0, 7);
        }
      });
    }
  }

  void saveFilter() {
    if (widget.temporary) return;
    (s.state.putIfAbsent('transactionFilters', () => <String, dynamic>{})
        as Map)[ledger['id']] = filter
        .toJson();
    final old = s.state['transactionViews']?[scopeId] as Map? ?? {};
    (s.state.putIfAbsent('transactionViews', () => <String, dynamic>{})
        as Map)[ledger['id']] = {
      'modes': {
        ...?old['modes'] as Map?,
        modeKey: {
          'filter': filter.toJson(),
          'loadedStart': loadedStart,
          'loadedEnd': loadedEnd,
          'visiblePeriod': visiblePeriod,
          'selected': selected,
          'month': month,
          'offset': scroll.hasClients ? scroll.offset : 0,
        },
      },
      'calendar': calendar,
      'monthly': monthly,
      'foldedDays': foldedDays.toList(),
      'openMonths': openMonths.toList(),
    };
    if (s.database != null) {
      s.queueViewPreferences(
        onError: (Object e) {
          if (mounted) message(context, e);
        },
      );
    }
  }

  Future<void> openBatch() async {
    if (s.viewLedgers.length != 1 || ledger['id'] != s.active['id']) {
      message(context, '请先切换到单个当前账本进行批量操作');
      return;
    }
    if (!s.canEdit) {
      message(context, '当前账本没有编辑权限');
      return;
    }
    final ids = queryRows(s.period(widget.periodKey, ledger: ledger))
        .map((e) => (e['source_entry_id'] ?? e['id']) as String)
        .toSet();
    await Navigator.push(
      context,
      AppPageRoute(builder: (_) => BatchPage(s, ids)),
    );
    if (mounted) setState(() {});
  }

  void openExport() {
    Map<String, Set<String>>? selected;
    if (filter.chips.isNotEmpty || widget.temporary) {
      selected = {for (final book in s.viewLedgers) book['id'] as String: {}};
      for (final row in queryRows(s.period(widget.periodKey, ledger: ledger))) {
        final book = (row['source_ledger_id'] ?? ledger['id']) as String;
        selected
            .putIfAbsent(book, () => {})
            .add((row['source_entry_id'] ?? row['id']) as String);
      }
    }
    openDataPage(
      context,
      ExportEntriesPage(s, period: visiblePeriod, filtered: selected),
    );
  }

  Future<void> openSearch() async {
    final draft = TextEditingController(text: filter.keyword);
    final result = await glassSheet<String>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '搜索流水',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: draft,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '备注、分类、标签、账户',
                prefixIcon: Icon(CupertinoIcons.search),
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft.text),
              child: const Text('查看结果'),
            ),
          ],
        ),
      ),
      height: 0.48,
    );
    if (result != null && mounted) {
      setState(() {
        filter.keyword = result;
        search.text = result;
        saveFilter();
      });
    }
  }

  Widget pill(
    String text, {
    IconData? icon,
    VoidCallback? onTap,
    bool active = false,
  }) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap ?? filters,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 28),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? p.brandSoft : p.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? Colors.transparent : p.borderStrong,
              width: 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: active ? p.brandColor : p.ink2),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? p.brandColor : p.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void changeView(String value) => setState(() {
    saveFilter();
    calendar = value == 'calendar';
    monthly = value == 'month';
    final v = s.state['transactionViews']?[scopeId]?['modes']?[modeKey] as Map?;
    if (v != null) {
      loadedStart = v['loadedStart'];
      loadedEnd = v['loadedEnd'];
      visiblePeriod = v['visiblePeriod'];
      month = v['month'];
      selected = v['selected'];
    } else {
      openMonths.clear();
    }
    if (scroll.hasClients) {
      scroll.jumpTo((v?['offset'] as num? ?? 0).toDouble());
    }
    saveFilter();
  });

  Widget viewSwitch() => AppSegmentControl<String>(
    value: calendar
        ? 'calendar'
        : monthly
        ? 'month'
        : 'list',
    items: const [('list', '列表'), ('calendar', '日历'), ('month', '按月')],
    itemPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
    fontSize: 11,
    onChanged: changeView,
  );

  String _queryKey = '';
  LedgerIndex? _queryIndex;
  List<Json> _queryRows = [];
  Set<String>? _queryOnlyIds;
  List<Json> queryRows(BookPeriod p) {
    final index = ledgerIndex(ledger),
        key =
            '$modeKey/$loadedStart/$loadedEnd/$month/${p.id}:${jsonEncode(filter.toJson())}';
    final effective = filter.copy();
    if (effective.start.isEmpty && !widget.temporary) {
      if (monthly) {
        effective.start = '0001-01-01';
        effective.end = '9999-12-31';
      } else if (calendar) {
        final d = DateTime.parse('$month-01');
        effective.start = dateKey(d);
        effective.end = dateKey(DateTime(d.year, d.month + 1));
      } else {
        effective.start = '0001-01-01';
        effective.end = '9999-12-31';
      }
    }
    if (!identical(index, _queryIndex) ||
        key != _queryKey ||
        !setEquals(widget.onlyIds, _queryOnlyIds)) {
      _queryIndex = index;
      _queryKey = key;
      _queryOnlyIds = widget.onlyIds == null ? null : Set.of(widget.onlyIds!);
      _queryRows = effective.apply(
        ledger,
        widget.onlyIds == null
            ? index.records
            : index.records
                  .where((e) => widget.onlyIds!.contains(e['id']))
                  .toList(),
        p,
      );
    }
    return widget.includeRecord == null
        ? _queryRows
        : _queryRows.where(widget.includeRecord!).toList();
  }

  bool get mixed =>
      s.viewLedgers.map((l) => settingsOf(l)['base_currency']).toSet().length >
      1;
  @override
  Widget build(BuildContext context) {
    final period = s.period(widget.periodKey, ledger: ledger),
        rows = queryRows(period),
        day = calendar
            ? rows.where((e) => e['data']['date'] == selected).toList()
            : const <Json>[];
    final start = filter.start.isEmpty ? period.start : filter.start,
        end = filter.end.isEmpty ? period.end : filter.end;
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: trackScroll,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              controller: scroll,
              key: PageStorageKey("transactions-${ledger['id']}"),
              slivers: [
                if (widget.bookPicker != null)
                  SliverToBoxAdapter(
                    child: Builder(
                      builder: (context) {
                        final pal = AppPalette.of(context);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 1, 16, 0),
                          child: Row(
                            children: [
                              Flexible(child: widget.bookPicker!),
                              if (pal.style.isCute) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: pal.brandSoft,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        pal.style.badgeText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          color: pal.brandDeep,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ThemeMascot(
                                  style: pal.style,
                                  size: 36,
                                  mood: MascotMood.signature,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (widget.shortcuts != null)
                  SliverToBoxAdapter(child: widget.shortcuts),
                PinnedHeaderSliver(child: fixedHeader(period)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            viewSwitch(),
                            if (!calendar)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${filter.start.isEmpty ? '全部时间' : '$start — ${dateKey(DateTime.parse(end).subtract(const Duration(days: 1)))}'} · ${rows.length} 笔',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontFeatures: tabularFigures,
                                      color: mutedInk(context),
                                    ),
                                  ),
                                  if (!monthly) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => setState(() {
                                        final keys = rows
                                            .map(
                                              (e) => e['data']['date'] as String,
                                            )
                                            .toSet();
                                        if (foldedDays.containsAll(keys)) {
                                          foldedDays.clear();
                                        } else {
                                          foldedDays.addAll(keys);
                                        }
                                        saveFilter();
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          foldedDays.isEmpty ? '按日折叠' : '全部展开',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: expenseInk(context),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                        if (filter.chips.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                for (final entry in filter.chips.entries)
                                  InputChip(
                                    label: Text(entry.value),
                                    visualDensity: VisualDensity.compact,
                                    onDeleted: () => setState(() {
                                      filter.clear(entry.key);
                                      saveFilter();
                                    }),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (calendar) ...[
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: pickMonth,
                                  child: Text(
                                    '${month.substring(0, 4)} 年 ${int.parse(month.substring(5))} 月',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.4,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 30,
                                height: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  tooltip: '日历上月',
                                  onPressed: () => move(-1),
                                  icon: const Icon(
                                    CupertinoIcons.chevron_left,
                                    size: 14,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 30,
                                height: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  tooltip: '日历下月',
                                  onPressed: () => move(1),
                                  icon: const Icon(
                                    CupertinoIcons.chevron_right,
                                    size: 14,
                                  ),
                                ),
                              ),
                              pill(
                                '今天',
                                active: true,
                                onTap: () => selectDay(today()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (!collapsed)
                            GlassPanel(
                              radius: 18,
                              padding: const EdgeInsets.fromLTRB(
                                10,
                                10,
                                10,
                                8,
                              ),
                              child: PeriodSwipe(
                                onChange: move,
                                child: calendarGrid(rows, period),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '自然月日历 · ${s.currency}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: secondaryInk(context),
                                  ),
                                ),
                              ),
                              Text(
                                mixed
                                    ? '多币种'
                                    : '${balanceMode ? '结余' : '支出'} ${s.display(displayedTotal(rows.where((e) => (e['data']['date'] as String).startsWith(month)).toList()))}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: tabularFigures,
                                  color: expenseInk(context),
                                ),
                              ),
                              SizedBox(
                                width: 30,
                                height: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  tooltip: collapsed ? '展开月历' : '收起月历',
                                  onPressed: () =>
                                      setState(() => collapsed = !collapsed),
                                  icon: Icon(
                                    collapsed
                                        ? CupertinoIcons.chevron_down
                                        : CupertinoIcons.chevron_up,
                                    size: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Divider(color: hairline(context)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                dayLabel(selected),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${day.length} 笔记录',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: secondaryInk(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (day.isNotEmpty)
                            const SizedBox.shrink()
                          else
                            panel(
                              Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.calendar,
                                      size: 26,
                                    ),
                                    const SizedBox(height: 8),
                                    hint('这一天，还没有记录'),
                                  ],
                                ),
                              ),
                            ),
                          if (!widget.temporary)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => widget.add(selected),
                                icon: const Icon(CupertinoIcons.plus, size: 13),
                                label: Text(
                                  '记入 $selected',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                        ] else ...[
                          if (rows.isEmpty)
                            panel(
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 26,
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.list_bullet,
                                      size: 26,
                                    ),
                                    const SizedBox(height: 10),
                                    const Text('从今天的第一笔开始'),
                                    const SizedBox(height: 5),
                                    hint('还没有匹配记录，记一笔或调整筛选'),
                                  ],
                                ),
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: lazyRows(calendar ? day : rows),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 106)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  final groupLimits = <String, int>{};
  Future<void> pickMonth() async {
    final choice = await chooseMonth(context, calendar ? month : visiblePeriod);
    if (choice != null && mounted) jumpToMonth(choice);
  }

  void jumpToMonth(String value) {
    final date = DateTime.parse('${value.substring(0, 7)}-01');
    final start = dateKey(date),
        end = dateKey(DateTime(date.year, date.month + 1));
    setState(() {
      month = value.substring(0, 7);
      selected = start;
      visiblePeriod = start;
      if (!calendar) {
        filter.start = start;
        filter.end = end;
      }
      groupLimits.clear();
      saveFilter();
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    widget.onVisiblePeriod?.call(start);
  }

  LedgerIndex? _headerIndex;
  String _headerKey = '';
  List<Json>? _headerSource;
  Map<String, List<int>> _headerSums = {};
  bool _headerBalanceActive = false;

  Widget fixedHeader(BookPeriod p) {
    final d = DateTime.parse(
      '${calendar ? month : visiblePeriod.substring(0, 7)}-01',
    );
    final from = dateKey(d), until = dateKey(DateTime(d.year, d.month + 1));
    final index = ledgerIndex(ledger);
    final source = filter.chips.isNotEmpty ? queryRows(p) : null;
    final key = '${p.id}/$from/$until/${jsonEncode(filter.toJson())}';
    if (!identical(index, _headerIndex) ||
        key != _headerKey ||
        !identical(source, _headerSource)) {
      _headerIndex = index;
      _headerKey = key;
      _headerSource = source;
      final rows =
          source ??
          (filter.copy()
                ..start = from
                ..end = until)
              .apply(ledger, index.records, p);
      _headerSums = {};
      final balance = BalanceRule(ledger);
      _headerBalanceActive = balance.active;
      for (final e in rows) {
        final d = e['data'];
        if (d['type'] == 'transfer') continue;
        final v = _headerSums.putIfAbsent(
          d['base_currency'] ?? 'CNY',
          () => [0, 0, 0],
        );
        v[cashFlowType(d) == 'income' ? 1 : 0] += cashFlowAmount(d);
        v[2] += balance.contribution(e);
      }
    }
    final sums = _headerSums;
    if (sums.isEmpty) {
      sums[settingsOf(ledger)['base_currency'] ?? 'CNY'] = [0, 0, 0];
    }
    final pPalette = AppPalette.of(context);
    final isCute = pPalette.style.isCute;
    final headerContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InkWell(
              key: const ValueKey('flow-month'),
              borderRadius: BorderRadius.circular(999),
              onTap: pickMonth,
              child: Container(
                constraints: const BoxConstraints(minHeight: 26),
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isCute ? pPalette.heroBadgeBg : pPalette.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      calendar ? month : visiblePeriod.substring(0, 7),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularFigures,
                        color: isCute
                            ? pPalette.heroBadgeInk
                            : pPalette.brandColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      CupertinoIcons.chevron_down,
                      size: 10,
                      color: isCute
                          ? pPalette.heroBadgeInk
                          : pPalette.brandColor,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            pill(
              '筛选',
              icon: CupertinoIcons.slider_horizontal_3,
              active: filter.chips.isNotEmpty,
            ),
            const Spacer(),
            IconButton(
              tooltip: '搜索流水',
              onPressed: openSearch,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
              ),
              icon: Icon(
                CupertinoIcons.search,
                size: 16.5,
                color: isCute ? pPalette.heroSubInk : pPalette.ink2,
              ),
            ),
            moreMenu(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 4, right: 6),
          child: Divider(
            height: 1,
            color: isCute ? pPalette.heroBorder : pPalette.border,
          ),
        ),
        for (final e in sums.entries)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '支出',
                        style: TextStyle(
                          fontSize: 10,
                          color: isCute ? pPalette.heroSubInk : pPalette.ink3,
                        ),
                      ),
                      const SizedBox(height: 1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: MarkerHighlight(
                          height: 7,
                          bottom: 1,
                          child: Text(
                            formatAmount(e.value[0], e.key),
                            style: TextStyle(
                              color: isCute
                                  ? pPalette.heroInk
                                  : pPalette.brandColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: -0.4,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '收入',
                        style: TextStyle(
                          fontSize: 10,
                          color: isCute ? pPalette.heroSubInk : pPalette.ink3,
                        ),
                      ),
                      const SizedBox(height: 1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatAmount(e.value[1], e.key),
                          style: TextStyle(
                            color: pPalette.income,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: -0.4,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (s.state['showBalance'] != false) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _headerBalanceActive ? '结余·排除后' : '结余',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: isCute ? pPalette.heroSubInk : pPalette.ink3,
                          ),
                        ),
                        const SizedBox(height: 1),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            formatAmount(e.value[2], e.key),
                            style: TextStyle(
                              color: isCute ? pPalette.heroInk : pPalette.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                              letterSpacing: -0.4,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      color: isCute
          ? pPalette.canvas.withValues(alpha: 0.94)
          : pPalette.canvas,
      child: isCute
          ? Container(
              padding: const EdgeInsets.fromLTRB(11, 4, 6, 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: pPalette.heroGradient,
                ),
                borderRadius: BorderRadius.circular(
                  isAndroidPlatform ? 20 : 18,
                ),
                border: Border.all(color: pPalette.heroBorder, width: 0.9),
                boxShadow: [
                  BoxShadow(
                    color: pPalette.brandColor.withValues(
                      alpha: pPalette.isDark ? 0.22 : 0.10,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: headerContent,
            )
          : GlassPanel(
              radius: isAndroidPlatform ? 20 : 18,
              padding: const EdgeInsets.fromLTRB(11, 4, 6, 6),
              child: headerContent,
            ),
    );
  }

  Widget moreMenu() => TapRegion(
    groupId: moreController,
    onTapOutside: (_) => closeMore(),
    child: CompositedTransformTarget(
      link: moreLink,
      child: OverlayPortal(
        controller: moreController,
        overlayChildBuilder: (context) => Positioned(
          width: 220,
          child: CompositedTransformFollower(
            link: moreLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: TapRegion(
              groupId: moreController,
              onTapOutside: (_) => closeMore(),
              child: Material(
                elevation: 5,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    moreItem('筛选', filters),
                    moreItem('切换年月', pickMonth),
                    for (final view in [
                      ('list', '列表'),
                      ('calendar', '日历'),
                      ('month', '按月'),
                    ])
                      moreItem(
                        view.$2,
                        () => changeView(view.$1),
                        selected:
                            view.$1 ==
                            (calendar
                                ? 'calendar'
                                : monthly
                                ? 'month'
                                : 'list'),
                      ),
                    moreItem(
                      balanceMode ? '切换为收支' : '切换为结余',
                      () => setState(() {
                        s.state['transactionDimension'] = balanceMode
                            ? 'expense'
                            : 'balance';
                        saveFilter();
                      }),
                    ),
                    moreItem('批量操作', openBatch),
                    moreItem('导出流水', openExport),
                  ],
                ),
              ),
            ),
          ),
        ),
        child: IconButton(
          tooltip: '更多功能',
          onPressed: moreController.toggle,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            minimumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(Icons.more_horiz, size: 19, color: secondaryInk(context)),
        ),
      ),
    ),
  );

  Widget moreItem(String title, VoidCallback action, {bool selected = false}) =>
      ListTile(
        dense: true,
        title: Text(title),
        trailing: selected ? const Icon(Icons.check, size: 16) : null,
        onTap: () {
          closeMore();
          action();
        },
      );

  List<Json>? _groupRows;
  bool _groupMonthMode = false, _groupBalanceMode = false;
  Map<String, List<Json>> _groups = {};
  Map<String, (int, int)> _groupTotals = {};
  Map<String, int> _groupDisplayed = {};
  Map<String, Map<String, int>> _dayNet = {};
  int _groupMaximum = 1;
  String _groupLayoutKey = '';
  List<Object> _groupItems = [];

  Widget dayBalance(
    BuildContext c,
    int amount,
    String currency, {
    bool showCurrency = false,
  }) => Text(
    '结余 ${showCurrency ? '$currency ' : ''}${formatAmount(amount, currency)}',
    style: TextStyle(
      fontSize: 10,
      color: amount < 0 ? Theme.of(c).colorScheme.error : secondaryInk(c),
    ),
  );

  Widget lazyRows(List<Json> rows) {
    final monthMode = monthly && !calendar;
    if (!identical(rows, _groupRows) ||
        monthMode != _groupMonthMode ||
        balanceMode != _groupBalanceMode) {
      _groupRows = rows;
      _groupMonthMode = monthMode;
      _groupBalanceMode = balanceMode;
      _groups = {};
      for (final e in rows) {
        final date = e['data']['date'] as String;
        final key = monthMode ? '${date.substring(0, 7)}-01' : date;
        (_groups[key] ??= []).add(e);
      }
      _groupTotals = {
        for (final group in _groups.entries)
          group.key: (sum(group.value, 'income'), sum(group.value, 'expense')),
      };
      final rule = BalanceRule(ledger);
      _groupDisplayed = {
        for (final group in _groups.entries)
          group.key: balanceMode
              ? rule.total(group.value)
              : _groupTotals[group.key]!.$2,
      };
      _dayNet = {};
      if (!monthMode && !balanceMode) {
        for (final group in _groups.entries) {
          final (income, expense) = _groupTotals[group.key]!;
          if (income <= 0 || expense <= 0) continue;
          final amounts = <String, int>{};
          for (final row in group.value) {
            final data = row['data'] as Json;
            if (data['type'] == 'transfer') continue;
            final currency = (data['base_currency'] ?? s.currency) as String;
            amounts.update(
              currency,
              (n) => n + rule.contribution(row),
              ifAbsent: () => rule.contribution(row),
            );
          }
          _dayNet[group.key] = amounts;
        }
      }
      _groupMaximum = _groupDisplayed.values.fold(
        1,
        (n, value) => math.max(n, value.abs()),
      );
      _groupLayoutKey = '';
    }
    final groups = _groups, totals = _groupTotals, maximum = _groupMaximum;
    final layoutKey =
        '$monthMode/$calendar/${foldedDays.join(',')}/${openMonths.join(',')}/${jsonEncode(groupLimits)}';
    if (layoutKey != _groupLayoutKey) {
      final items = <Object>[];
      String? year;
      for (final group in groups.entries) {
        if (monthMode && year != group.key.substring(0, 4)) {
          year = group.key.substring(0, 4);
          items.add(int.parse(year));
        }
        items.add(group);
        if (calendar ||
            (monthMode
                ? openMonths.contains(group.key)
                : !foldedDays.contains(group.key))) {
          final limit = groupLimits[group.key] ?? 100;
          items.addAll(group.value.take(limit));
          if (group.value.length > limit) items.add(group.key);
        }
      }
      _groupItems = items;
      _groupLayoutKey = layoutKey;
    }
    final items = _groupItems;
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (c, i) {
        final item = items[i];
        if (item is int) {
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(
              '$item 年',
              style: TextStyle(fontSize: 12, color: secondaryInk(c)),
            ),
          );
        }
        if (item is String) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(
                () => groupLimits[item] = (groupLimits[item] ?? 100) + 100,
              );
            }
          });
          return const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (item is Json) {
          return KeyedSubtree(
            key: anchors.putIfAbsent(
              '${item['data']['date']}/${item['id']}',
              () => GlobalKey(),
            ),
            child: recordSurface(
              widget.tile(item),
              first: i == 0 || items[i - 1] is! Json,
              last: i == items.length - 1 || items[i + 1] is! Json,
            ),
          );
        }
        final group = item as MapEntry<String, List<Json>>;
        final open =
            calendar ||
            (monthMode
                ? openMonths.contains(group.key)
                : !foldedDays.contains(group.key));
        if (monthMode) {
          final value = _groupDisplayed[group.key]!;
          return InkWell(
            key: anchors.putIfAbsent('${group.key}/group', () => GlobalKey()),
            onTap: () => setState(() {
              if (!openMonths.add(group.key)) openMonths.remove(group.key);
              saveFilter();
            }),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${int.parse(group.key.substring(5, 7))}月',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: balanceMode
                        ? _BalanceBar(
                            value: mixed ? 0 : value,
                            maximum: maximum,
                          )
                        : LinearProgressIndicator(
                            value: mixed ? 0 : value.abs() / maximum,
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(2),
                            color: value < 0
                                ? Theme.of(c).colorScheme.error
                                : expenseInk(c),
                            backgroundColor: hairline(c),
                          ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: Text(
                      mixed
                          ? '${group.value.length} 笔'
                          : '${balanceMode && value > 0 ? '+' : ''}${s.display(value)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: value < 0
                            ? Theme.of(c).colorScheme.error
                            : expenseInk(c),
                      ),
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 17),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            InkWell(
              key: anchors.putIfAbsent('${group.key}/group', () => GlobalKey()),
              onTap: calendar
                  ? null
                  : () => setState(() {
                      final target = monthMode ? openMonths : foldedDays;
                      if (!target.add(group.key)) target.remove(group.key);
                      saveFilter();
                    }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 3),
                child: Row(
                  children: [
                    if (AppPalette.of(c).style.isCute) ...[
                      ThemeMotifIcon(style: AppPalette.of(c).style, size: 11),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        monthMode
                            ? '${group.key.substring(0, 7)} · ${group.key.substring(5)}–${s.period(group.key, ledger: ledger).last.substring(5)}'
                            : dayLabel(group.key),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Flexible(
                      flex: 2,
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 2,
                        alignment: WrapAlignment.end,
                        children: [
                          if (mixed)
                            Text(
                              '${group.value.length} 笔',
                              style: const TextStyle(fontSize: 10.5),
                            )
                          else if (balanceMode)
                            dayBalance(
                              c,
                              _groupDisplayed[group.key]!,
                              s.currency,
                            )
                          else ...[
                            if (totals[group.key]!.$1 != 0)
                              Text(
                                '收 ${s.display(totals[group.key]!.$1)}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontFeatures: tabularFigures,
                                  color: incomeInk(c),
                                ),
                              ),
                            Text(
                              '支 ${s.display(totals[group.key]!.$2)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFeatures: tabularFigures,
                                color: expenseInk(c),
                              ),
                            ),
                          ],
                          for (final amount
                              in (_dayNet[group.key] ?? const <String, int>{})
                                  .entries)
                            dayBalance(
                              c,
                              amount.value,
                              amount.key,
                              showCurrency: mixed,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 15,
                      color: mutedInk(c),
                    ),
                  ],
                ),
              ),
            ),
            if (!monthMode && !calendar)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 5),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: mixed
                        ? 0
                        : _groupDisplayed[group.key]!.abs() / maximum,
                    minHeight: 2.5,
                    backgroundColor: hairline(c),
                    color:
                        (_groupDisplayed[group.key]! < 0
                                ? incomeInk(context)
                                : expenseInk(context))
                            .withValues(alpha: 0.72),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget metric(String title, int value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(fontSize: 10, color: secondaryInk(context))),
      const SizedBox(height: 5),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          mixed ? '分币种查看' : '${moneySymbol(s.currency)} ${s.display(value)}',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            letterSpacing: -.7,
            color: color,
          ),
        ),
      ),
    ],
  );
  String dayLabel(String key) => flowDayLabel(key);

  Widget recordSurface(Widget child, {bool first = true, bool last = true}) {
    final p = AppPalette.of(context);
    final r = isAndroidPlatform ? 20.0 : 18.0;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        border: Border(
          left: BorderSide(color: p.border, width: 0.8),
          right: BorderSide(color: p.border, width: 0.8),
          top: first ? BorderSide(color: p.border, width: 0.8) : BorderSide.none,
          bottom: last
              ? BorderSide(color: p.border, width: 0.8)
              : BorderSide.none,
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(first ? r : 0),
          bottom: Radius.circular(last ? r : 0),
        ),
      ),
      child: child,
    );
  }
  Widget dayGroup(String key, List<Json> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      children: [
        InkWell(
          onTap: () => setState(() {
            if (!foldedDays.add(key)) foldedDays.remove(key);
            saveFilter();
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    dayLabel(key),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${rows.length} 笔 · 支 ${s.display(sum(rows, 'expense'))}${sum(rows, 'income') != 0 ? ' · 收 ${s.display(sum(rows, 'income'))}' : ''}',
                  style: TextStyle(fontSize: 9, color: secondaryInk(context)),
                ),
                const SizedBox(width: 4),
                Icon(
                  foldedDays.contains(key)
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_up,
                  size: 10,
                ),
              ],
            ),
          ),
        ),
        if (!foldedDays.contains(key))
          recordSurface(Column(children: rows.map(widget.tile).toList())),
      ],
    ),
  );
  Widget grouped(List<Json> rows) {
    final groups = <String, List<Json>>{};
    for (final e in rows) {
      final k = (e['data']['date'] as String).substring(0, monthly ? 7 : 10);
      (groups[k] ??= []).add(e);
    }
    if (!monthly) {
      return Column(
        children: groups.entries.map((e) => dayGroup(e.key, e.value)).toList(),
      );
    }
    return Column(
      children: [
        for (final group in groups.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassPanel(
              radius: 21,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  InkWell(
                    onTap: () => setState(() {
                      if (!openMonths.add(group.key)) {
                        openMonths.remove(group.key);
                      }
                      saveFilter();
                    }),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              '${int.parse(group.key.substring(5))}',
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '月 · ${group.key.substring(0, 4)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: secondaryInk(context),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${group.value.length} 笔',
                              style: TextStyle(
                                fontSize: 10,
                                color: secondaryInk(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              openMonths.contains(group.key)
                                  ? CupertinoIcons.chevron_up
                                  : CupertinoIcons.chevron_down,
                              size: 12,
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            Expanded(
                              child: metric(
                                '支出',
                                sum(group.value, 'expense'),
                                expenseInk(context),
                              ),
                            ),
                            Expanded(
                              child: metric(
                                '收入',
                                sum(group.value, 'income'),
                                incomeInk(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: hairline(context)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            hint('结余'),
                            const Spacer(),
                            Text(
                              s.display(BalanceRule(ledger).total(group.value)),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (openMonths.contains(group.key)) ...monthDays(group.value),
                ],
              ),
            ),
          ),
        hint('仅统计筛选区间内的记录，点击月份展开每日明细。'),
      ],
    );
  }

  List<Widget> monthDays(List<Json> rows) {
    final days = <String, List<Json>>{};
    for (final e in rows) {
      (days[e['data']['date']] ??= []).add(e);
    }
    return days.entries.map((e) => dayGroup(e.key, e.value)).toList();
  }

  void move(int delta) {
    final d = DateTime.parse('$month-01');
    setState(() {
      month = dateKey(DateTime(d.year, d.month + delta)).substring(0, 7);
      selected = '$month-01';
      visiblePeriod = '${selected.substring(0, 7)}-01';
      saveFilter();
    });
    widget.onVisiblePeriod?.call(visiblePeriod);
  }

  Future<void> selectDay(String key) async {
    if (filter.start.isNotEmpty &&
        (key.compareTo(filter.start) < 0 || key.compareTo(filter.end) >= 0)) {
      message(context, '该日期不在筛选范围');
      return;
    }
    setState(() {
      selected = key;
      month = key.substring(0, 7);
      visiblePeriod = '${key.substring(0, 7)}-01';
      saveFilter();
    });
    widget.onVisiblePeriod?.call(visiblePeriod);
  }

  bool trackScroll(ScrollNotification n) {
    if (n is ScrollStartNotification) closeMore();
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (widget.temporary) return false;
    if (n is ScrollEndNotification || n is ScrollUpdateNotification) {
      if (!calendar && filter.chips.isEmpty) {
        final top = context.findRenderObject() as RenderBox?;
        final candidates = <MapEntry<String, double>>[];
        anchors.removeWhere((k, v) => v.currentContext == null);
        for (final a in anchors.entries) {
          final box = a.value.currentContext?.findRenderObject() as RenderBox?;
          if (box != null &&
              box.attached &&
              box.hasSize &&
              top != null &&
              top.attached) {
            RenderObject? ancestor = box;
            while (ancestor != null && !identical(ancestor, top)) {
              ancestor = ancestor.parent;
            }
            if (ancestor == null) continue;
            final y = box.localToGlobal(Offset.zero, ancestor: top).dy;
            if (y + box.size.height > 0) {
              candidates.add(MapEntry(a.key.substring(0, 10), y));
            }
          }
        }
        candidates.sort((a, b) => a.value.compareTo(b.value));
        if (candidates.isNotEmpty) {
          final next = '${candidates.first.key.substring(0, 7)}-01';
          if (next != visiblePeriod) {
            visiblePeriod = next;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {});
                widget.onVisiblePeriod?.call(next);
              }
            });
          }
        }
      }
      if (n is ScrollEndNotification) saveFilter();
    }
    return false;
  }

  Widget calendarGrid(List<Json> rows, BookPeriod p) {
    final netByDay = <String, int>{};
    final balance = BalanceRule(ledger);
    for (final e in rows) {
      final d = e['data'];
      if (d['type'] == 'transfer') continue;
      final date = d['date'] as String;
      netByDay[date] = (netByDay[date] ?? 0) + balance.contribution(e);
    }

    final first = DateTime.parse('$month-01'),
        week = (s.state['weekStart'] as int?) ?? 0,
        offset = (first.weekday % 7 - week + 7) % 7,
        days = DateTime(first.year, first.month + 1, 0).day,
        cells =
            ((offset + DateTime(first.year, first.month + 1, 0).day) / 7)
                .ceil() *
            7,
        scheme = Theme.of(context).colorScheme;
    final labels = week == 0
        ? ['日', '一', '二', '三', '四', '五', '六']
        : ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      children: [
        Row(
          children: labels
              .map((v) => Expanded(child: Center(child: hint(v))))
              .toList(),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: math.max(
              60,
              26 + MediaQuery.textScalerOf(context).scale(34),
            ),
            crossAxisSpacing: 3,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (c, index) {
            final number = index - offset + 1;
            if (number < 1 || number > days) return const SizedBox.shrink();
            final date = DateTime(first.year, first.month, number),
                key = dateKey(date),
                daily = rows
                    .where((e) => e['data']['date'] == dateKey(date))
                    .toList(),
                chosen = key == selected;
            final expense = sum(daily, 'expense'),
                income = sum(daily, 'income'),
                inRange =
                    key.compareTo(
                          filter.start.isEmpty ? '$month-01' : filter.start,
                        ) >=
                        0 &&
                    key.compareTo(
                          filter.end.isEmpty
                              ? dateKey(DateTime(first.year, first.month + 1))
                              : filter.end,
                        ) <
                        0;
            return Semantics(
              button: true,
              selected: chosen,
              label:
                  '$key ${key == today() ? '今天' : ''} 支出 ${s.display(expense)} 收入 ${s.display(income)}${inRange ? '' : ' 不在筛选范围'}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => selectDay(key),
                child: Column(
                  children: [
                    BudgetPool(
                      spent: s.view['id'] == s.active['id']
                          ? (budgetQuery(s.active, s.period(key)).days[key] ??
                                0)
                          : expense,
                      limit: s.view['id'] == s.active['id']
                          ? (s.dailyBudgets(key)[key] ?? 0)
                          : 0,
                      selected: chosen,
                      child: Container(
                        height: 26,
                        width: 28,
                        alignment: Alignment.center,
                        child: Text(
                          '${date.day}${key == today() ? '•' : ''}',
                          style: TextStyle(
                            fontWeight: chosen
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: chosen
                                ? scheme.onSurface
                                : inRange
                                ? scheme.onSurface
                                : scheme.outline,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (balanceMode && !mixed)
                      FittedBox(
                        child: Text(
                          s.display(balance.total(daily)),
                          style: TextStyle(
                            fontSize: 10,
                            color: balance.total(daily) < 0
                                ? scheme.error
                                : scheme.primary,
                          ),
                        ),
                      ),
                    if (!balanceMode && expense != 0)
                      FittedBox(
                        child: Text(
                          mixed ? '${daily.length} 笔' : compact(expense),
                          style: TextStyle(
                            fontSize: 10,
                            height: 1,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    if (!balanceMode && income > 0 && !mixed)
                      FittedBox(
                        child: Text(
                          compact(income),
                          style: TextStyle(
                            fontSize: 10,
                            height: 1,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFFFFBF96)
                                : const Color(0xFF96501D),
                          ),
                        ),
                      ),
                    if (daily.any((e) => e['data']['type'] == 'transfer'))
                      const Icon(Icons.swap_horiz, size: 10),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class FilterPage extends StatefulWidget {
  final LedgerStore s;
  final EntryFilter original;
  final BookPeriod period;
  final Json? ledger;
  const FilterPage(
    this.s,
    this.original,
    this.period, {
    super.key,
    this.ledger,
  });
  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  late EntryFilter f;
  late TextEditingController min, max, query;
  LedgerStore get s => widget.s;
  Json get ledger => widget.ledger ?? s.active;
  List<Json> choices(String kind, {bool archived = true}) =>
      dictionary(ledger, kind, archived: archived);
  String get amountCurrency => f.originalAmount && f.currencies.length == 1
      ? f.currencies.single
      : s.currency;
  @override
  void initState() {
    super.initState();
    f = widget.original.copy();
    min = TextEditingController(
      text: f.min == null ? '' : formatAmount(f.min!, amountCurrency),
    );
    max = TextEditingController(
      text: f.max == null ? '' : formatAmount(f.max!, amountCurrency),
    );
    query = TextEditingController(text: f.keyword);
  }

  @override
  void dispose() {
    min.dispose();
    max.dispose();
    query.dispose();
    super.dispose();
  }

  Widget chips(String title, Map<String, String> values, Set<String> selected) {
    final exclude = title.startsWith('排除');
    final all = !exclude && !f.restricted.contains(title) && selected.isEmpty;
    if (title == '分类' || title == '排除分类' || title == '标签' || title == '排除标签') {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(
          all
              ? '全部'
              : selected.isEmpty
              ? (exclude ? '不排除' : '未选择')
              : '已选择 ${selected.length} 项',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final draft = all ? values.keys.toSet() : {...selected};
          final result = await glassSheet<Set<String>>(
            context,
            FilterTreePicker(
              title: title,
              labels: values,
              categories: title.contains('分类')
                  ? choices('category', archived: true)
                  : [],
              selected: draft,
            ),
          );
          if (result != null) {
            setState(() {
              selected
                ..clear()
                ..addAll(result);
              if (!exclude) {
                f.restricted.add(title);
                if (result.containsAll(values.keys)) {
                  selected.clear();
                  f.restricted.remove(title);
                }
              }
            });
          }
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (exclude) {
                  selected.clear();
                } else {
                  final full = all || selected.containsAll(values.keys);
                  selected.clear();
                  if (full) {
                    f.restricted.add(title);
                  } else {
                    f.restricted.remove(title);
                  }
                }
              }),
              child: Text(
                exclude
                    ? '清空'
                    : (all || selected.containsAll(values.keys))
                    ? '取消全选'
                    : '全选',
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: values.entries
              .map(
                (e) => FilterChip(
                  label: Text(e.value),
                  selected: all || selected.contains(e.key),
                  onSelected: (v) => setState(() {
                    if (all) selected.addAll(values.keys);
                    if (!exclude) f.restricted.add(title);
                    v ? selected.add(e.key) : selected.remove(e.key);
                    if (title == '分类' || title == '排除分类') {
                      final children = choices('category', archived: true)
                          .where((c) => c['data']['parent_id'] == e.key)
                          .map((c) => c['id'] as String);
                      if (v) {
                        selected.addAll(children);
                      } else {
                        selected.removeAll(children);
                        for (final c in choices(
                          'category',
                          archived: true,
                        ).where((c) => c['id'] == e.key)) {
                          selected.remove(c['data']['parent_id']);
                        }
                      }
                    }
                    if (title == '币种') {
                      f.originalAmount = false;
                      min.clear();
                      max.clear();
                    }
                  }),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void apply() {
    try {
      f.min = min.text.isEmpty
          ? null
          : parseAmount(min.text, amountCurrency, zero: true);
      f.max = max.text.isEmpty
          ? null
          : parseAmount(max.text, amountCurrency, zero: true);
      if (f.min != null && f.max != null && f.min! > f.max!) {
        throw const FormatException('最低金额不能大于最高金额');
      }
      if (f.originalAmount && f.currencies.length != 1) {
        throw const FormatException('原币金额筛选必须选择一个币种');
      }
      f.keyword = query.text.trim();
      Navigator.pop(context, f);
    } catch (e) {
      message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('组合筛选'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            f = EntryFilter();
            min.clear();
            max.clear();
            query.clear();
          }),
          child: const Text('重置'),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(onPressed: apply, child: const Text('应用筛选')),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Text(
          '时间：${f.start.isEmpty ? widget.period.label : '${f.start} 至 ${dateKey(DateTime.parse(f.end).subtract(const Duration(days: 1)))}'}',
        ),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('快速年月'),
              onPressed: () async {
                final selected = await chooseMonth(
                  context,
                  f.start.isEmpty ? widget.period.start : f.start,
                );
                if (selected != null) {
                  final p = s.period(selected);
                  setState(() {
                    f.start = p.start;
                    f.end = p.end;
                  });
                }
              },
            ),
            ActionChip(
              label: const Text('自定义日期'),
              onPressed: () async {
                final d = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDateRange: DateTimeRange(
                    start: DateTime.parse(
                      f.start.isEmpty ? widget.period.start : f.start,
                    ),
                    end: DateTime.parse(
                      f.end.isEmpty ? widget.period.end : f.end,
                    ).subtract(const Duration(days: 1)),
                  ),
                );
                if (d != null) {
                  setState(() {
                    f.start = dateKey(d.start);
                    f.end = dateKey(d.end.add(const Duration(days: 1)));
                  });
                }
              },
            ),
          ],
        ),
        space,
        TextField(
          controller: query,
          decoration: const InputDecoration(labelText: '关键词'),
        ),
        space,
        chips('类型', {
          'expense': '支出',
          'income': '收入',
          'transfer': '转账',
        }, f.types),
        chips('分类', {
          for (final e in choices('category', archived: true))
            e['id']:
                '${e['data']['type'] == 'income' ? '收 · ' : ''}${e['data']['name']}${e['data']['archived'] == true ? '（停用）' : ''}',
        }, f.categories),
        chips('排除分类', {
          for (final c in choices('category', archived: true))
            c['id']: c['data']['name'],
        }, f.excludedCategories),
        chips('标签', {
          for (final e in choices('tag', archived: true))
            e['id']: e['data']['name'],
        }, f.tags),
        if (choices('tag', archived: true).isNotEmpty) ...[
          chips('排除标签', {
            for (final t in choices('tag', archived: true))
              t['id']: t['data']['name'],
          }, f.excludedTags),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('必须包含全部所选标签'),
            value: f.allTags,
            onChanged: (v) => setState(() => f.allTags = v),
          ),
          space,
        ],
        chips('账户', {
          for (final a in {
            ...accounts,
            ...s.records(ledger).map((e) => e['data']['account'] as String),
            ...s
                .records(ledger)
                .where((e) => e['data']['type'] == 'transfer')
                .map((e) => e['data']['to_account'] as String),
          })
            a: a,
        }, f.accounts),
        DropdownButtonFormField<String>(
          initialValue: f.accountSide,
          decoration: const InputDecoration(labelText: '转账账户匹配'),
          items: const [
            DropdownMenuItem(value: 'any', child: Text('任一端')),
            DropdownMenuItem(value: 'from', child: Text('仅转出')),
            DropdownMenuItem(value: 'to', child: Text('仅转入')),
          ],
          onChanged: (v) => setState(() => f.accountSide = v!),
        ),
        space,
        chips('成员', {
          for (final e in s.records(ledger))
            (e['data']['member'] as String? ?? '').isEmpty
                    ? e['author'] ?? ''
                    : 'label:${e['data']['member']}':
                (e['data']['member'] as String? ?? '').isEmpty
                ? e['author_name'] ?? '我'
                : e['data']['member'],
        }, f.members),
        chips('币种', {for (final c in currencies.keys) c: c}, f.currencies),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('按原币金额筛选（默认 ${s.currency}）'),
          subtitle: const Text('限单一原币；切换单位清空金额范围'),
          value: f.originalAmount,
          onChanged: (v) => setState(() {
            f.originalAmount = v;
            min.clear();
            max.clear();
          }),
        ),
        TextField(
          controller: min,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: '最低金额（$amountCurrency）'),
        ),
        space,
        TextField(
          controller: max,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: '最高金额（$amountCurrency）'),
        ),
        space,
        DropdownButtonFormField<String>(
          initialValue: f.sort,
          decoration: const InputDecoration(labelText: '排序'),
          items: const [
            DropdownMenuItem(value: 'date_desc', child: Text('日期从新到旧')),
            DropdownMenuItem(value: 'date_asc', child: Text('日期从旧到新')),
            DropdownMenuItem(value: 'amount_desc', child: Text('折合金额从高到低')),
            DropdownMenuItem(value: 'amount_asc', child: Text('折合金额从低到高')),
          ],
          onChanged: (v) => setState(() => f.sort = v!),
        ),
        space,
      ],
    ),
  );
}

class _BalanceBar extends StatelessWidget {
  final int value, maximum;
  const _BalanceBar({required this.value, required this.maximum});
  @override
  Widget build(BuildContext c) => SizedBox(
    height: 12,
    child: LayoutBuilder(
      builder: (c, constraints) {
        final half = constraints.maxWidth / 2,
            length = half * (value.abs() / maximum).clamp(0, 1);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(height: 3, color: hairline(c)),
            Positioned(
              left: value < 0 ? half - length : half,
              width: length,
              height: 3,
              child: ColoredBox(
                color: value < 0
                    ? Theme.of(c).colorScheme.error
                    : expenseInk(c),
              ),
            ),
            Container(width: 1, height: 10, color: secondaryInk(c)),
          ],
        );
      },
    ),
  );
}
