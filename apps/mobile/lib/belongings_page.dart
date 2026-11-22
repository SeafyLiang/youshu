import 'package:flutter/services.dart';

import 'belongings_links.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'belongings_store.dart';
import 'belongings_media.dart';
import 'belongings_forms.dart';
import 'belongings_backup_page.dart';
import 'store.dart' show LedgerStore;
import 'ui.dart'
    show
        AppPageRoute,
        AppPalette,
        CircleAction,
        GlassPanel,
        MarkerHighlight,
        MascotMood,
        ThemeMascot,
        isAndroidPlatform,
        message,
        tabularFigures;

const bGreen = Color(0xff0E7460);
void bToast(BuildContext context, Object error) => message(context, error);
Future<T?> bPush<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(AppPageRoute(builder: (_) => page));
Future<bool> bConfirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;
Widget bCard(
  BuildContext context,
  Widget child, {
  EdgeInsets padding = const EdgeInsets.all(15),
}) => GlassPanel(
  radius: isAndroidPlatform ? 20 : 18,
  padding: padding,
  child: child,
);
Widget bCaption(String text) => Builder(
  builder: (c) =>
      Text(text, style: TextStyle(fontSize: 11.5, color: AppPalette.of(c).ink3)),
);

class BelongingsPage extends StatefulWidget {
  final LedgerStore ledger;
  const BelongingsPage(this.ledger, {super.key});
  @override
  State<BelongingsPage> createState() => BelongingsPageState();
}

class BelongingsPageState extends State<BelongingsPage> {
  BelongingsStore? store;
  Object? error;
  String query = '', category = '全部', status = '持有中', sort = '最近购买';
  bool grid = false;
  @override
  void initState() {
    super.initState();
    open();
  }

