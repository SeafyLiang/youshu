import 'domain.dart';

List<String> periodDays(BookPeriod p) => [
  for (
    var d = DateTime.parse(p.start);
    d.isBefore(DateTime.parse(p.end));
    d = d.add(const Duration(days: 1))
  )
    dateKey(d),
];

Map<String, int> allocateDays(BookPeriod p, int amount, Map overrides) {
  final days = periodDays(p), fixed = <String, int>{};
  for (final e in overrides.entries) {
    if (!days.contains(e.key) || e.value is! int || e.value < 0) {
      throw const FormatException('每日额度超出账期或无效');
    }
    fixed[e.key as String] = e.value as int;
  }
  final rest = amount - fixed.values.fold<int>(0, (a, b) => a + b),
      free = days.where((d) => !fixed.containsKey(d)).toList();
  if (rest < 0 || (free.isEmpty && rest != 0)) {
    throw const FormatException('月预算不足或所有日期已固定，请调整日额度或重置');
  }
  return {
    for (final d in days)
      d:
          fixed[d] ??
          (rest ~/ free.length +
              (free.indexOf(d) < rest % free.length ? 1 : 0)),
  };
}

class BudgetQuery {
  final Map<String, int> days = {}, categories = {};
  int spent = 0;
  BudgetQuery(Json ledger, BookPeriod period) {
    final index = ledgerIndex(ledger), settings = settingsOf(ledger);
    final excluded = Set<String>.from(
          settings['budget_excluded_categories'] ?? [],
        ),
        tags = Set<String>.from(settings['budget_excluded_tags'] ?? []);
    for (final c in index.byKind['category'] ?? <Json>[]) {
      if (excluded.contains(c['data']['parent_id'])) excluded.add(c['id']);
    }
    for (final e in index.between(period.start, period.end)) {
      final d = e['data'] as Json;
      if (d['type'] != 'expense' || !period.contains(d['date'])) continue;
      final source = isRefund(d)
          ? (index.byId[d['refund_of']]?['data'] as Json? ?? d)
          : d;
      if (excluded.contains(source['category_id']) ||
          (source['tag_ids'] as List? ?? []).any(tags.contains)) {
        continue;
      }
      final n = signedAmount(d), cid = source['category_id'] as String? ?? '';
      spent += n;
      days[d['date']] = (days[d['date']] ?? 0) + n;
      categories[cid] = (categories[cid] ?? 0) + n;
      final parent = index.byId[cid]?['data']['parent_id'];
      if (parent != null && parent != '') {
        categories[parent] = (categories[parent] ?? 0) + n;
      }
    }
  }
}

final _budgetCache = Expando<Map<String, BudgetQuery>>();
BudgetQuery budgetQuery(Json ledger, BookPeriod p) {
  final index = ledgerIndex(ledger);
  final cache = _budgetCache[index] ??= {};
  return cache.putIfAbsent(p.id, () => BudgetQuery(ledger, p));
}
