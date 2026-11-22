import 'belongings_page.dart';
import 'reminders.dart';
import 'templates_page.dart';
import 'recurring_page.dart';
import 'reminders_page.dart';
import 'utility_pages.dart';
import 'help_page.dart';
import 'icon_catalog.dart';
import 'data_pages.dart';

import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart'
    show listEquals, LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'update_page.dart';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'store.dart';
import 'ui.dart';
import 'record_page.dart';
import 'preferences_page.dart';
import 'transactions.dart';
import 'statistics_page.dart';
import 'ledger_picker.dart';
import 'budget_page.dart';
import 'detail_page.dart';
import 'merge_page.dart';
export 'record_page.dart';

const teal = Color(0xFF126C62),
    ink = Color(0xFF24333B),
    mint = Color(0xFFE1F2EA),
    canvas = Color(0xFFF1F4F5),
    amber = Color(0xFFBD672D);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Microsoft Fluent UI Emoji',
    ], await rootBundle.loadString('assets/belongings/LICENSE-Microsoft.txt'));
  });
  runApp(const YoushuBootstrap());
}

class YoushuBootstrap extends StatefulWidget {
  final LedgerStore? store;
  const YoushuBootstrap({super.key, this.store});
  @override
  State<YoushuBootstrap> createState() => _YoushuBootstrapState();
}

