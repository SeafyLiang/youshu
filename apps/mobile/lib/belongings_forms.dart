import 'package:flutter/services.dart';

import 'belongings_links.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'belongings_store.dart';
import 'belongings_media.dart';
import 'belongings_page.dart';

Future<String?> bPickDate(
  BuildContext context,
  String? current, {
  String? first,
  String? last,
}) async {
  final start = bDate(first ?? '1900-01-01'), end = bDate(last ?? '2200-12-31');
  var initial = bDate(current ?? bDay());
  if (initial.isBefore(start)) initial = start;
  if (initial.isAfter(end)) initial = end;
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: start,
    lastDate: end,
  );
  return picked == null ? null : bDay(picked);
}

Widget bField(
  TextEditingController c,
  String label, {
  bool money = false,
  int lines = 1,
  Key? key,
  int? maxLength,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextField(
    key: key,
    controller: c,
    maxLength: maxLength,
    maxLines: lines,
    keyboardType: money
        ? const TextInputType.numberWithOptions(decimal: true)
        : lines > 1
        ? TextInputType.multiline
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      prefixText: money ? '¥ ' : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      counterText: '',
    ),
  ),
);
Widget bDateRow(
  String title,
  String? value,
  VoidCallback tap, {
  VoidCallback? clear,
}) => ListTile(
  contentPadding: EdgeInsets.zero,
  title: Text(title, style: const TextStyle(fontSize: 14)),
  trailing: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value ?? '未设置',
        style: TextStyle(color: value == null ? Colors.grey : null),
      ),
      if (value != null && clear != null)
        IconButton(
          tooltip: '清除$title',
          onPressed: clear,
          icon: const Icon(Icons.close, size: 16),
        )
      else
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.chevron_right, size: 18),
        ),
    ],
  ),
  onTap: tap,
);

class BelongingForm extends StatefulWidget {
  final BelongingsStore store;
  final Belonging? item;
  const BelongingForm(this.store, {super.key, this.item});
  @override
  State<BelongingForm> createState() => _BelongingFormState();
}

class _BelongingFormState extends State<BelongingForm> {
  late final name = TextEditingController(text: widget.item?.name),
      price = TextEditingController(
        text: widget.item == null
            ? ''
            : (widget.item!.price / 100).toStringAsFixed(2),
      ),
      purchaseLink = TextEditingController(text: widget.item?.purchaseUrl),
      note = TextEditingController(text: widget.item?.note),
      target = TextEditingController(
        text: widget.item?.target == null
            ? ''
            : (widget.item!.target! / 100).toStringAsFixed(2),
      ),
      recovery = TextEditingController(
        text: ((widget.item?.recovery ?? 0) / 100).toStringAsFixed(2),
      );
  late String icon = widget.item?.icon ?? 'laptop',
      category = widget.item?.category ?? '数码',
      status = widget.item?.state ?? '在用',
      purchase = widget.item?.purchase ?? bDay();
  late String? cover = widget.item?.cover,
      expiry = widget.item?.expiry,
      warranty = widget.item?.warranty,
      end = widget.item?.end;
  late String? coverSource = widget.item?.coverSource;
  late BJson? coverEdit = widget.item?.coverEdit;
  late int remind = widget.item?.remind ?? 7;
  late List<String> photos = [...?widget.item?.photos];
  bool busy = false;
  @override
  void dispose() {
    for (final c in [name, price, note, target, recovery, purchaseLink]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> image({bool attachment = false}) async {
    setState(() => busy = true);
    try {
      final result = await pickBelongingPhoto(
        context,
        widget.store,
        cover: !attachment,
        source: attachment ? null : coverSource ?? cover,
        edit: attachment ? null : coverEdit,
      );
      final m = result?.media;
      if (m != null && mounted) {
        setState(() {
          if (attachment) {
            if (!photos.contains(m)) photos.add(m);
          } else {
            cover = m;
            coverSource = result!.source;
            coverEdit = result.metadata;
          }
        });
      }
    } catch (e) {
      if (mounted) bToast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pasteLink() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final urls = extractPurchaseUrls(text);
    if (!mounted) return;
    if (urls.isEmpty) {
      bToast(context, '未找到 HTTP / HTTPS 链接，请复制购物平台的分享链接');
      return;
    }
    final selected = urls.length == 1
        ? urls.single
        : await showModalBottomSheet<String>(
            context: context,
            builder: (c) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('选择要保存的购买链接')),
                  ...urls.map(
                    (u) => ListTile(
                      title: Text(Uri.parse(u).host),
                      subtitle: Text(
                        u,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(c, u),
                    ),
                  ),
                ],
              ),
            ),
          );
    if (mounted && selected != null) {
      setState(() => purchaseLink.text = selected);
    }
  }