  Future<void> open() async {
    try {
      final s = await widget.ledger.openBelongings();
      if (mounted) {
        setState(() {
          store = s;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> addItem() async {
    if (store != null) await bPush(context, BelongingForm(store!));
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('物品数据暂时无法打开'),
            TextButton(onPressed: open, child: const Text('重试')),
          ],
        ),
      );
    }
    if (store == null) return const Center(child: CircularProgressIndicator());
    final s = store!;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final held = s.items.where((i) => i.held).toList();
        final total = held.fold<int>(0, (n, i) => n + i.price);
        final heldCosts = s.costs.where(
          (c) => held.any((i) => i.id == c.itemId),
        );
        final allDaily = held.fold<double>(
          0,
          (n, i) => n + dailyCost(i, s.costsFor(i.id)),
        );
        final visible = s.items
            .where(
              (i) =>
                  (status == '全部' ||
                      (status == '持有中' ? i.held : i.state == status)) &&
                  (category == '全部' || i.category == category) &&
                  (query.isEmpty ||
                      '${i.name} ${i.note}'.toLowerCase().contains(
                        query.toLowerCase(),
                      )),
            )
            .toList();
        visible.sort(
          (a, b) => switch (sort) {
            '价格最高' => b.price.compareTo(a.price),
            '日均最高' => dailyCost(
              b,
              s.costsFor(b.id),
            ).compareTo(dailyCost(a, s.costsFor(a.id))),
            _ => b.purchase.compareTo(a.purchase),
          },
        );
        final alerts = s.items
            .where(
              (i) =>
                  i.held &&
                  [i.expiry, i.warranty].whereType<String>().any(
                    (d) => bDate(d).difference(bDate(bDay())).inDays <= 30,
                  ),
            )
            .length;
        final p = AppPalette.of(context);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 106),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '物品',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      Badge(
                        isLabelVisible: alerts > 0,
                        label: Text('$alerts'),
                        child: CircleAction(
                          tooltip: '到期与保修',
                          onTap: () =>
                              bPush(context, BelongingsRemindersPage(s)),
                          icon: Icons.notifications_none_rounded,
                        ),
                      ),
                      CircleAction(
                        tooltip: '物品数据备份',
                        onTap: () => bPush(
                          context,
                          BelongingsBackupPage(s, widget.ledger),
                        ),
                        icon: Icons.cloud_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: p.heroGradient,
                      ),
                      borderRadius: BorderRadius.circular(
                        isAndroidPlatform ? 22 : 20,
                      ),
                      border: p.style.isCute
                          ? Border.all(color: p.heroBorder, width: 0.9)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: (p.style.isCute
                                  ? p.brandColor
                                  : p.heroGradient.first)
                              .withValues(
                                alpha: p.isDark
                                    ? 0.36
                                    : (p.style.isCute ? 0.12 : 0.24),
                              ),
                          blurRadius: p.style.isCute ? 14 : 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: DefaultTextStyle(
                      style: TextStyle(color: p.heroInk),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (p.style.isCute)
                            Positioned(
                              right: -2,
                              top: -4,
                              child: IgnorePointer(
                                child: ThemeMascot(
                                  style: p.style,
                                  size: 58,
                                  mood: MascotMood.signature,
                                ),
                              ),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '总资产 · 持有物品原值',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: p.heroSubInk,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: p.heroBadgeBg,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${held.length} 件',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: p.heroBadgeInk,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 3,
                                  bottom: 7,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: MarkerHighlight(
                                    height: 9,
                                    bottom: 2,
                                    child: Text(
                                      '¥ ${bMoney(total)}',
                                      key: const Key('belongings-total'),
                                      style: TextStyle(
                                        fontSize: 27,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.7,
                                        fontFeatures: tabularFigures,
                                        color: p.heroInk,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.only(top: 7),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: p.style.isCute
                                          ? p.heroBorder
                                          : Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                      width: 0.7,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '养护 ¥${bMoney(maintenanceCost(heldCosts))}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontFeatures: tabularFigures,
                                          color: p.heroSubInk,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '合计日均 ¥${bMoney(allDaily)}',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          fontFeatures: tabularFigures,
                                          color: p.heroInk,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => setState(() => query = v),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索物品',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 19,
                        color: p.ink3,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      filled: true,
                      fillColor: p.card,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: p.border, width: 0.9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: p.brandColor, width: 1.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: p.brandSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: status,
                            isDense: true,
                            iconEnabledColor: p.brandColor,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: p.brandColor,
                            ),
                            items: ['持有中', ...belongingStates, '全部']
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      v,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: p.ink,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => status = v!),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: p.borderStrong, width: 0.8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: category,
                            isDense: true,
                            iconEnabledColor: p.ink2,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: p.ink,
                            ),
                            items: ['全部', ...belongingCategories]
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      v == '全部' ? '全部分类' : v,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: p.ink,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => category = v!),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '排序：$sort',
                        initialValue: sort,
                        onSelected: (v) => setState(() => sort = v),
                        icon: Icon(Icons.sort_rounded, size: 19, color: p.ink2),
                        itemBuilder: (_) => ['最近购买', '价格最高', '日均最高']
                            .map(
                              (v) => CheckedPopupMenuItem(
                                value: v,
                                checked: sort == v,
                                child: Text(v),
                              ),
                            )
                            .toList(),
                      ),
                      IconButton(
                        tooltip: grid ? '切换列表' : '切换网格',
                        onPressed: () => setState(() => grid = !grid),
                        icon: Icon(
                          grid
                              ? Icons.view_list_rounded
                              : Icons.grid_view_rounded,
                          size: 19,
                          color: grid ? p.brandColor : p.ink2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 40,
                            color: p.brandColor,
                          ),
                          const SizedBox(height: 10),
                          Text(s.items.isEmpty ? '让每件物品，都有自己的记录' : '没有符合条件的物品'),
                          const SizedBox(height: 6),
                          bCaption(
                            s.items.isEmpty ? '记下购入、维修和陪伴的每一天' : '试试其他分类或搜索词',
                          ),
                          if (s.items.isEmpty)
                            TextButton.icon(
                              onPressed: addItem,
                              icon: const Icon(Icons.add),
                              label: const Text('添加第一件物品'),
                            ),
                        ],
                      ),
                    ),
                  if (grid)
                    LayoutBuilder(
                      builder: (c, box) {
                        final cols = box.maxWidth > 600 ? 3 : 2;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: visible
                              .map(
                                (i) => SizedBox(
                                  width:
                                      (box.maxWidth - 10 * (cols - 1)) / cols,
                                  child: tile(i, true),
                                ),
                              )
                              .toList(),
                        );
                      },
                    )
                  else
                    ...visible.map(
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: tile(i, false),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget tile(Belonging i, bool grid) {
    final s = store!, cost = dailyCost(i, s.costsFor(i.id));
    final p = AppPalette.of(context);
    final image = BelongingImage(
      s,
      icon: i.icon,
      media: i.cover,
      size: grid ? 68 : 50,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(isAndroidPlatform ? 20 : 18),
      onTap: () => bPush(context, BelongingDetail(s, i.id)),
      child: bCard(
        context,
        grid
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: image),
                  const SizedBox(height: 8),
                  Text(
                    i.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  bCaption('${i.state} · ${bDuration(i.days())}'),
                  const SizedBox(height: 7),
                  Text(
                    '¥${bMoney(cost)} / 天',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                      color: p.brandColor,
                    ),
                  ),
                  bCaption('购入 ¥${bMoney(i.price)}'),
                ],
              )
            : Row(
                children: [
                  image,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                i.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
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
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                i.state,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: p.brandColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        bCaption(
                          '${bDuration(i.days())}  ·  原价 ¥${bMoney(i.price)}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '¥${bMoney(cost)}',
                        style: TextStyle(
                          color: p.brandColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: -0.3,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                      bCaption('每天'),
                    ],
                  ),
                ],
              ),
        padding: const EdgeInsets.all(11),
      ),
    );
  }
}

