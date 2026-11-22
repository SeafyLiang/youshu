import 'domain.dart';

/// Personal display exclusions live on the book, independent of shared budgets.
class BalanceRule {
  final Json ledger;
  late final index = ledgerIndex(ledger);
  late final categories = Set<String>.from(
    ledger['balance_exclusions']?['categories'] ?? [],
  );
  late final tags = Set<String>.from(
    ledger['balance_exclusions']?['tags'] ?? [],
  );
  BalanceRule(this.ledger);
  bool get active =>
      categories.isNotEmpty ||
      tags.isNotEmpty ||
      ledger['balance_has_exclusions'] == true;
  bool includes(Json entry) {
    if (entry['balance_excluded'] is bool) {
      return entry['balance_excluded'] != true;
    }
    final data = entry['data'] as Json;
    final source = isRefund(data)
        ? (index.byId[data['refund_of']]?['data'] as Json? ?? data)
        : data;
    return !categories.contains(source['category_id']) &&
        !categories.contains(
          index.byId[source['category_id']]?['data']['parent_id'],
        ) &&
        !(source['tag_ids'] as List? ?? []).any(tags.contains);
  }

  int contribution(Json entry) {
    final data = entry['data'] as Json;
    if (!includes(entry) || data['type'] == 'transfer') return 0;
    return (data['type'] == 'income' ? 1 : -1) * signedAmount(data);
  }

  int total(Iterable<Json> rows) =>
      rows.fold(0, (sum, e) => sum + contribution(e));
}