  Future<void> save() async {
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      final held = ['在用', '闲置'].contains(status);
      final item = Belonging({
        ...?widget.item?.data,
        'id': widget.item?.id ?? const Uuid().v4(),
        'name': name.text.trim(),
        'price': bCents(price.text),
        'purchase': purchase,
        'category': category,
        'icon': icon,
        'state': status,
        'currency': 'CNY',
        'note': note.text.trim(),
        'target': target.text.trim().isEmpty ? null : bCents(target.text),
        'cover': cover,
        'coverSource': coverSource,
        'coverEdit': coverEdit,
        'purchaseUrl': purchaseLink.text.trim().isEmpty
            ? null
            : purchaseLink.text.trim(),
        'photos': photos,
        'expiry': expiry,
        'warranty': warranty,
        'remind': remind,
        'end': held ? null : end,
        'recovery': status == '已售出' ? bCents(recovery.text) : 0,
      });
      await widget.store.saveItem(item);
      if (mounted) Navigator.pop(context, item.id);
    } catch (e) {
      if (mounted) bToast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext _) => Scaffold(
    appBar: AppBar(title: Text(widget.item == null ? '添加物品' : '编辑物品')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: FilledButton(
          key: const Key('save-belonging'),
          onPressed: busy ? null : save,
          child: Text(busy ? '正在保存…' : '保存物品'),
        ),
      ),
    ),
    body: AbsorbPointer(
      absorbing: busy,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              BelongingImage(widget.store, icon: icon, media: cover, size: 80),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => image(),
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 19,
                      ),
                      label: const Text('选择物品照片'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final value = await showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: true,
                          builder: (c) => SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '全彩图标',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: belongingIcons.entries
                                        .map(
                                          (e) => InkWell(
                                            onTap: () =>
                                                Navigator.pop(c, e.key),
                                            child: SizedBox(
                                              width: 64,
                                              child: Column(
                                                children: [
                                                  BelongingImage(
                                                    widget.store,
                                                    icon: e.key,
                                                    size: 56,
                                                  ),
                                                  Text(
                                                    e.value,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        if (value != null) {
                          setState(() {
                            icon = value;
                            cover = null;
                            coverSource = null;
                            coverEdit = null;
                          });
                        }
                      },
                      child: const Text('使用内置全彩图标'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          bField(name, '物品名称', key: const Key('belonging-name'), maxLength: 80),
          bField(price, '购买价格', money: true, key: const Key('belonging-price')),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: '分类'),
            items: belongingCategories
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => category = v!),
          ),
          bDateRow('购买时间', purchase, () async {
            final v = await bPickDate(context, purchase, last: bDay());
            if (v != null) setState(() => purchase = v);
          }),
          TextField(
            key: const Key('belonging-purchase-link'),
            controller: purchaseLink,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '购买链接（选填）',
              hintText: '商品或订单的 HTTP / HTTPS 链接',
              suffixIcon: IconButton(
                tooltip: '粘贴购物分享链接',
                icon: const Icon(Icons.content_paste),
                onPressed: pasteLink,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: bCaption('可粘贴京东、淘宝、拼多多等分享文案；订单跳转需要实际订单链接。'),
          ),
          const Divider(),
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: '物品状态'),
            items: belongingStates
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() {
              status = v!;
              if (['已退役', '已售出'].contains(v)) end ??= bDay();
            }),
          ),
          if (['已退役', '已售出'].contains(status))
            bDateRow('结束时间', end, () async {
              final v = await bPickDate(
                context,
                end,
                first: purchase,
                last: bDay(),
              );
              if (v != null) setState(() => end = v);
            }),
          if (status == '已售出')
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: bField(recovery, '售出回收金额', money: true),
            ),
          const SizedBox(height: 14),
          bCaption('闲置继续计算持有天数；售出或退役后日均成本冻结。'),
          const SizedBox(height: 22),
          bDateRow('有效期至', expiry, () async {
            final v = await bPickDate(context, expiry, first: purchase);
            if (v != null) setState(() => expiry = v);
          }, clear: () => setState(() => expiry = null)),
          bDateRow('保修至', warranty, () async {
            final v = await bPickDate(context, warranty, first: purchase);
            if (v != null) setState(() => warranty = v);
          }, clear: () => setState(() => warranty = null)),
          DropdownButtonFormField<int>(
            initialValue: remind,
            decoration: const InputDecoration(labelText: '到期提醒'),
            items: [-1, 1, 7, 30]
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v < 0 ? '关闭' : '提前 $v 天和当天'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => remind = v!),
          ),
          const SizedBox(height: 22),
          bField(target, '目标日均价格（选填）', money: true),
          bField(note, '备注（选填）', lines: 3, maxLength: 2000),
          const Text('附加照片', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ...photos.map(
                (m) => Stack(
                  children: [
                    InkWell(
                      onTap: () =>
                          bPush(context, BelongingPhotoPage(widget.store, m)),
                      child: BelongingImage(
                        widget.store,
                        icon: icon,
                        media: m,
                        size: 90,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton.filled(
                        tooltip: '移除照片',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => photos.remove(m)),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              if (photos.length < 5)
                SizedBox(
                  width: 90,
                  height: 90,
                  child: OutlinedButton(
                    onPressed: () => image(attachment: true),
                    child: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          bCaption('最多 5 张附加照片，单张原图不超过 10 MB。'),
        ],
      ),
    ),
  );
}

class BelongingCostForm extends StatefulWidget {
  final BelongingsStore store;
  final Belonging item;
  final BelongingCost? cost;
  const BelongingCostForm(this.store, this.item, {super.key, this.cost});
  @override
  State<BelongingCostForm> createState() => _BelongingCostFormState();
}

class _BelongingCostFormState extends State<BelongingCostForm> {
  late final amount = TextEditingController(
        text: widget.cost == null
            ? ''
            : (widget.cost!.amount / 100).toStringAsFixed(2),
      ),
      title = TextEditingController(text: widget.cost?.title),
      vendor = TextEditingController(text: widget.cost?.vendor),
      note = TextEditingController(text: widget.cost?.note);
  late String kind = widget.cost?.kind ?? '维修',
      date = widget.cost?.date ?? widget.item.end ?? bDay();
  late String? receipt = widget.cost?.receipt;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    amount.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [amount, title, vendor, note]) {
      c.dispose();
    }
    super.dispose();
  }

  BelongingCost draft() => BelongingCost({
    ...?widget.cost?.data,
    'id': widget.cost?.id ?? const Uuid().v4(),
    'itemId': widget.item.id,
    'amount': bCents(amount.text),
    'title': title.text.trim(),
    'kind': kind,
    'date': date,
    'vendor': vendor.text.trim(),
    'note': note.text.trim(),
    'receipt': receipt,
  });
  Future<void> save() async {
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      await widget.store.saveCost(draft());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) bToast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext _) {
    double? after;
    try {
      after = dailyCost(widget.item, [
        ...widget.store
            .costsFor(widget.item.id)
            .where((c) => c.id != widget.cost?.id),
        draft(),
      ]);
    } catch (_) {
      /* Incomplete amount. */
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.cost == null ? '记录维修与养护' : '编辑养护记录')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: FilledButton(
            key: const Key('save-belonging-cost'),
            onPressed: busy ? null : save,
            child: Text(busy ? '正在保存…' : '保存养护记录'),
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                BelongingImage(
                  widget.store,
                  icon: widget.item.icon,
                  media: widget.item.cover,
                  size: 50,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              children: belongingCostKinds
                  .map(
                    (v) => ChoiceChip(
                      label: Text(v),
                      selected: kind == v,
                      onSelected: (_) => setState(() => kind = v),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            bField(
              amount,
              '费用金额（免费服务可填 0）',
              money: true,
              key: const Key('belonging-cost-amount'),
            ),
            bField(
              title,
              '维修 / 养护项目',
              key: const Key('belonging-cost-title'),
              maxLength: 120,
            ),
            bDateRow('发生时间', date, () async {
              final v = await bPickDate(
                context,
                date,
                first: widget.item.purchase,
                last: widget.item.end ?? bDay(),
              );
              if (v != null) setState(() => date = v);
            }),
            if (after != null)
              bCard(
                context,
                Row(
                  children: [
                    const Expanded(
                      child: Text('保存后日均成本', style: TextStyle(fontSize: 13)),
                    ),
                    Text(
                      '¥${bMoney(after)} / 天',
                      key: const Key('cost-daily-preview'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            bField(vendor, '服务商（选填）', maxLength: 160),
            bField(note, '备注（选填）', lines: 3, maxLength: 2000),
            Row(
              children: [
                const Expanded(child: Text('维修凭证')),
                if (receipt != null)
                  TextButton(
                    onPressed: () => setState(() => receipt = null),
                    child: const Text('移除'),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    setState(() => busy = true);
                    try {
                      final m = await pickBelongingImage(context, widget.store);
                      if (m != null && mounted) setState(() => receipt = m);
                    } catch (e) {
                      if (mounted) bToast(context, e);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(receipt == null ? '添加照片' : '更换照片'),
                ),
              ],
            ),
            if (receipt != null)
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => bPush(
                    context,
                    BelongingPhotoPage(widget.store, receipt!),
                  ),
                  child: BelongingImage(
                    widget.store,
                    icon: widget.item.icon,
                    media: receipt,
                    size: 120,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            bCaption('仅记录在物品中，不生成账本流水，也不占用预算。'),
            if (widget.cost != null)
              TextButton(
                onPressed: () async {
                  if (!await bConfirm(
                    context,
                    '删除养护记录？',
                    '删除后将重新计算投入和日均成本，无法撤销。',
                  )) {
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    await widget.store.deleteCost(widget.cost!);
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) bToast(context, e);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
                child: const Text(
                  '删除本条记录',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