class _YoushuBootstrapState extends State<YoushuBootstrap> {
  late final LedgerStore store = widget.store ?? LedgerStore();
  Timer? progressTimer;
  Json preferences = {};
  bool loading = false, ready = false, showProgress = false, failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }

  Future<void> open() async {
    if (loading) return;
    setState(() {
      loading = true;
      failed = false;
      showProgress = false;
    });
    progressTimer?.cancel();
    progressTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !ready) setState(() => showProgress = true);
    });
    try {
      if (Platform.isAndroid) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      await store.initialize(
        onPreferencesLoaded: (value) {
          if (mounted) setState(() => preferences = value);
        },
      );
      progressTimer?.cancel();
      if (!mounted) return;
      setState(() => ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await AppReminders.instance.start(store);
          if (mounted && store.state['notificationPermissionAsked'] != true) {
            await AppReminders.instance.requestPermission();
            store.state['notificationPermissionAsked'] = true;
            await store.persist(preferencesOnly: true);
          }
        } catch (_) {
          AppReminders.instance.error = '提醒初始化失败，请在提醒设置中重试';
        }
      });
    } catch (_) {
      progressTimer?.cancel();
      if (mounted) setState(() => failed = true);
    } finally {
      loading = false;
    }
  }

  @override
  void dispose() {
    progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ready) return YoushuApp(store);
    final style = appThemeStyleOf(preferences['themeStyle']);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      theme: appTheme(Brightness.light, style: style),
      darkTheme: appTheme(Brightness.dark, style: style),
      themeMode: _themeMode(preferences['theme']),
      home: Builder(
        builder: (context) {
          final logo = ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/brand/launch.png',
              width: 72,
              height: 72,
            ),
          );
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: failed
                ? Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            logo,
                            const SizedBox(height: 24),
                            const Text(
                              '无法打开本地账本，请检查设备存储后重试。\n请勿卸载 App，以免丢失本地数据。',
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: open,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, size) => Stack(
                      children: [
                        Center(child: logo),
                        if (showProgress)
                          Positioned(
                            top: size.maxHeight / 2 + 56,
                            left: 24,
                            right: 24,
                            child: const Column(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text('正在打开账本'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

ThemeMode _themeMode(Object? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

class YoushuApp extends StatefulWidget {
  final LedgerStore store;
  const YoushuApp(this.store, {super.key});
  @override
  State<YoushuApp> createState() => _YoushuAppState();
}

class _YoushuAppState extends State<YoushuApp> {
  LedgerStore get store => widget.store;
  late (Object?, Object?, double, bool) appearance;
  Object? iconRevision;
  List<Object?> iconSources = [];
  (Object?, Object?, double, bool) get currentAppearance => (
    store.state['theme'],
    store.state['themeStyle'],
    store.fontScale,
    store.state['followSystemFont'] == true,
  );

  void syncIcons() {
    final sources = store.ledgers.map((l) => l['custom_icons']).toList();
    if (iconRevision != store.state['dataRevision'] ||
        !listEquals(sources, iconSources)) {
      IconCatalog.sync(store.ledgers);
      iconRevision = store.state['dataRevision'];
      iconSources = sources;
    }
  }

  void changed() {
    syncIcons();
    if (appearance != currentAppearance) {
      setState(() => appearance = currentAppearance);
    }
  }

  @override
  void initState() {
    super.initState();
    appearance = currentAppearance;
    syncIcons();
    store.addListener(changed);
  }

  @override
  void didUpdateWidget(YoushuApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != store) {
      oldWidget.store.removeListener(changed);
      store.addListener(changed);
      appearance = currentAppearance;
      iconSources = [];
      syncIcons();
    }
  }

  @override
  void dispose() {
    store.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = appThemeStyleOf(store.state['themeStyle']);
    return MaterialApp(
      title: '有数',
      debugShowCheckedModeBanner: false,
      locale: Locale('zh', 'CN'),
      supportedLocales: [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: appTheme(Brightness.light, style: style),
      darkTheme: appTheme(Brightness.dark, style: style),
      themeMode: _themeMode(store.state['theme']),
      builder: (context, child) => AppBackdrop(
        child: ValueListenableBuilder<double?>(
          valueListenable: store.fontPreview,
          child: NoticeHost(child: child!),
          builder: (context, preview, child) => AdaptiveDisplay(
            scale: preview ?? store.fontScale,
            followSystem: store.state['followSystemFont'] == true,
            child: child!,
          ),
        ),
      ),
      home: Home(store, key: ObjectKey(store)),
    );
  }
}

IconData categoryIcon(String category) => switch (category) {
  '餐饮' => Icons.restaurant_rounded,
  '交通' => Icons.directions_bus_rounded,
  '购物' => Icons.shopping_bag_rounded,
  '日用' => Icons.local_mall_outlined,
  '居住' => Icons.home_rounded,
  '娱乐' => Icons.sports_esports_rounded,
  '健康' => Icons.favorite_outline,
  '学习' => Icons.menu_book_rounded,
  '旅行' => Icons.flight_rounded,
  '人情' => Icons.redeem_rounded,
  '工资' => Icons.account_balance_wallet_rounded,
  _ => Icons.more_horiz_rounded,
};
Widget card(Widget child, {Color? color}) => color == null
    ? panel(child)
    : Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 16),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: EdgeInsets.all(20), child: child),
        ),
      );
Widget label(String text) => hint(text);
Widget gap([double size = 16]) => SizedBox(height: size);

String transactionSubtitle(
  Json ledger,
  Json entry, {
  String? sourceLedger,
  bool shared = false,
}) {
  final data = entry['data'] as Json;
  final note = (data['note'] as String? ?? '').trim();
  final account = (data['account'] as String? ?? '').trim();
  final selectedTags = (data['tag_ids'] as List? ?? []).toSet();
  final tags = <String>[
    for (final tag in ledgerIndex(ledger).byKind['tag'] ?? <Json>[])
      if (selectedTags.contains(tag['id'])) '#${tag['data']['name']}',
  ];
  return [
    if (sourceLedger != null && sourceLedger.trim().isNotEmpty)
      sourceLedger.trim(),
    if (note.isNotEmpty) note,
    if (account.isNotEmpty && account != '未指定') account,
    if (shared) (entry['author_name'] as String? ?? '我'),
    for (final key in ['member', 'merchant', 'project'])
      if ((data[key] as String? ?? '').trim().isNotEmpty)
        (data[key] as String).trim(),
    if (tags.isNotEmpty) tags.join(' '),
  ].where((value) => value.isNotEmpty).join(' · ');
}

class Home extends StatefulWidget {
  final LedgerStore store;
  const Home(this.store, {super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  LedgerStore get s => widget.store;
  Color get teal => Theme.of(context).colorScheme.primary;
  Color get ink => Theme.of(context).colorScheme.onSurface;
  Color get mint => Theme.of(context).colorScheme.primaryContainer;
  int tab = 1;
  int analysisMode = 0;
  final belongingsKey = GlobalKey<BelongingsPageState>();
  final visited = <int>{1};
  final transactionsKey = GlobalKey<TransactionsState>();
  String month = today();
  @override
  void initState() {
    super.initState();
    tab = (s.state['lastTab'] as int? ?? 1).clamp(1, 4);
    if (s.state['navLayout'] != 2) {
      if (tab == 2) {
        tab = 3;
        s.state['analysisMode'] = 1;
      }
      s.state['navLayout'] = 2;
      s.state['lastTab'] = tab;
    }
    analysisMode = (s.state['analysisMode'] as int? ?? 0).clamp(0, 1);
    visited.add(tab);
    month = s.state['lastTransactionPeriod'] ?? today();
    s.addListener(refresh);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => s.resumeMaintenance().catchError((Object e) {
        if (mounted) toast(e.toString());
      }),
    );
    system.setMethodCallHandler((call) async {
      if (call.method == 'quickAdd') quick(call.arguments?.toString() ?? '');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final route = await system.invokeMethod<String>('initialAction');
        if (route != null && route.isNotEmpty) quick(route);
      } on MissingPluginException {
        /* 非手机测试。 */
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      s.resumeMaintenance().catchError((Object e) {
        if (mounted) toast(e.toString());
      });
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(
        s.flushViewPreferences().catchError((Object e) {
          if (mounted) toast(e.toString());
        }),
      );
      if (state == AppLifecycleState.paused) unawaited(s.flushWidgetRefresh());
      s.backupTimer?.cancel();
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(s.flushViewPreferences().catchError((Object _) {}));
    WidgetsBinding.instance.removeObserver(this);
    s.backupTimer?.cancel();
    s.removeListener(refresh);
    system.setMethodCallHandler(null);
    super.dispose();
  }

  void quick(String route) {
    if (mounted) {
      record(
        category: categories.firstWhere(
          (c) => route.contains(Uri.encodeComponent(c)) || route.contains(c),
          orElse: () => '餐饮',
        ),
      );
    }
  }

  void toast(String value) {
    if (mounted) notifyApp(value);
  }

  Future<void> action(
    Future<void> Function() work, {
    String success = '',
  }) async {
    try {
      await work();
      if (success.isNotEmpty) toast(success);
    } catch (e) {
      toast(e.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<String?> ask(
    String title, {
    String initial = '',
    bool number = false,
  }) async {
    final c = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: number ? 13 : 50,
          keyboardType: number
              ? TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) {
                Navigator.pop(context, c.text.trim());
              }
            },
            child: Text('保存'),
          ),
        ],
      ),
    );
    // 控制器随对话框退出动画后由 GC 释放，不在动画期间 dispose。
    return value;
  }

  Future<bool> confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('继续'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> record({
    String category = '餐饮',
    Json? entry,
    String? date,
    bool copy = false,
  }) async {
    transactionsKey.currentState?.closeMore();
    if (s.busy) {
      toast('正在同步，请稍后记账');
      return;
    }
    if (!s.canEdit) {
      toast('当前账本为只读权限');
      return;
    }
    final outcome = await Navigator.push<String>(
      context,
      AppPageRoute<String>(
        builder: (_) => RecordPage(
          s,
          category: category,
          existing: entry,
          initialDate: date,
          copy: copy,
        ),
      ),
    );
    if (outcome == 'saved' && entry == null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() {
        tab = 1;
        visited.add(1);
        s.state['lastTab'] = 1;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            transactionsKey.currentState?.scroll.hasClients == true) {
          transactionsKey.currentState!.scroll.jumpTo(0);
        }
      });
      s.queueViewPreferences();
      await s.flushViewPreferences();
    }
  }

  Widget templateShortcuts() {
    final multi = s.viewLedgers.length > 1;
    final pinned = multi
        ? <Json>[]
        : s.recordTemplates.where((t) => t['pinned'] == true).take(3).toList();
    final pending = multi ? 0 : s.recurringPending.length;
    if (pinned.isEmpty && pending == 0) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pinned.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in pinned)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      CupertinoIcons.bolt,
                      size: 13,
                      color: p.brandColor,
                    ),
                    label: Text(
                      item['name'],
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onPressed: () => useRecordTemplate(context, s, item),
                  ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '管理',
                    style: TextStyle(fontSize: 11.5, color: p.ink2),
                  ),
                  onPressed: () => openTemplates(context, s),
                ),
              ],
            ),
          if (pending > 0) ...[
            if (pinned.isNotEmpty) const SizedBox(height: 6),
            GlassPanel(
              radius: 14,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                leading: Icon(
                  CupertinoIcons.calendar,
                  size: 17,
                  color: p.brandColor,
                ),
                title: Text(
                  '$pending 笔周期账单待确认',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_right,
                  size: 13,
                  color: p.ink3,
                ),
                onTap: () => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => RecurringHistory(s)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void changeMonth(int delta) {
    final p = s.period(month);
    setState(
      () => month = delta > 0
          ? p.end
          : dateKey(DateTime.parse(p.start).subtract(Duration(days: 1))),
    );
  }

  Widget monthPicker() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(
          '${int.parse(s.period(month).start.substring(5, 7))} 月账期',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 28,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: '上一账期',
            onPressed: () => changeMonth(-1),
            icon: const Icon(CupertinoIcons.chevron_left, size: 12),
          ),
        ),
        SizedBox(
          width: 28,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: '下一账期',
            onPressed: () => changeMonth(1),
            icon: const Icon(CupertinoIcons.chevron_right, size: 12),
          ),
        ),
        const Spacer(),
        Text(
          '${s.period(month).start.substring(5).replaceAll('-', '.')} — ${dateKey(DateTime.parse(s.period(month).end).subtract(const Duration(days: 1))).substring(5).replaceAll('-', '.')}',
          style: TextStyle(fontSize: 10, color: secondaryInk(context)),
        ),
      ],
    ),
  );

  Widget bookPicker() {
    final p = AppPalette.of(context);
    return InkWell(
      onTap: chooseView,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p.style.isCute)
              ThemeMotifIcon(style: p.style, size: 15)
            else
              Icon(CupertinoIcons.book, size: 15, color: p.brandColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                (tab == 1 || (tab == 3 && analysisMode == 0))
                    ? (s.viewLedgers.length > 1
                          ? '${s.viewLedgers.length} 个账本'
                          : s.view['name'])
                    : s.active['name'],
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: p.ink,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down, size: 11, color: p.ink3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      extendBody: true,
      appBar: null,
      body: SafeArea(
        bottom: false,
        child: AbsorbPointer(
          absorbing: s.busy,
          child: IndexedStack(
            index: tab - 1,
            children: [
              visited.contains(1)
                  ? Transactions(
                      s,
                      key: transactionsKey,
                      summary: scopeSummary(),
                      shortcuts: templateShortcuts(),
                      bookPicker: bookPicker(),
                      periodKey: month,
                      onVisiblePeriod: (value) {
                        if (month != value) {
                          setState(() {
                            month = value;
                            s.state['lastTransactionPeriod'] = value;
                          });
                        }
                      },
                      tile: entryTile,
                      add: (d) => record(date: d),
                    )
                  : const SizedBox.shrink(),
              visited.contains(2)
                  ? BelongingsPage(s, key: belongingsKey)
                  : const SizedBox.shrink(),
              visited.contains(3)
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: bookPicker(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          child: AppSegmentControl<int>(
                            expand: true,
                            value: analysisMode,
                            items: const [(0, '统计'), (1, '预算')],
                            itemPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6.5,
                            ),
                            onChanged: (value) => setState(() {
                              analysisMode = value;
                              s.state['analysisMode'] = analysisMode;
                              if (s.database != null) {
                                s.queueViewPreferences(
                                  onError: (e) => toast('$e'),
                                );
                              }
                            }),
                          ),
                        ),
                        Expanded(
                          child: IndexedStack(
                            index: analysisMode,
                            children: [
                              StatisticsPage(s, onDetails: openDetails),
                              BudgetPage(
                                s,
                                periodKey: month,
                                onEdit: editBudget,
                                onPeriod: changeMonth,
                                onDetails: openDetails,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              visited.contains(4)
                  ? SettingsPage(s, embedded: true, onBooks: openBooks)
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              p.canvas,
              p.canvas.withValues(alpha: 0.78),
              p.canvas.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: GlassPanel(
                    blur: true,
                    radius: isAndroidPlatform ? 26 : 32,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        nav(1, CupertinoIcons.list_bullet, '流水'),
                        nav(2, CupertinoIcons.cube_box, '物品'),
                        nav(3, CupertinoIcons.chart_bar, '分析'),
                        nav(4, CupertinoIcons.person, '我的'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: tab == 2 ? '添加物品' : '记一笔',
                  child: Semantics(
                    button: true,
                    label: tab == 2 ? '添加物品' : '记一笔',
                    child: GestureDetector(
                      onTap: () => tab == 2
                          ? belongingsKey.currentState?.addItem()
                          : record(),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: isAndroidPlatform
                              ? BoxShape.rectangle
                              : BoxShape.circle,
                          borderRadius: isAndroidPlatform
                              ? BorderRadius.circular(18)
                              : null,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: p.fabGradient,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: p.brandColor.withValues(
                                alpha: p.isDark ? 0.25 : 0.32,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          CupertinoIcons.plus,
                          size: 23,
                          color: p.fabInk,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget nav(int index, IconData icon, String text) {
    final p = AppPalette.of(context);
    final active = tab == index;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        label: text,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => setState(() {
            transactionsKey.currentState?.closeMore();
            if (tab == index && index == 1) {
              transactionsKey.currentState?.scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              );
            }
            tab = index;
            visited.add(index);
            s.state['lastTab'] = index;
            if (s.database != null) {
              s.queueViewPreferences(
                onError: (Object e) {
                  toast('$e');
                },
              );
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 6.5),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active ? p.brandSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(isAndroidPlatform ? 20 : 24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: active ? p.brandColor : p.ink3),
                const SizedBox(height: 2.5),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: active ? p.brandColor : p.ink3,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget periodSummary() {
    final expense = s.total(month, 'expense'),
        income = s.total(month, 'income'),
        budget = s.budget(month, '全部');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        monthPicker(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本期支出 · ${s.currency == 'CNY' ? '人民币' : s.currency}',
                    style: TextStyle(
                      fontSize: 10,
                      color: secondaryInk(context),
                    ),
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: ink,
                          fontFamily: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.fontFamily,
                        ),
                        children: [
                          TextSpan(
                            text: '${moneySymbol(s.currency)} ',
                            style: const TextStyle(fontSize: 15),
                          ),
                          TextSpan(
                            text: s.display(expense).split('.').first,
                            style: const TextStyle(
                              fontSize: 37,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -1.6,
                            ),
                          ),
                          if (s.display(expense).contains('.'))
                            TextSpan(
                              text: '.${s.display(expense).split('.').last}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -1,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  _smallTotal('收入', income),
                  const SizedBox(height: 7),
                  if (s.state['showBalance'] != false)
                    _smallTotal(
                      '结余',
                      BalanceRule(s.active).total(s.monthRecords(month)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        InkWell(
          onTap: () => setState(() {
            tab = 3;
            analysisMode = 1;
            visited.add(3);
          }),
          borderRadius: BorderRadius.circular(15),
          child: GlassPanel(
            radius: 15,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        budget > 0
                            ? '本期预算剩余 ${moneySymbol(s.currency)} ${s.display(budget - s.budgetSpent(month))}'
                            : '本期预算未设置',
                        style: TextStyle(
                          fontSize: 10,
                          color: expenseInk(context),
                        ),
                      ),
                    ),
                    Text(
                      budget > 0
                          ? '${(s.budgetSpent(month) / budget * 100).round()}%'
                          : '设置',
                      style: TextStyle(
                        fontSize: 10,
                        color: secondaryInk(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: budget > 0
                        ? (s.budgetSpent(month) / budget).clamp(0, 1)
                        : 0,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    color: s.budgetSpent(month) > budget && budget > 0
                        ? incomeInk(context)
                        : expenseInk(context).withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _smallTotal(String title, int value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: TextStyle(fontSize: 10, color: secondaryInk(context))),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          s.display(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );

  Widget entryTile(Json e) {
    final d = e['data'];
    final style = ledgerIndex(s.view).byId[d['category_id']]?['data'];
    final originLedger = s.ledgers.firstWhere(
      (l) => l['id'] == e['source_ledger_id'],
      orElse: () => s.viewLedgers.first,
    );
    final origin =
        ledgerIndex(originLedger).byId[e['source_entry_id'] ?? e['id']] ?? e;
    final income = cashFlowType(d) == 'income',
        transfer = d['type'] == 'transfer';
    final p = AppPalette.of(context);
    final subtitleText = transactionSubtitle(
      s.view,
      e,
      sourceLedger: s.viewLedgers.length > 1
          ? originLedger['name'] as String
          : null,
      shared: originLedger['shared'] == true,
    );
    final tile = InkWell(
      onTap: () async {
        if (s.active['id'] != originLedger['id']) {
          await s.select(originLedger['id'], preserveView: true);
        }
        await record(entry: origin);
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border, width: 0.6)),
        ),
        child: Row(
          children: [
            CategoryBadge(
              name: categoryName(s.view, d),
              icon: transfer
                  ? 'transfer'
                  : visualIcon(
                      s.view,
                      ledgerIndex(s.view).byId[d['category_id']],
                    ),
              color: style?['color'],
              size: 32,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isRefund(d)
                        ? '退款 · ${categoryName(s.view, d)}'
                        : transfer
                        ? '${d['account']} → ${d['to_account']}'
                        : categoryName(s.view, d),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                  if (subtitleText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      key: ValueKey('entry-subtitle-${e['id']}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: p.ink3),
                    ),
                  ] else
                    SizedBox.shrink(key: ValueKey('entry-subtitle-${e['id']}')),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${transfer
                      ? ''
                      : income || isRefund(d)
                      ? '+'
                      : '−'}${formatAmount(d['original_amount_minor'] ?? d['amount'], d['original_currency'] ?? settingsOf(originLedger)['base_currency'])}${(d['original_currency'] ?? settingsOf(originLedger)['base_currency']) != s.currency ? ' ${d['original_currency']}' : ''}',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    fontFeatures: tabularFigures,
                    color: income ? p.income : p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  d['original_currency'] != null &&
                          d['original_currency'] !=
                              settingsOf(originLedger)['base_currency']
                      ? '≈ ${settingsOf(originLedger)['base_currency']} ${formatAmount(d['amount'], settingsOf(originLedger)['base_currency'])}'
                      : entryTime(d),
                  style: TextStyle(
                    fontSize: 10,
                    fontFeatures: tabularFigures,
                    color: p.ink3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (originLedger['role'] == 'viewer') return tile;
    return SwipeEntry(
      key: ValueKey(e['id']),
      canTemplate: !isRefund(d) && d['type'] != 'transfer',
      canRefund:
          d['type'] == 'expense' &&
          !isRefund(d) &&
          (origin['data']['amount'] as int) >
              (ledgerIndex(originLedger).refunds[origin['id']] ?? 0),
      action: (value) async {
        if (s.active['id'] != originLedger['id']) {
          await s.select(originLedger['id'], preserveView: true);
        }
        await entryAction(value, origin);
      },
      child: tile,
    );
  }

  Future<void> entryAction(String value, Json entry) async {
    if (value == '存为模板') {
      await Navigator.push(
        context,
        AppPageRoute(builder: (_) => TemplateEditor(s, source: entry['data'])),
      );
      return;
    }
    if (value == '复制') {
      await record(entry: entry, copy: true);
      return;
    }
    if (value == '编辑') {
      await record(entry: entry);
      return;
    }
    if (value == '退款') {
      final value = await ask(
        '退款金额（${s.currency}）· 可退 ${s.display(s.refundable(entry))}',
        initial: s.display(s.refundable(entry)),
        number: true,
      );
      if (value != null) {
        await action(
          () => s.refund(entry, parseAmount(value, s.currency)),
          success: '退款已计入收入，并回补当期预算',
        );
      }
      return;
    }
    if (await confirm(
      '移入回收站？',
      '保留30天，关联退款将一起移入。${s.hasRecurringLink(entry['id']) ? '\n此流水关联周期账单，本期将保留已处理状态避免重复入账；恢复流水后关联仍保留。' : ''}',
    )) {
      final book = s.active;
      try {
        await s.trashEntry(entry);
        notifyApp(
          '已移入回收站',
          action: '撤销',
          onAction: () {
            s
                .restoreTrashEntry(book, entry)
                .catchError((Object e) => notifyApp(e.toString(), error: true));
          },
        );
      } catch (e) {
        toast(e.toString());
      }
    }
  }

  Future<void> editBudget(String category) async {
    if (s.active['role'] != 'owner') {
      toast('预算由账本所有者管理');
      return;
    }
    final value = await ask(
      '${category == '全部' ? '全部' : s.choices('category', archived: true).firstWhere((c) => c['id'] == category)['data']['name']} · ${s.period(month).label} 预算',
      initial: s.display(s.budget(month, category)),
      number: true,
    );
    if (value != null) {
      await action(
        () => s.setBudget(
          month,
          category,
          parseAmount(value, s.currency, zero: true),
        ),
        success: '预算已保存',
      );
    }
  }

  static const bookIcons = {
    'book': Icons.menu_book_outlined,
    'home': Icons.home_outlined,
    'travel': Icons.flight_outlined,
    'work': Icons.work_outline,
    'gift': Icons.card_giftcard,
    'savings': Icons.savings_outlined,
  };

  Future<void> bookAction(String value, Json book) async {
    if (value == '复制') {
      await action(() => s.copyBook(book), success: '已复制账本');
      return;
    }
    if (value == '编辑') {
      final controller = TextEditingController(text: book['name']);
      var icon = book['icon'] as String? ?? 'book';
      final accepted = await settledDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: const Text('编辑账本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final choice in bookIcons.entries)
                      IconButton(
                        onPressed: () => set(() => icon = choice.key),
                        icon: Icon(
                          choice.value,
                          color: icon == choice.key ? teal : secondaryInk(c),
                        ),
                      ),
                  ],
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
      final name = controller.text.trim();
      controller.dispose();
      if (accepted != true || name.isEmpty) return;
      await action(() async {
        if (book['shared'] == true) {
          if (book['role'] != 'owner') throw const FormatException('仅所有者可修改名称');
          await s.api(
            '/api/ledgers/${book['id']}',
            method: 'PATCH',
            body: {'name': name},
          );
        }
        final old = {...book};
        book['name'] = name;
        book['icon'] = icon;
        try {
          await s.persist();
        } catch (_) {
          book
            ..clear()
            ..addAll(old);
          rethrow;
        }
      }, success: '账本已保存');
      return;
    }
    if (await confirm(
      '移除 ${book['name']}？',
      book['shared'] == true ? '仅移除本机副本，其他成员不受影响。' : '移入回收站，保留30天。',
    )) {
      await action(() => s.trashBook(book), success: '账本已移入回收站');
    }
  }

  List<Widget> ledgerPage() => [
    Text('账本', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w500)),
    gap(8),

    gap(16),
    ...s.ledgers.map(
      (l) => SwipeEntry(
        action: (value) => bookAction(value, l),
        child: InkWell(
          onTap: () => action(() => s.select(l['id'])),
          child: card(
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    bookIcons[l['icon']] ??
                        (l['shared'] == true
                            ? Icons.group_outlined
                            : Icons.menu_book_outlined),
                    color: teal,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l['name'],
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      gap(5),
                      label('本机账本 · ${s.records(l).length} 笔'),
                    ],
                  ),
                ),
                if (l['id'] == s.active['id'])
                  Icon(Icons.check_circle, color: teal),
              ],
            ),
          ),
        ),
      ),
    ),
    OutlinedButton.icon(
      onPressed: () async {
        final name = await ask('新建账本');
        if (name == null || !mounted) return;
        final currency = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(
            title: Text('选择基准币种'),
            children: currencies.keys
                .map(
                  (v) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, v),
                    child: Text(v == 'CNY' ? 'CNY · 人民币（默认）' : v),
                  ),
                )
                .toList(),
          ),
        );
        if (currency != null) {
          await action(() => s.addLedger(name, currency: currency));
        }
      },
      icon: Icon(Icons.add),
      label: Text('新建账本'),
    ),
    gap(),
    FilledButton.icon(
      onPressed: settings,
      icon: Icon(Icons.cloud_outlined),
      label: Text('共享、备份与设置'),
    ),
  ];
  Future<void> chooseView() async {
    if (tab == 3 && analysisMode == 1) {
      final id = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('预算账本'),
          children: s.ledgers
              .map(
                (l) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, l['id']),
                  child: Text(l['name']),
                ),
              )
              .toList(),
        ),
      );
      if (id != null) await action(() => s.select(id, preserveView: true));
      return;
    }
    final ids = await pickLedgers(context, s);
    if (ids != null) await action(() => s.setViewLedgers(ids));
  }

  Future<void> mergeBooks() async {
    final ids = await pickLedgers(context, s, merge: true);
    if (ids == null || !mounted) return;
    final name = await ask('合并账本名称', initial: '合并账本');
    if (name == null || !mounted) return;
    await Navigator.push(
      context,
      AppPageRoute(
        builder: (_) => MergePage(s, ids: ids, name: name),
      ),
    );
  }

  void openBooks() => Navigator.push(
    context,
    AppPageRoute(
      builder: (_) => AnimatedBuilder(
        animation: s,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: const Text('账本管理')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ...ledgerPage(),
              OutlinedButton.icon(
                onPressed: mergeBooks,
                icon: const Icon(Icons.merge),
                label: const Text('合并流水'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget scopeSummary() {
    if (s.viewLedgers.length == 1 && s.view['id'] == s.active['id']) {
      return periodSummary();
    }
    final rows = s.monthRecords(month, ledger: s.view),
        sums = <String, List<int>>{};
    for (final e in rows) {
      final d = e['data'];
      if (d['type'] == 'transfer') continue;
      final v = sums.putIfAbsent(d['base_currency'] ?? 'CNY', () => [0, 0]);
      v[cashFlowType(d) == 'income' ? 1 : 0] += cashFlowAmount(d);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.period(month, ledger: s.view).label),
            const SizedBox(height: 8),
            for (final e in sums.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${e.key}  支 ${formatAmount(e.value[0], e.key)}  收 ${formatAmount(e.value[1], e.key)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  void settings() => setState(() {
    tab = 4;
    visited.add(4);
  });
  void openDetails(
    String title,
    EntryFilter filter,
    Set<String> ids,
    Json ledger,
  ) => Navigator.push(
    context,
    AppPageRoute(
      builder: (_) => LedgerDetailPage(
        store: s,
        ledger: ledger,
        title: title,
        filter: filter,
        ids: ids,
        tile: entryTile,
      ),
    ),
  );
}

class SettingsPage extends StatelessWidget {
  final LedgerStore s;
  final bool embedded;
  final VoidCallback? onBooks;
  const SettingsPage(this.s, {super.key, this.embedded = false, this.onBooks});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    void open(Widget page) =>
        Navigator.push(context, AppPageRoute(builder: (_) => page));
    Widget row(
      String title,
      IconData icon,
      VoidCallback action, {
      String? detail,
      Color? tint,
    }) {
      final fg = tint ?? p.brandColor;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        minTileHeight: 50,
        leading: Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            color: fg.withValues(alpha: p.isDark ? 0.18 : 0.11),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 17,
            color: p.isDark ? Color.lerp(fg, Colors.white, 0.25) : fg,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: p.ink,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (detail != null) ...[
              Text(detail, style: TextStyle(fontSize: 11, color: p.ink3)),
              const SizedBox(width: 6),
            ],
            Icon(CupertinoIcons.chevron_right, size: 13, color: p.ink3),
          ],
        ),
        onTap: action,
      );
    }

    Widget group(String title, List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 7),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.ink3,
              ),
            ),
          ),
          GlassPanel(
            radius: isAndroidPlatform ? 20 : 18,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.only(left: 58, right: 14),
                      child: Divider(height: 1),
                    ),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final styleLabel = appThemeStyleOf(s.state['themeStyle']).label;
    final brightLabel = switch (s.state['theme']) {
      'light' => '浅色',
      'dark' => '深色',
      _ => '系统',
    };
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('我的')),
      body: SafeArea(
        child: ListView(
          key: const PageStorageKey('my-settings'),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
          children: [
            if (embedded) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '我的',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.brandSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '本机离线保存',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: p.brandColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onBooks,
                  child: GlassPanel(
                    radius: isAndroidPlatform ? 20 : 18,
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: p.heroGradient,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: p.style.isCute
                                ? Border.all(color: p.heroBorder, width: 0.8)
                                : null,
                          ),
                          child: Center(
                            child: p.style.isCute
                                ? ThemeMascot(
                                    style: p.style,
                                    size: 34,
                                    mood: MascotMood.happy,
                                  )
                                : Text(
                                    '数',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: p.heroInk,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.active['name'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '本机账本 · ${s.records(s.active).length} 笔 · ${s.currency}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFeatures: tabularFigures,
                                  color: p.ink3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onBooks != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: p.surface2,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '管理',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: p.ink2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            group('账本与数据', [
              row(
                '常用模板',
                CupertinoIcons.square_grid_2x2,
                () => openTemplates(context, s),
                detail: '随手记 · 周期记账',
                tint: p.brandColor,
              ),
              if (onBooks != null)
                row(
                  '账本管理',
                  CupertinoIcons.book,
                  onBooks!,
                  detail: '${s.ledgers.length} 个账本',
                  tint: const Color(0xFF3B82A6),
                ),
              row(
                '导入与导出',
                CupertinoIcons.arrow_up_arrow_down,
                () => open(DataPage(s)),
                tint: const Color(0xFF7E6BB5),
              ),
              row(
                '备份与恢复',
                CupertinoIcons.archivebox,
                () => open(BackupsPage(s)),
                tint: p.income,
              ),
            ]),
            group('偏好与提醒', [
              row(
                '偏好设置',
                CupertinoIcons.gear,
                () => open(PreferencesPage(s)),
                detail: '$styleLabel · $brightLabel',
                tint: p.brandColor,
              ),
              row(
                '提醒与免打扰',
                CupertinoIcons.bell,
                () => open(RemindersPage(s)),
                tint: const Color(0xFFD97736),
              ),
            ]),
            group('更多', [
              row(
                '回收站',
                CupertinoIcons.trash,
                () => open(TrashPage(s)),
                tint: p.danger,
              ),
              row(
                '使用帮助',
                CupertinoIcons.question_circle,
                () => open(const HelpPage()),
                tint: const Color(0xFF64748B),
              ),
              if (Platform.isAndroid)
                row(
                  '检查更新',
                  CupertinoIcons.arrow_down_circle,
                  () => open(const UpdatePage()),
                  tint: p.brandColor,
                ),
            ]),
            Center(child: hint('有数 $appRelease')),
          ],
        ),
      ),
    );
  }
}
