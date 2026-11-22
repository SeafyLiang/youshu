import 'domain.dart';

class DictionaryDeletion {
  final Map<String, String> mapping;
  final List<Json> changes;
  final Map<String, int> expected;
  final Set<String> budgetConflicts, balanceConflicts;
  final Json balanceExclusions;
  final List<String> moves, budgets;
  final int entryCount;
  DictionaryDeletion(
    this.mapping,
    this.changes,
    this.expected,
    this.budgetConflicts,
    this.balanceConflicts,
    this.balanceExclusions,
    this.moves,
    this.budgets,
    this.entryCount,
  );
}

/// Build the complete change before touching state. The server applies the same
/// mapping under a write transaction and compares the affected revision set.
DictionaryDeletion planDictionaryDeletion(
  Json ledger,
  String id,
  String replacementId, {
  Map<String, bool> budgetPolicy = const {},
  Map<String, bool> balancePolicy = const {},
}) {
  final rows = (ledger['entries'] as List).cast<Json>();
  final byId = {for (final row in rows) row['id'] as String: row};
  final source = byId[id];
  if (source == null ||
      source['deleted'] == true ||
      !['category', 'tag'].contains(source['kind'])) {
    throw const FormatException('分类或标签已变化，请重新打开');
  }
  final kind = source['kind'], target = byId[replacementId];
  if (replacementId.isNotEmpty &&
      (target == null ||
          target['deleted'] == true ||
          target['kind'] != kind ||
          id == replacementId ||
          target['data']['archived'] == true ||
          (kind == 'category' &&
              target['data']['type'] != source['data']['type']))) {
    throw const FormatException('请选择同账本中可用的同类型替代项');
  }
  final expected = <String, int>{};
  void guard(Json row) => expected[row['id']] = row['revision'] ?? 0;
  guard(source);
  if (target != null) guard(target);
  final changes = <String, Json>{},
      mapping = <String, String>{id: replacementId};
  void patch(Json row, Json data, {bool? deleted}) {
    guard(row);
    changes[row['id']] = {
      ...row,
      'data': data,
      'deleted': deleted ?? row['deleted'] ?? false,
    };
  }

  final moves = <String>[], budgets = <String>[];
  final children = rows
      .where(
        (r) =>
            r['kind'] == 'category' &&
            r['deleted'] != true &&
            r['data']['parent_id'] == id,
      )
      .toList();
  if (kind == 'category' && children.isNotEmpty) {
    if (target == null || target['data']['parent_id'] != '') {
      throw const FormatException('带子分类的分类需选择另一个一级分类');
    }
    final siblings =
        rows
            .where(
              (r) =>
                  r['kind'] == 'category' &&
                  r['deleted'] != true &&
                  r['data']['parent_id'] == replacementId,
            )
            .toList()
          ..sort((a, b) => (a['id'] as String).compareTo(b['id']));
    for (final child in [...children, ...siblings]) {
      guard(child);
    }
    for (final child in children) {
      final same = siblings
          .where((r) => r['data']['name'] == child['data']['name'])
          .firstOrNull;
      if (same == null) {
        patch(child, {...child['data'] as Json, 'parent_id': replacementId});
        moves.add('${child['data']['name']} → ${target['data']['name']}');
      } else {
        mapping[child['id']] = same['id'];
        moves.add(
          '${child['data']['name']} → ${target['data']['name']} / ${same['data']['name']}（合并）',
        );
      }
    }
  }
  var entryCount = 0;
  for (final row in rows) {
    if (row['data']['purged'] == true) continue;
    final data = row['data'] as Json;
    if (row['kind'] == 'entry') {
      final hit = kind == 'category'
          ? mapping.containsKey(data['category_id'])
          : (data['tag_ids'] as List? ?? []).any(mapping.containsKey);
      if (!hit) continue;
      if (target == null) throw const FormatException('已有流水引用，请选择替代项');
      final next = {...data};
      if (kind == 'category') {
        next['category_id'] = mapping[data['category_id']];
        next['category'] = byId[next['category_id']]!['data']['name'];
      } else {
        next['tag_ids'] = (data['tag_ids'] as List)
            .map((t) => mapping[t] ?? t)
            .toSet()
            .toList();
      }
      patch(row, next);
      entryCount++;
    } else if (row['kind'] == 'budget' &&
        kind == 'category' &&
        mapping.containsKey(data['category_id'])) {
      if (target == null) throw const FormatException('已有预算引用，请选择替代分类');
      final cid = mapping[data['category_id']]!;
      patch(row, {
        ...data,
        'category_id': cid,
        'category': byId[cid]!['data']['name'],
      });
    }
  }
  // Colliding category budgets become a single visible allocation.
  final groups = <String, List<Json>>{};
  for (final row in rows.where(
    (r) => r['kind'] == 'budget' && r['deleted'] != true,
  )) {
    final next = changes[row['id']] ?? row, data = next['data'];
    if (!mapping.values.contains(data['category_id']) ||
        data['category_id'] == '') {
      continue;
    }
    (groups['${data['period_id']}:${data['category_id']}'] ??= []).add(next);
  }
  for (final group in groups.values) {
    if (!group.any((r) => changes.containsKey(r['id']))) continue;
    group.sort((a, b) => (a['id'] as String).compareTo(b['id']));
    final keep =
        group
            .where(
              (r) =>
                  !mapping.containsKey(byId[r['id']]!['data']['category_id']),
            )
            .firstOrNull ??
        group.first;
    final amount = group.fold<int>(0, (n, r) => n + r['data']['amount'] as int);
    if (amount > 999999999999) throw const FormatException('合并预算超出上限，请先调整额度');
    patch(byId[keep['id']]!, {...keep['data'] as Json, 'amount': amount});
    for (final row in group.where((r) => r['id'] != keep['id'])) {
      patch(byId[row['id']]!, row['data'] as Json, deleted: true);
    }
    if (group.length > 1) {
      budgets.add(
        '${keep['data']['start_date']} · ${keep['data']['category']} → ${formatAmount(amount, settingsOf(ledger)['base_currency'])}',
      );
    }
  }
  final settings = rows.firstWhere(
    (r) => r['kind'] == 'ledger_settings' && r['deleted'] != true,
  );
  guard(settings);
  final budgetConflicts = <String>{}, balanceConflicts = <String>{};
  List<String> remap(
    List original,
    Map<String, bool> policy,
    Set<String> conflicts,
  ) {
    final values = original.cast<String>().toSet();
    for (final pair in mapping.entries) {
      if (pair.value.isEmpty && values.contains(pair.key)) {
        throw const FormatException('排除规则正在使用，请选择替代项');
      }
      if (pair.value.isNotEmpty &&
          values.contains(pair.key) != values.contains(pair.value)) {
        conflicts.add(pair.value);
      }
    }
    final result = values
        .map((v) => mapping[v] ?? v)
        .where((v) => v.isNotEmpty)
        .toSet();
    for (final pair in policy.entries) {
      if (mapping.values.contains(pair.key)) {
        pair.value ? result.add(pair.key) : result.remove(pair.key);
      }
    }
    return result.toList();
  }

  final field = kind == 'category' ? 'categories' : 'tags';
  final settingsKey = 'budget_excluded_$field';
  final nextSettings = {...settings['data'] as Json};
  final excluded = remap(
    List.from(nextSettings[settingsKey] ?? []),
    budgetPolicy,
    budgetConflicts,
  );
  if (excluded
          .toSet()
          .difference(Set.from(nextSettings[settingsKey] ?? []))
          .isNotEmpty ||
      Set.from(nextSettings[settingsKey] ?? [])
          .difference(excluded.toSet())
          .isNotEmpty) {
    nextSettings[settingsKey] = excluded;
    patch(settings, nextSettings);
  }
  final balance = <String, dynamic>{
    'categories': <String>[],
    'tags': <String>[],
    ...?ledger['balance_exclusions'] as Map<String, dynamic>?,
  };
  balance[field] = remap(
    List.from(balance[field]),
    balancePolicy,
    balanceConflicts,
  );
  for (final old in mapping.keys) {
    patch(
      byId[old]!,
      Map<String, dynamic>.from(byId[old]!['data']),
      deleted: true,
    );
  }
  return DictionaryDeletion(
    mapping,
    changes.values.toList(),
    expected,
    budgetConflicts,
    balanceConflicts,
    balance,
    moves,
    budgets,
    entryCount,
  );
}
