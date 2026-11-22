import 'dart:convert';

import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;
const currencies = {
  'CNY': 2,
  'USD': 2,
  'EUR': 2,
  'HKD': 2,
  'JPY': 0,
  'GBP': 2,
  'SGD': 2,
  'AUD': 2,
  'CAD': 2,
};
const defaultIcons = {
  '餐饮': 'restaurant',
  '交通': 'bus',
  '购物': 'shopping',
  '日用': 'shopping',
  '居住': 'home',
  '娱乐': 'game',
  '健康': 'favorite',
  '学习': 'book',
  '旅行': 'flight',
  '人情': 'gift',
  '工资': 'work',
  '其他': 'category',
};
const defaultCategories = [
  '餐饮',
  '交通',
  '购物',
  '日用',
  '居住',
  '娱乐',
  '健康',
  '学习',
  '旅行',
  '人情',
  '工资',
  '其他',
];
String dateKey(DateTime d) => d.toIso8601String().substring(0, 10);
String bookToday() =>
    dateKey(DateTime.now().toUtc().add(const Duration(hours: 8)));
int unit(String currency) => currencies[currency] == 0 ? 1 : 100;
int parseAmount(String value, String currency, {bool zero = false}) {
  if (!currencies.containsKey(currency)) throw const FormatException('不支持的币种');
  final scale = currencies[currency]!;
  if (!RegExp(scale == 0 ? r'^\d{1,12}$' : r'^\d{1,10}(\.\d{1,2})?$')
      .hasMatch(value.trim())) {
    throw FormatException('$currency 金额最多 $scale 位小数');
  }
  final p = value.trim().split('.');
  final n =
      int.parse(p[0]) * unit(currency) +
      (p.length > 1 ? int.parse(p[1].padRight(scale, '0')) : 0);
  if (n > 999999999999 || (!zero && n == 0)) {
    throw const FormatException('金额需大于零且在有效范围内');
  }
  return n;
}

String formatAmount(num value, String currency) {
  final n = value.toInt(),
      scale = currencies[currency] ?? 2,
      u = unit(currency);
  return '${n < 0 ? '-' : ''}${n.abs() ~/ u}${scale == 0 ? '' : '.${(n.abs() % u).toString().padLeft(scale, '0')}'}';
}

int convertAmount(int minor, String from, String to, String rate) {
  if (!RegExp(r'^\d{1,8}(\.\d{1,12})?$').hasMatch(rate)) {
    throw const FormatException('汇率需为正数，最多 12 位小数');
  }
  final p = rate.split('.'), digits = p.length == 2 ? p[1].length : 0;
  final r = BigInt.parse(p.join()),
      denominator = BigInt.from(10).pow(digits) * BigInt.from(unit(from));
  if (r <= BigInt.zero) throw const FormatException('汇率需大于零');
  final numerator = BigInt.from(minor) * r * BigInt.from(unit(to));
  final result =
      ((numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two))
          .toInt();
  if (result <= 0 || result > 999999999999) {
    throw const FormatException('折合金额超出有效范围');
  }
  return result;
}

class BookPeriod {
  final String start, end;
  const BookPeriod(this.start, this.end);
  String get id => '$start/$end';
  String get last =>
      dateKey(DateTime.parse(end).subtract(const Duration(days: 1)));
  String get label => '$start 至 $last';
  bool contains(String date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) < 0;
}

DateTime boundary(int year, int month, int day) {
  final first = DateTime(year, month),
      last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, day > last ? last : day);
}

BookPeriod periodAt(String date, List<dynamic> rules) {
  final ordered = rules.map((e) => Map<String, dynamic>.from(e)).toList()
    ..sort((a, b) => a['effective'].compareTo(b['effective']));
  final rule = ordered.lastWhere(
    (r) => (r['effective'] as String).compareTo(date) <= 0,
    orElse: () => ordered.first,
  );
  final d = DateTime.parse(date), day = rule['day'] as int;
  var start = boundary(d.year, d.month, day);
  if (dateKey(start).compareTo(date) > 0) {
    start = boundary(d.year, d.month - 1, day);
  }
  var end = boundary(start.year, start.month + 1, day);
  if (dateKey(start).compareTo(rule['effective']) < 0) {
    start = DateTime.parse(rule['effective']);
  }
  for (final next in ordered) {
    if ((next['effective'] as String).compareTo(date) > 0 &&
        next['effective'].compareTo(dateKey(end)) < 0) {
      end = DateTime.parse(next['effective']);
    }
  }
  return BookPeriod(dateKey(start), dateKey(end));
}

