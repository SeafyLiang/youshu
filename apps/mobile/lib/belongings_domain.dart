import 'belongings_links.dart';

import 'dart:math' as math;

typedef BJson = Map<String, dynamic>;
const belongingIcons = <String, String>{
  'laptop': '电脑',
  'mobile_phone': '手机',
  'headphone': '耳机',
  'camera': '相机',
  'watch': '手表',
  'handbag': '包袋',
  'running_shoe': '鞋履',
  'bicycle': '单车',
  'couch_and_lamp': '家具',
  'television': '电视',
  'video_game': '游戏机',
  'ring': '首饰',
  'backpack': '背包',
  'lotion_bottle': '个护',
  'electric_plug': '配件',
  'keyboard': '键盘',
  'motor_scooter': '电动车',
  'washing_machine': '洗衣机',
};
const belongingCategories = ['数码', '出行', '家电', '家居', '穿搭', '运动', '个护', '其他'];
const belongingStates = ['在用', '闲置', '已退役', '已售出'];
const belongingCostKinds = ['维修', '保养', '配件'];
const maxBelongingMoney = 99999999999;
String bDay([DateTime? value]) {
  final d = value ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

DateTime bDate(String value) {
  final d = DateTime.tryParse('${value}T00:00:00Z');
  if (d == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      bDay(d) != value) {
    throw const FormatException('日期无效');
  }
  return d;
}

int bCents(String value) {
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value.trim())) {
    throw const FormatException('请输入非负金额，最多两位小数');
  }
  final p = value.trim().split('.');
  final whole = int.tryParse(p.first);
  if (whole == null || whole > maxBelongingMoney ~/ 100) {
    throw const FormatException('金额过大');
  }
  final n =
      whole * 100 + int.parse(p.length == 1 ? '0' : p.last.padRight(2, '0'));
  if (n > maxBelongingMoney) throw const FormatException('金额过大');
  return n;
}

String bMoney(num cents) => (cents / 100)
    .toStringAsFixed(2)
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},');
String bDuration(int days) => days <= 365
    ? '$days 天'
    : '${days ~/ 365}年${days % 365 == 0 ? '' : '${days % 365}天'}';

bool validMediaId(String s) => RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(s);
void bText(dynamic v, String label, {bool required = false, int max = 500}) {
  if (v is! String || v.length > max || (required && v.trim().isEmpty)) {
    throw FormatException('$label无效');
  }
}

void bAmount(dynamic n) {
  if (n is! int || n < 0 || n > maxBelongingMoney) {
    throw const FormatException('金额无效');
  }
}

class Belonging {
  final BJson data;
  Belonging(BJson json) : data = Map.unmodifiable(json);
  String get id => data['id'];
  int get revision => data['revision'] ?? 0;
  String get name => data['name'];
  String get purchase => data['purchase'];
  int get price => data['price'];
  String get category => data['category'];
  String get icon => data['icon'];
  String get state => data['state'];
  String get note => data['note'] ?? '';
  String? get cover => data['cover'];
  String? get coverSource => data['coverSource'];
  BJson? get coverEdit => data['coverEdit'] == null
      ? null
      : Map<String, dynamic>.from(data['coverEdit']);
  String? get purchaseUrl => data['purchaseUrl'];
  List<String> get photos => List<String>.from(data['photos'] ?? []);
  String? get expiry => data['expiry'];
  String? get warranty => data['warranty'];
  String? get end => data['end'];
  int get recovery => data['recovery'] ?? 0;
  int get remind => data['remind'] ?? 7;
  int? get target => data['target'];
  bool get held => state == '在用' || state == '闲置';
  Iterable<String> get media => {?cover, ?coverSource, ...photos};
  int days([String? now]) => math.max(
    1,
    bDate(end ?? now ?? bDay()).difference(bDate(purchase)).inDays + 1,
  );
  void validate({String? now}) {
    final today = now ?? bDay();
    bText(id, '物品编号', required: true, max: 120);
    bText(name, '名称', required: true, max: 80);
    bText(note, '备注', max: 2000);
    bAmount(price);
    bDate(purchase);
    if (purchase.compareTo(today) > 0) {
      throw const FormatException('购买日期不能晚于今天');
    }
    if (!belongingCategories.contains(category) ||
        !belongingIcons.containsKey(icon) ||
        !belongingStates.contains(state)) {
      throw const FormatException('物品分类、封面或状态无效');
    }
    if (data['currency'] != 'CNY') throw const FormatException('物品暂使用人民币');
    if (![-1, 1, 7, 30].contains(remind)) throw const FormatException('提醒设置无效');
    for (final d in [expiry, warranty]) {
      if (d != null) {
        bDate(d);
        if (d.compareTo(purchase) < 0) {
          throw const FormatException('到期日期不能早于购买日');
        }
      }
    }
    if (!held) {
      if (end == null) throw const FormatException('请选择结束日期');
      bDate(end!);
      if (end!.compareTo(purchase) < 0 || end!.compareTo(today) > 0) {
        throw const FormatException('结束日期须在购买日与今天之间');
      }
    } else if (end != null || recovery != 0) {
      throw const FormatException('持有物品不能含结束日或回收金额');
    }
    bAmount(recovery);
    if (state != '已售出' && recovery != 0) {
      throw const FormatException('仅售出物品可填写回收金额');
    }
    if (target != null) {
      bAmount(target);
      if (target! == 0) throw const FormatException('目标日均须大于 0');
    }
    if (purchaseUrl != null && !validPurchaseUrl(purchaseUrl!)) {
      throw const FormatException('请输入有效的 HTTP 或 HTTPS 购买链接');
    }
    if (coverEdit != null) {
      final rect = coverEdit!['rect'];
      if (cover == null ||
          coverSource == null ||
          rect is! List ||
          rect.length != 4 ||
          rect.any((v) => v is! num || !v.isFinite || v < 0 || v > 1) ||
          rect[2] <= 0 ||
          rect[3] <= 0 ||
          rect[0] + rect[2] > 1.000001 ||
          rect[1] + rect[3] > 1.000001 ||
          coverEdit!['subject'] is! bool) {
        throw const FormatException('图片裁剪参数无效');
      }
    }
    if (photos.length > 5 || media.any((m) => !validMediaId(m))) {
      throw const FormatException('图片引用无效');
    }
  }
}

