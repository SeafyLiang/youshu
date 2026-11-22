import 'domain.dart';

String fxCurrency(Json d) =>
    d['fx_mode'] == 'actual' && d['base_currency'] != 'CNY'
    ? d['base_currency']
    : d['original_currency'];
int fxAmount(Json d) => d['fx_mode'] == 'actual' && d['base_currency'] != 'CNY'
    ? d['amount']
    : d['original_amount_minor'];
String fxKey(Json d) => '${fxCurrency(d)}/${d['date']}';

/// Exact cumulative shares allow refunds from different base-currency copies.
class RefundShare {
  BigInt numerator = BigInt.zero, denominator = BigInt.one;
  void add(int amount, int total) {
    if (amount <= 0 || total <= 0) throw const FormatException('退款基准金额无效');
    numerator =
        numerator * BigInt.from(total) + BigInt.from(amount) * denominator;
    denominator *= BigInt.from(total);
    final gcd = numerator.gcd(denominator);
    numerator ~/= gcd;
    denominator ~/= gcd;
    if (numerator > denominator) throw const FormatException('合并后的累计退款超出原消费');
  }

  int rounded(int total) =>
      ((numerator * BigInt.from(total) + denominator ~/ BigInt.two) ~/
              denominator)
          .toInt();
}

/// A detached composed ledger. Source ledgers never change.
Json convertMergedCny((Json, Map<String, Json>) input) {
  final l = input.$1, rates = input.$2, idx = ledgerIndex(l);
  final original = {
    for (final e in idx.records) e['id']: Map<String, dynamic>.from(e['data']),
  };
  final refunds = <String, List<Json>>{};
  for (final e in idx.records) {
    final d = e['data'] as Json;
    if (isRefund(d)) {
      (refunds[d['refund_of']] ??= []).add(e);
      continue;
    }
    if (d['base_currency'] == 'CNY') continue;
    final from = fxCurrency(d), n = fxAmount(d);
    final rate = from == 'CNY'
        ? <String, dynamic>{
            'rate': '1',
            'date': d['date'],
            'source': 'identity',
          }
        : rates[fxKey(d)];
    if (rate == null) throw FormatException('缺少 ${fxKey(d)} 汇率');
    final value = convertAmount(n, from, 'CNY', rate['rate']);
    if (value <= 0) throw const FormatException('折算金额不足一分，请核对');
    (l.putIfAbsent('fx_audit', () => <String, dynamic>{}) as Json)[e['id']] = {
      ...d,
    };
    d.addAll({
      'base_currency': 'CNY',
      'amount': value,
      'base_amount_minor': value,
      'fx_rate': rate['rate'],
      'fx_rate_date': rate['date'],
      'fx_source': rate['source'],
      'fx_mode': from == 'CNY' && d['original_currency'] == 'CNY'
          ? 'identity'
          : from != d['original_currency']
          ? 'actual'
          : rate['source'] == 'manual'
          ? 'manual'
          : 'auto',
    });
  }
  for (final group in refunds.entries) {
    final parent = idx.byId[group.key]!['data'] as Json,
        oldParent = original[group.key]!;
    final rows = group.value
      ..sort(
        (a, b) => '${a['data']['date']}/${a['id']}'.compareTo(
          '${b['data']['date']}/${b['id']}',
        ),
      );
    final share = RefundShare();
    var newSum = 0;
    for (final e in rows) {
      final d = e['data'] as Json;
      final basis = e['refund_basis'] as Map? ?? oldParent;
      if (basis['base_currency'] != d['base_currency']) {
        throw const FormatException('退款币种基准不一致');
      }
      share.add(d['amount'], basis['amount']);
      final value = share.rounded(parent['amount']) - newSum;
      newSum += value;
      if (value <= 0 ||
          (d['base_currency'] == 'CNY' && value != d['amount']) ||
          (d['original_currency'] == 'CNY' &&
              value != d['original_amount_minor'])) {
        throw const FormatException('退款人民币实退额或舍入差额需核对');
      }
      if (d['base_currency'] == 'CNY') continue;
      (l.putIfAbsent('fx_audit', () => <String, dynamic>{}) as Json)[e['id']] =
          {...d};
      d.addAll({
        'base_currency': 'CNY',
        'amount': value,
        'base_amount_minor': value,
        'fx_rate': parent['fx_rate'],
        'fx_rate_date': parent['fx_rate_date'],
        'fx_source': 'refund-proportion',
        'fx_mode': 'actual',
      });
    }
    if (newSum > parent['amount']) throw const FormatException('人民币退款累计超出原消费');
  }
  final settings = (l['entries'] as List).firstWhere(
    (e) => e['kind'] == 'ledger_settings',
  )['data'];
  settings['base_currency'] = 'CNY';
  settings['budget_excluded_categories'] = <String>[];
  settings['budget_excluded_tags'] = <String>[];
  invalidateLedger(l);
  return l;
}