class BelongingDetail extends StatelessWidget {
  final BelongingsStore store;
  final String id;
  const BelongingDetail(this.store, this.id, {super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (c, _) {
      final found = store.items.where((i) => i.id == id);
      if (found.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('物品')),
          body: const Center(child: Text('物品已删除')),
        );
      }
      final i = found.first,
          costs = store.costsFor(id),
          maintenance = maintenanceCost(costs),
          daily = dailyCost(i, costs),
          p = AppPalette.of(context);
      return Scaffold(
        appBar: AppBar(
          title: const Text('物品详情'),
          actions: [
            CircleAction(
              tooltip: '编辑物品',
              onTap: () => bPush(context, BelongingForm(store, item: i)),
              icon: Icons.edit_outlined,
            ),
            const SizedBox(width: 10),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Row(
              children: [
                BelongingImage(store, icon: i.icon, media: i.cover, size: 68),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.name,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      bCaption(
                        '${i.category} · ${i.state} · ${bDuration(i.days())}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            bCard(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bCaption(i.held ? '当前日均成本' : '最终日均成本'),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '¥${bMoney(daily)}',
                      key: const Key('belonging-daily'),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        fontFeatures: tabularFigures,
                        color: p.brandColor,
                      ),
                    ),
                  ),
                  bCaption('（购入 + 养护 − 回收）÷ 持有天数'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      metric(context, '购入原价', i.price),
                      const SizedBox(width: 10),
                      metric(context, '养护费用', maintenance),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      metric(context, '累计投入', i.price + maintenance),
                      const SizedBox(width: 10),
                      metric(context, '回收金额', i.recovery),
                    ],
                  ),
                  if (i.target != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      daily <= i.target!
                          ? '已达到日均 ¥${bMoney(i.target!)} 的目标'
                          : '目标日均 ¥${bMoney(i.target!)} · 无新增费用时约还需 ${math.max(0, ((i.price + maintenance - i.recovery) / i.target!).ceil() - i.days())} 天',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: p.brandColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            bCard(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '日均成本趋势',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  bCaption('最近 ${math.min(180, i.days())} 天 · 维修按发生日计入'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 112,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _CostPainter(
                        belongingCurve(i, costs),
                        p.ink3,
                        p.brandColor,
                        p.card,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      bCaption(belongingCurve(i, costs).first.$1),
                      bCaption(i.end ?? bDay()),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '维修与养护',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  key: const Key('add-belonging-cost'),
                  onPressed: () => bPush(context, BelongingCostForm(store, i)),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('记一笔'),
                ),
              ],
            ),
            if (costs.isEmpty) bCard(context, bCaption('维修、保养和配件支出，都记在这里。')),
            ...costs.map(
              (cost) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: bCard(
                  context,
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      child: Icon(
                        cost.kind == '维修'
                            ? Icons.build_outlined
                            : cost.kind == '保养'
                            ? Icons.cleaning_services_outlined
                            : Icons.extension_outlined,
                        size: 19,
                      ),
                    ),
                    title: Text(cost.title),
                    subtitle: Text(
                      '${cost.date} · ${cost.kind}${cost.vendor.isEmpty ? '' : ' · ${cost.vendor}'}',
                    ),
                    trailing: Text(
                      '¥${bMoney(cost.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () =>
                        bPush(context, BelongingCostForm(store, i, cost: cost)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            bCard(
              context,
              Column(
                children: [
                  info('购买时间', i.purchase),
                  if (i.purchaseUrl != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: const Text('购买链接'),
                      subtitle: Text(
                        Uri.parse(i.purchaseUrl!).host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        try {
                          await openPurchaseLink(i.purchaseUrl!);
                        } catch (e) {
                          if (context.mounted) bToast(context, e);
                        }
                      },
                      trailing: IconButton(
                        tooltip: '复制购买链接',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: i.purchaseUrl!),
                          );
                          if (context.mounted) bToast(context, '已复制购买链接');
                        },
                      ),
                    ),
                  if (i.expiry != null) info('有效期至', i.expiry!),
                  if (i.warranty != null) info('保修至', i.warranty!),
                  if (i.end != null) info('结束时间', i.end!),
                  info('到期提醒', i.remind < 0 ? '关闭' : '提前 ${i.remind} 天及当天'),
                  if (i.note.isNotEmpty) info('备注', i.note),
                ],
              ),
            ),
            if (i.photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: i.photos
                    .map(
                      (m) => InkWell(
                        onTap: () =>
                            bPush(context, BelongingPhotoPage(store, m)),
                        child: BelongingImage(
                          store,
                          icon: i.icon,
                          media: m,
                          size: 90,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => bPush(context, BelongingForm(store, item: i)),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('修改状态 / 售出 / 退役'),
            ),
            TextButton(
              onPressed: () async {
                if (!await bConfirm(
                  context,
                  '删除物品？',
                  '将删除「${i.name}」和 ${costs.length} 条养护记录，无法撤销。',
                )) {
                  return;
                }
                try {
                  await store.deleteItem(i);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) bToast(context, e);
                }
              },
              child: const Text(
                '删除物品',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget metric(BuildContext context, String label, int n) {
    final p = AppPalette.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bCaption(label),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '¥${bMoney(n)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 86, child: bCaption(label)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class _CostPainter extends CustomPainter {
  final List<(String, double)> values;
  final Color axis;
  final Color accent;
  final Color dotStroke;
  _CostPainter(this.values, this.axis, this.accent, this.dotStroke);
  @override
  void paint(Canvas canvas, Size size) {
    final maxV = math.max(1.0, values.map((v) => v.$2).reduce(math.max));
    final paint = Paint()
      ..color = axis.withValues(alpha: .16)
      ..strokeWidth = .6;
    for (var n = 0; n < 3; n++) {
      final y = 12 + (size.height - 24) * n / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      final label = TextPainter(
        text: TextSpan(
          text: '¥${bMoney(maxV * (1 - n / 2))}',
          style: TextStyle(color: axis, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y + 2));
    }
    final path = Path();
    final fill = Path();
    double? lastX, lastY, firstX;
    final bottomY = size.height - 12;
    for (var n = 0; n < values.length; n++) {
      final x =
              50 +
              (size.width - 54) *
                  (values.length == 1 ? 1 : n / (values.length - 1)),
          y = 12 + (size.height - 24) * (1 - values[n].$2 / maxV);
      if (n == 0) {
        firstX = x;
        path.moveTo(x, y);
        fill.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
      lastX = x;
      lastY = y;
    }
    if (firstX != null && lastX != null) {
      fill
        ..lineTo(lastX, bottomY)
        ..lineTo(firstX, bottomY)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.22),
              accent.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 12, size.width, size.height - 24)),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (lastX != null && lastY != null) {
      canvas.drawCircle(Offset(lastX, lastY), 4.5, Paint()..color = dotStroke);
      canvas.drawCircle(Offset(lastX, lastY), 3.2, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(covariant _CostPainter old) =>
      old.accent != accent || old.axis != axis || old.values != values;
}

class BelongingPhotoPage extends StatelessWidget {
  final BelongingsStore store;
  final String media;
  const BelongingPhotoPage(this.store, this.media, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('图片')),
    body: Center(
      child: InteractiveViewer(child: Image.file(store.mediaFile(media))),
    ),
  );
}

class BelongingsRemindersPage extends StatelessWidget {
  final BelongingsStore store;
  const BelongingsRemindersPage(this.store, {super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (c, _) {
      final entries = [
        for (final i in store.items.where((i) => i.held))
          for (final pair in [(i.expiry, '有效期'), (i.warranty, '保修')])
            if (pair.$1 != null) (i, pair.$1!, pair.$2),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      return Scaffold(
        appBar: AppBar(title: const Text('到期与保修')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            bCaption('到期不会自动退役。系统提醒按物品设置发送，需开启通知权限；打开有数时补充后续提醒。'),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有设置有效期或保修时间'),
              ),
            ...entries.map((e) {
              final days = bDate(e.$2).difference(bDate(bDay())).inDays;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: BelongingImage(
                  store,
                  icon: e.$1.icon,
                  media: e.$1.cover,
                  size: 48,
                ),
                title: Text(e.$1.name),
                subtitle: Text(
                  '${e.$3} · ${e.$2}${e.$1.remind < 0 ? ' · 提醒关闭' : ''}',
                ),
                trailing: Text(
                  days < 0
                      ? '已过期'
                      : days == 0
                      ? '今天到期'
                      : '剩 $days 天',
                  style: TextStyle(
                    color: days <= 7
                        ? AppPalette.of(context).warn
                        : AppPalette.of(context).brandColor,
                    fontSize: 12,
                  ),
                ),
                onTap: () => bPush(context, BelongingDetail(store, e.$1.id)),
              );
            }),
          ],
        ),
      );
    },
  );
}