class BelongingCost {
  final BJson data;
  BelongingCost(BJson json) : data = Map.unmodifiable(json);
  String get id => data['id'];
  String get itemId => data['itemId'];
  int get revision => data['revision'] ?? 0;
  int get amount => data['amount'];
  String get title => data['title'];
  String get date => data['date'];
  String get kind => data['kind'];
  String get vendor => data['vendor'] ?? '';
  String get note => data['note'] ?? '';
  String? get receipt => data['receipt'];
  void validate(Belonging item, {String? now}) {
    bText(id, '费用编号', required: true, max: 120);
    bText(title, '维修项目', required: true, max: 120);
    bText(vendor, '服务商', max: 160);
    bText(note, '备注', max: 2000);
    bAmount(amount);
    bDate(date);
    if (itemId != item.id || !belongingCostKinds.contains(kind)) {
      throw const FormatException('费用所属物品或类型无效');
    }
    if (date.compareTo(item.purchase) < 0 ||
        date.compareTo(item.end ?? now ?? bDay()) > 0) {
      throw const FormatException('维修日期须在购买日与今天（或结束日）之间');
    }
    if (receipt != null && !validMediaId(receipt!)) {
      throw const FormatException('凭证引用无效');
    }
  }
}

int maintenanceCost(Iterable<BelongingCost> costs) =>
    costs.fold(0, (s, c) => s + c.amount);
int investedCost(Belonging item, Iterable<BelongingCost> costs) =>
    item.price + maintenanceCost(costs);
double dailyCost(
  Belonging item,
  Iterable<BelongingCost> costs, {
  String? now,
}) => math.max(0, investedCost(item, costs) - item.recovery) / item.days(now);
List<(String, double)> belongingCurve(
  Belonging item,
  List<BelongingCost> costs, {
  String? now,
}) {
  final n = item.days(now),
      start = math.max(1, n - 179),
      out = <(String, double)>[];
  for (var d = start; d <= n; d++) {
    final day = bDay(bDate(item.purchase).add(Duration(days: d - 1)));
    final total =
        item.price +
        maintenanceCost(costs.where((c) => c.date.compareTo(day) <= 0));
    out.add((
      day,
      math.max(0, total - (!item.held && d == n ? item.recovery : 0)) / d,
    ));
  }
  return out;
}

List<BJson> belongingReminderDays(Iterable<Belonging> items, String today) {
  final grouped = <String, List<String>>{};
  for (final i in items.where((i) => i.held && i.remind >= 0)) {
    for (final pair in [(i.expiry, '有效期'), (i.warranty, '保修')]) {
      if (pair.$1 == null) continue;
      for (final delta in [i.remind, 0]) {
        final day = bDay(bDate(pair.$1!).subtract(Duration(days: delta)));
        if (day.compareTo(today) < 0) continue;
        (grouped[day] ??= []).add(
          '${i.name}${pair.$2}${delta == 0 ? '今天到期' : '将在 $delta 天后到期'}',
        );
      }
    }
  }
  final keys = grouped.keys.toList()..sort();
  return keys
      .take(6)
      .map(
        (d) => <String, dynamic>{
          'day': d,
          'names': grouped[d]!.take(3).join('；'),
          'count': grouped[d]!.length,
        },
      )
      .toList();
}