// 账本派生索引仅驻留内存；数据修改后由 Store 统一失效。
final _ledgerIndexes = Expando<LedgerIndex>();
void invalidateLedger(Json ledger) => _ledgerIndexes[ledger] = null;
LedgerIndex ledgerIndex(Json ledger) {
  final entries = ledger['entries'] as List;
  final cached = _ledgerIndexes[ledger];
  if (cached != null &&
      identical(cached.source, entries) &&
      cached.count == entries.length) {
    return cached;
  }
  return _ledgerIndexes[ledger] = LedgerIndex(entries);
}

class LedgerIndex {
  final List source;
  final int count;
  final Map<String, Json> byId = {}, bySource = {};
  final Map<String, List<Json>> byCategory = {}, byTag = {};
  final Map<String, int> refunds = {};
  final Map<String, List<Json>> byKind = {};
  final Map<String, List<Json>> periods = {};
  final Map<String, BookPeriod> bookPeriods = {};
  final Map<String, Map<String, int>> totals = {};
  late final List<Json> records;
  List<Json> between(String start, String end) {
    int below(String date) {
      var lo = 0, hi = records.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if ((records[mid]['data']['date'] as String).compareTo(date) >= 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    return records.sublist(below(end), below(start));
  }

  LedgerIndex(this.source) : count = source.length {
    for (final value in source) {
      final e = value as Json;
      if (e['deleted'] == true) continue;
      if (e['id'] is String) byId[e['id']] = e;
      if (e['kind'] == 'entry') {
        final d = e['data'];
        if ((d['source_key'] ?? '') != '') bySource[d['source_key']] = e;
        (byCategory[d['category_id'] ?? ''] ??= []).add(e);
        for (final tag in d['tag_ids'] ?? []) {
          (byTag[tag] ??= []).add(e);
        }
      }
      if (e['kind'] == 'entry' && isRefund(e['data'])) {
        final parent = e['data']['refund_of'] as String;
        refunds[parent] = (refunds[parent] ?? 0) + (e['data']['amount'] as int);
      }
      (byKind[e['kind']] ??= []).add(e);
    }
    for (final kind in ['category', 'tag']) {
      byKind[kind]?.sort(
        (a, b) => (a['data']['order'] as int? ?? 0).compareTo(
          b['data']['order'] as int? ?? 0,
        ),
      );
    }
    records = List<Json>.from(byKind['entry'] ?? [])
      ..sort((a, b) {
        final x = a['data'], y = b['data'];
        final date = (y['date'] as String).compareTo(x['date']);
        return date != 0 ? date : entryTime(y).compareTo(entryTime(x));
      });
  }
}

Json settingsOf(Json ledger) {
  final rows = ledgerIndex(ledger).byKind['ledger_settings'] ?? [];
  return rows.isEmpty
      ? {
          'base_currency': 'CNY',
          'timezone': 'Asia/Shanghai',
          'rules': [
            {'day': 1, 'effective': '1900-01-01'},
          ],
        }
      : Map<String, dynamic>.from(rows.first['data']);
}

List<Json> dictionary(
  Json ledger,
  String kind, {
  bool archived = true,
  String? type,
}) => (ledgerIndex(ledger).byKind[kind] ?? [])
    .where(
      (e) =>
          (archived || e['data']['archived'] != true) &&
          (type == null || e['data']['type'] == type),
    )
    .toList();
String categoryId(String ledger, String type, String name) =>
    const Uuid().v5(Namespace.url.value, 'yousu:$ledger:$type:$name');
Json entity(String id, String kind, Json data, {int revision = 0}) => {
  'id': id,
  'kind': kind,
  'data': data,
  'revision': revision,
  'deleted': false,
  'author': '',
  'author_name': '我',
};
Json migrateLedger(Json original) {
  final ledger = jsonDecode(jsonEncode(original)) as Json;
  final rows = (ledger['entries'] as List).cast<Json>();
  if (rows.any((e) => e['kind'] == 'ledger_settings')) return ledger;
  final rev = ledger['shared'] == true ? 1 : 0;
  final names = <String, String>{
    for (final name in defaultCategories)
      '${name == '工资' ? 'income' : 'expense'}:$name': name,
  };
  for (final e in rows) {
    final d = e['data'];
    if (e['kind'] == 'entry' && d['type'] != 'transfer') {
      names['${d['type']}:${d['category']}'] = d['category'];
    }
    if (e['kind'] == 'budget' && d['category'] != '全部') {
      names['expense:${d['category']}'] = d['category'];
    }
  }
  final additions = <Json>[
    entity('settings', 'ledger_settings', settingsOf(ledger), revision: rev),
  ];
  var order = 0;
  for (final key in names.keys) {
    final type = key.split(':').first, name = names[key]!;
    additions.add(
      entity(categoryId(ledger['id'], type, name), 'category', {
        'name': name,
        'type': type,
        'parent_id': '',
        'icon': defaultIcons[name] ?? 'category',
        'color': '#126C62',
        'order': order++,
        'archived': false,
      }, revision: rev),
    );
  }
  Json upgrade(String kind, Json data) {
    final d = Map<String, dynamic>.from(data);
    if (kind == 'entry') {
      d.addAll({
        'original_currency': 'CNY',
        'original_amount_minor': d['amount'],
        'currency_scale': 2,
        'base_currency': 'CNY',
        'base_amount_minor': d['amount'],
        'fx_rate': '1',
        'fx_rate_date': d['date'],
        'fx_source': 'identity',
        'fx_mode': 'identity',
        'category_id': d['type'] == 'transfer'
            ? ''
            : categoryId(ledger['id'], d['type'], d['category']),
        'tag_ids': <String>[],
        'to_currency': 'CNY',
        'to_amount_minor': d['type'] == 'transfer' ? d['amount'] : 0,
      });
    } else if (kind == 'budget') {
      final p = periodAt('${d['month']}-01', [
        {'day': 1, 'effective': '2000-01-01'},
      ]);
      d.addAll({
        'period_id': p.id,
        'start_date': p.start,
        'end_date': p.end,
        'category_id': d['category'] == '全部'
            ? ''
            : categoryId(ledger['id'], 'expense', d['category']),
        'base_currency': 'CNY',
      });
    }
    return d;
  }

  for (final e in rows) {
    e['data'] = upgrade(e['kind'], e['data']);
  }
  for (final op in (ledger['pending'] as List? ?? [])) {
    op['data'] = upgrade(op['kind'], op['data']);
  }
  ledger['entries'] = [...rows, ...additions];
  return ledger;
}

String categoryName(Json ledger, Json data) =>
    ledgerIndex(ledger).byId[data['category_id']]?['data']['name'] ??
    data['category'] ??
    '其他';

bool isRefund(Json data) => (data['refund_of'] as String? ?? '').isNotEmpty;

/// Refunds are cash inflows. Storage and budget accounting retain their source.
String cashFlowType(Json data) =>
    isRefund(data) ? 'income' : data['type'] as String;
int cashFlowAmount(Json data) =>
    (data['base_amount_minor'] ?? data['amount']) as int;
int signedAmount(Json data) =>
    (isRefund(data) ? -1 : 1) * (data['base_amount_minor'] ?? data['amount'])
        as int;
String entryTime(Json data) => data['time'] ?? '';

class EntryFilter {
  Json? detailRule;
  Set<String> restricted = {}, excludedCategories = {}, excludedTags = {};

  String start = '',
      end = '',
      keyword = '',
      sort = 'date_desc',
      accountSide = 'any';
  Set<String> types = {},
      categories = {},
      tags = {},
      accounts = {},
      members = {},
      currencies = {};
  bool allTags = false, originalAmount = false;
  int? min, max;
  Json toJson() => {
    'start': start,
    'end': end,
    'keyword': keyword,
    'sort': sort,
    'accountSide': accountSide,
    'types': types.toList(),
    'categories': categories.toList(),
    'tags': tags.toList(),
    'accounts': accounts.toList(),
    'members': members.toList(),
    'currencies': currencies.toList(),
    'restricted': restricted.toList(),
    'excludedCategories': excludedCategories.toList(),
    'excludedTags': excludedTags.toList(),
    if (detailRule != null) 'detailRule': detailRule,
    'allTags': allTags,
    'originalAmount': originalAmount,
    'min': min,
    'max': max,
  };
  static EntryFilter fromJson(Json d) => EntryFilter()
    ..detailRule = (d['detailRule'] is Map
        ? Map<String, dynamic>.from(d['detailRule'])
        : null)
    ..start = d['start'] ?? ''
    ..end = d['end'] ?? ''
    ..keyword = d['keyword'] ?? ''
    ..sort = d['sort'] ?? 'date_desc'
    ..accountSide = d['accountSide'] ?? 'any'
    ..types = Set<String>.from(d['types'] ?? [])
    ..categories = Set<String>.from(d['categories'] ?? [])
    ..tags = Set<String>.from(d['tags'] ?? [])
    ..accounts = Set<String>.from(d['accounts'] ?? [])
    ..members = Set<String>.from(d['members'] ?? [])
    ..currencies = Set<String>.from(d['currencies'] ?? [])
    ..restricted = Set<String>.from(d['restricted'] ?? [])
    ..excludedCategories = Set<String>.from(d['excludedCategories'] ?? [])
    ..excludedTags = Set<String>.from(d['excludedTags'] ?? [])
    ..allTags = d['allTags'] ?? false
    ..originalAmount = d['originalAmount'] ?? false
    ..min = d['min']
    ..max = d['max'];
  EntryFilter copy() => EntryFilter()
    ..detailRule = (detailRule == null ? null : {...detailRule!})
    ..restricted = {...restricted}
    ..excludedCategories = {...excludedCategories}
    ..excludedTags = {...excludedTags}
    ..start = start
    ..end = end
    ..keyword = keyword
    ..sort = sort
    ..accountSide = accountSide
    ..types = {...types}
    ..categories = {...categories}
    ..tags = {...tags}
    ..accounts = {...accounts}
    ..members = {...members}
    ..currencies = {...currencies}
    ..allTags = allTags
    ..originalAmount = originalAmount
    ..min = min
    ..max = max;
  Map<String, String> get chips => {
    if (start.isNotEmpty)
      'time':
          '$start 至 ${dateKey(DateTime.parse(end).subtract(const Duration(days: 1)))}',
    if (types.isNotEmpty || restricted.contains('类型'))
      'types': '类型 ${types.length}',
    if (categories.isNotEmpty || restricted.contains('分类'))
      'categories': '分类 ${categories.length}',
    if (tags.isNotEmpty || restricted.contains('标签'))
      'tags': '标签 ${allTags ? '全部' : '任一'} ${tags.length}',
    if (accounts.isNotEmpty || restricted.contains('账户'))
      'accounts': '账户 ${accounts.length}',
    if (members.isNotEmpty || restricted.contains('成员'))
      'members': '成员 ${members.length}',
    if (currencies.isNotEmpty || restricted.contains('币种'))
      'currencies': '币种 ${currencies.join('/')}',
    if (min != null || max != null) 'amount': '金额范围',
    if (keyword.isNotEmpty) 'keyword': keyword,
    if (excludedCategories.isNotEmpty)
      'excludedCategories': '排除分类 ${excludedCategories.length}',
    if (excludedTags.isNotEmpty) 'excludedTags': '排除标签 ${excludedTags.length}',
  };
  void clear(String key) {
    restricted.remove(
      {
        'types': '类型',
        'categories': '分类',
        'tags': '标签',
        'accounts': '账户',
        'members': '成员',
        'currencies': '币种',
      }[key],
    );
    switch (key) {
      case 'excludedCategories':
        excludedCategories.clear();
      case 'excludedTags':
        excludedTags.clear();
      case 'time':
        start = '';
        end = '';
      case 'types':
        types.clear();
      case 'categories':
        categories.clear();
      case 'tags':
        tags.clear();
      case 'accounts':
        accounts.clear();
      case 'members':
        members.clear();
      case 'currencies':
        currencies.clear();
        originalAmount = false;
      case 'amount':
        min = null;
        max = null;
      case 'keyword':
        keyword = '';
    }
  }

  List<Json> apply(Json ledger, List<Json> rows, BookPeriod period) {
    final selected = {...categories}, excluded = {...excludedCategories};
    final baseCurrency = settingsOf(ledger)['base_currency'];
    for (final c in dictionary(ledger, 'category')) {
      if (categories.contains(c['data']['parent_id'])) selected.add(c['id']);
      if (excludedCategories.contains(c['data']['parent_id'])) {
        excluded.add(c['id']);
      }
    }
    bool any(Set<String> values, String? v, String title) =>
        (values.isEmpty && !restricted.contains(title)) || values.contains(v);
    final index = ledgerIndex(ledger), needle = keyword.trim().toLowerCase();
    final candidates = identical(rows, index.records)
        ? index.between(
            start.isEmpty ? period.start : start,
            end.isEmpty ? period.end : end,
          )
        : rows;
    final result = candidates.where((e) {
      final d = e['data'] as Json, date = d['date'] as String;
      if (detailRule != null) {
        final rule = detailRule!,
            c = index.byId[d['category_id']],
            parent = index.byId[c?['data']['parent_id']];
        if (rule['kind'] == 'statistics') {
          if (cashFlowType(d) != rule['type'] ||
              d['base_currency'] != rule['currency']) {
            return false;
          }
          final bucket = rule['bucket'] as String;
          if (rule['group'] == '标签') {
            final tags = List<String>.from(d['tag_ids'] ?? []);
            if (bucket == 'tag:none'
                ? tags.isNotEmpty
                : !tags.contains(bucket.substring(4))) {
              return false;
            }
          } else {
            final selectedCategory = rule['group'] == '一级分类'
                ? (parent ?? c)
                : c;
            final selectedId = selectedCategory?['id'] ?? d['category_id'];
            if (bucket != 'category:$selectedId') return false;
          }
        } else {
          final original = isRefund(d)
              ? (index.byId[d['refund_of']]?['data'] ?? d)
              : d;
          final settings = settingsOf(ledger),
              excluded = List<String>.from(
                settings['budget_excluded_categories'] ?? [],
              ),
              tags = List<String>.from(settings['budget_excluded_tags'] ?? []);
          if (d['type'] != 'expense' ||
              excluded.contains(original['category_id']) ||
              excluded.contains(
                index.byId[original['category_id']]?['data']['parent_id'],
              ) ||
              (original['tag_ids'] as List? ?? []).any(tags.contains)) {
            return false;
          }
          final category = rule['category'];
          if (category != null &&
              original['category_id'] != category &&
              index.byId[original['category_id']]?['data']['parent_id'] !=
                  category) {
            return false;
          }
        }
      }

      final s = start.isEmpty ? period.start : start,
          t = end.isEmpty ? period.end : end;
      if (date.compareTo(s) < 0 ||
          date.compareTo(t) >= 0 ||
          !any(types, cashFlowType(d), '类型') ||
          !any(selected, d['category_id'], '分类') ||
          excluded.contains(d['category_id']) ||
          !any(
            members,
            (d['member'] as String? ?? '').isEmpty
                ? e['author']
                : 'label:${d['member']}',
            '成员',
          ) ||
          !any(currencies, d['original_currency'] ?? 'CNY', '币种')) {
        return false;
      }
      final et = (d['tag_ids'] as List? ?? []).cast<String>();
      if (excludedTags.any(et.contains) ||
          (restricted.contains('标签') && tags.isEmpty)) {
        return false;
      }
      if (restricted.contains('账户') && accounts.isEmpty) return false;
      if (tags.isNotEmpty &&
          !(allTags ? tags.every(et.contains) : tags.any(et.contains))) {
        return false;
      }
      if (accounts.isNotEmpty) {
        final a = accounts.contains(d['account']),
            b = d['type'] == 'transfer' && accounts.contains(d['to_account']);
        if (!(accountSide == 'from'
            ? a
            : accountSide == 'to'
            ? b
            : a || b)) {
          return false;
        }
      }
      if (!originalAmount &&
          (min != null || max != null) &&
          (d['base_currency'] ?? 'CNY') != baseCurrency) {
        return false;
      }
      final n =
          (originalAmount
              ? d['original_amount_minor']
              : d['base_amount_minor']) ??
          d['amount'];
      if ((min != null && n < min) || (max != null && n > max)) return false;
      if (needle.isEmpty) return true;
      final names = et
          .map((id) => index.byId[id]?['data']['name'] ?? '')
          .join(' ');
      return '${categoryName(ledger, d)} $names ${d['note'] ?? ''} ${d['account']} ${d['to_account'] ?? ''} ${d['member'] ?? ''} ${d['merchant'] ?? ''} ${d['project'] ?? ''}'
          .toLowerCase()
          .contains(needle);
    }).toList();
    result.sort((a, b) {
      final x = a['data'], y = b['data'];
      if (sort.startsWith('amount')) {
        final currency = (x['base_currency'] ?? 'CNY').compareTo(
          y['base_currency'] ?? 'CNY',
        ) as int;
        if (currency != 0) return currency;
      }
      var c = sort.startsWith('amount')
          ? (x['amount'] as int).compareTo(y['amount'] as int)
          : ('${x['date']} ${entryTime(x)}').compareTo(
              '${y['date']} ${entryTime(y)}',
            );
      if (sort.endsWith('desc')) c = -c;
      return c == 0 ? (a['id'] as String).compareTo(b['id']) : c;
    });
    return result;
  }
}
