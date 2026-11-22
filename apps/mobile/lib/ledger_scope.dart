import 'dart:convert';

import 'domain.dart';
import 'balance.dart';
import 'merge_fx.dart' show RefundShare;

/// 分类以收支/父级/名称统一，展示保留来源；仅确切来源相同才去重。
Json composeLedgers(
  List<Json> ledgers,
  Json settings, {
  bool deduplicate = false,
}) {
  final entries = <Json>[],
      dict = <String, Json>{},
      origins = <String, Json>{},
      audit = <String, dynamic>{};
  final seenBase = <String, (String, int)>{};
  final orderedLedgers = [...ledgers];
  if (deduplicate) {
    orderedLedgers.sort(
      (a, b) => (settingsOf(a)['base_currency'] == 'CNY' ? 0 : 1).compareTo(
        settingsOf(b)['base_currency'] == 'CNY' ? 0 : 1,
      ),
    );
  }
  final seen = <String, String>{},
      icons = <String, dynamic>{},
      overrides = <String, dynamic>{};
  for (final l in orderedLedgers) {
    final balance = BalanceRule(l);
    final idx = ledgerIndex(l),
        catIds = <String, String>{},
        tagIds = <String, String>{};
    icons.addAll(Map<String, dynamic>.from(l['custom_icons'] ?? {}));
    String category(Json c) {
      final old = catIds[c['id']];
      if (old != null) return old;
      final d = c['data'], parent = idx.byId[d['parent_id']];
      final pid = parent == null ? '' : category(parent);
      final id = categoryId('scope', d['type'], '$pid/${d['name']}');
      catIds[c['id']] = id;
      dict.putIfAbsent(
        id,
        () => entity(id, 'category', {...d as Json, 'parent_id': pid}),
      );
      return id;
    }

    for (final c in idx.byKind['category'] ?? <Json>[]) {
      category(c);
    }
    for (final t in idx.byKind['tag'] ?? <Json>[]) {
      final id = categoryId('scope', 'tag', t['data']['name']);
      tagIds[t['id']] = id;
      dict.putIfAbsent(id, () => entity(id, 'tag', {...t['data'] as Json}));
    }
    for (final o in (l['icon_overrides'] as Map? ?? {}).entries) {
      final id = catIds[o.key] ?? tagIds[o.key];
      if (id != null) overrides[id] = o.value;
    }
    for (final e in idx.records) {
      final oldAudit = l['import_manifest']?['rows']?[e['id']];
      final origin =
          l['merge_sources']?[e['id']] ?? {'ledger': l['id'], 'entry': e['id']};
      final source =
          ((e['data']['source_key'] as String? ?? '').isNotEmpty
              ? e['data']['source_key']
              : oldAudit?['source_id']) ??
          '${origin['ledger']}/${origin['entry']}';
      if (deduplicate) {
        final d = e['data'];
        final fingerprint = jsonEncode([
          d['date'],
          d['time'],
          d['type'],
          d['original_currency'],
          d['original_amount_minor'],
          isRefund(d),
        ]);
        if (seen.containsKey(source)) {
          if (seen[source] != fingerprint ||
              (seenBase[source]!.$1 == d['base_currency'] &&
                  seenBase[source]!.$2 != d['amount'])) {
            throw const FormatException('相同来源账目存在修改，请核对后合并');
          }
          continue;
        }
        seen[source] = fingerprint;
        seenBase[source] = (d['base_currency'] as String, d['amount'] as int);
      }
      final id = deduplicate
          ? categoryId('merge', 'entry', source)
          : categoryId(l['id'], 'view', e['id']);
      final d = e['data'] as Json;
      entries.add({
        ...e,
        'id': id,
        'source_ledger_id': l['id'],
        if (!deduplicate) 'balance_excluded': !balance.includes(e),
        'source_entry_id': e['id'],
        'source_ledger_name': l['name'],
        if (isRefund(d))
          'refund_basis': {
            'base_currency': idx.byId[d['refund_of']]?['data']['base_currency'],
            'amount': idx.byId[d['refund_of']]?['data']['amount'],
          },
        'data': {
          ...d,
          'category_id': catIds[d['category_id']] ?? '',
          'tag_ids': [
            for (final t in d['tag_ids'] ?? [])
              if (tagIds.containsKey(t)) tagIds[t],
          ],
          if (isRefund(d))
            'refund_of': deduplicate
                ? categoryId(
                    'merge',
                    'entry',
                    ((idx.byId[d['refund_of']]?['data']['source_key']
                                        as String? ??
                                    '')
                                .isNotEmpty
                            ? idx.byId[d['refund_of']]!['data']['source_key']
                            : null) ??
                        l['import_manifest']?['rows']?[d['refund_of']]?['source_id'] ??
                        '${l['merge_sources']?[d['refund_of']]?['ledger'] ?? l['id']}/${l['merge_sources']?[d['refund_of']]?['entry'] ?? d['refund_of']}',
                  )
                : categoryId(l['id'], 'view', d['refund_of']),
        },
      });
      origins[id] = Map<String, dynamic>.from(origin);
      if (oldAudit != null) audit[id] = oldAudit;
    }
  }
  if (deduplicate) {
    final index = {for (final e in entries) e['id']: e};
    final refunds = <String, RefundShare>{};
    for (final e in entries.where((e) => isRefund(e['data']))) {
      final parent = e['data']['refund_of'] as String,
          basis = e['refund_basis'];
      if (index[parent] == null ||
          basis == null ||
          basis['amount'] is! int ||
          basis['base_currency'] != e['data']['base_currency']) {
        throw const FormatException('合并后的退款关系有冲突，请先核对退款');
      }
      (refunds[parent] ??= RefundShare()).add(
        e['data']['amount'],
        basis['amount'],
      );
    }
  }
  return {
    'id':
        'scope:${(ledgers.map((l) => l['id'] as String).toList()..sort()).join('|')}',
    'name': '多账本',
    'balance_has_exclusions':
        !deduplicate && ledgers.any((l) => BalanceRule(l).active),
    'shared': false,
    'role': 'viewer',
    'pending': <dynamic>[],
    'entries': [
      entity('settings', 'ledger_settings', {...settings}),
      ...dict.values,
      ...entries,
    ],
    'merge_sources': origins,
    'import_manifest': {'rows': audit},
    'custom_icons': icons,
    'icon_overrides': overrides,
  };
}
