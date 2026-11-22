part of 'store.dart';

extension DictionaryStore on LedgerStore {
  Future<void> deleteDictionary(
    String id,
    String replacementId, {
    Map<String, bool> budgetPolicy = const {},
    Map<String, bool> balancePolicy = const {},
  }) async {
    if (busy || active['role'] != 'owner') {
      throw const FormatException('仅账本所有者可在非同步状态下删除分类和标签');
    }
    if (active['shared'] == true &&
        state['dictionaryDeletionServer'] != endpoint) {
      await checkProtocol();
      if (state['dictionaryDeletionServer'] != endpoint) {
        throw const FormatException('请先升级共享服务以支持分类和标签删除');
      }
    }
    busy = true;
    changed();
    final before = await compute(_cloneBook, state);
    try {
      final book = active;
      final plan = planDictionaryDeletion(
        book,
        id,
        replacementId,
        budgetPolicy: budgetPolicy,
        balancePolicy: balancePolicy,
      );
      if (!budgetPolicy.keys.toSet().containsAll(plan.budgetConflicts) ||
          !balancePolicy.keys.toSet().containsAll(plan.balanceConflicts)) {
        throw const FormatException('请先选择迁移后的预算和结余排除规则');
      }
      final patches = {
        for (final row in plan.changes)
          row['id']: {
            ...row,
            'revision': book['shared'] == true ? (row['revision'] ?? 0) + 1 : 0,
          },
      };
      book['entries'] = [
        for (final row in book['entries']) patches[row['id']] ?? row,
      ];
      book['balance_exclusions'] = plan.balanceExclusions;
      for (final key in [
        'record_templates',
        'recurring_plans',
        'recurring_occurrences',
      ]) {
        _remapDictionaryPreferences(book[key], plan.mapping);
      }
      for (final key in [
        'transactionFilters',
        'transactionViews',
        'statisticsFilters',
        'statisticsViews',
      ]) {
        final saved = state[key]?[book['id']];
        if (saved != null) _remapDictionaryPreferences(saved, plan.mapping);
      }
      if (state['importDrafts'] != null) {
        state['importDrafts'] = List.from(state['importDrafts']);
      }
      for (final draft in state['importDrafts'] as List? ?? []) {
        if (draft['target'] == book['id']) {
          _remapDictionaryPreferences(draft, plan.mapping);
        }
      }
      if (book['shared'] == true) {
        (book['pending'] as List).add({
          '_action': 'dictionary_delete',
          'operation_id': uuid.v4(),
          'id': id,
          'replacement_id': replacementId,
          'expected': plan.expected,
          'budget_policy': budgetPolicy,
        });
      }
      state['dictionaryRevision'] = (state['dictionaryRevision'] ?? 0) + 1;
      invalidateLedger(book);
      await persist();
    } catch (_) {
      state = before;
      rethrow;
    } finally {
      busy = false;
      changed();
    }
  }
}

void _remapDictionaryPreferences(dynamic value, Map<String, String> mapping) {
  if (value is Map) {
    for (final key in value.keys.toList()) {
      final item = value[key];
      if ([
            'categories',
            'excludedCategories',
            'tags',
            'excludedTags',
            'tag_ids',
          ].contains(key) &&
          item is List) {
        value[key] = item
            .map((id) => mapping[id] ?? id)
            .where((id) => id != '')
            .toSet()
            .toList();
      } else if (key == 'category_id' && mapping.containsKey(item)) {
        value[key] = mapping[item];
      } else if (key == 'selected' &&
          item is String &&
          item.startsWith('category:')) {
        final id = item.substring(9);
        if (mapping.containsKey(id)) value[key] = 'category:${mapping[id]}';
      } else {
        _remapDictionaryPreferences(item, mapping);
      }
    }
  } else if (value is List) {
    for (final item in value) {
      _remapDictionaryPreferences(item, mapping);
    }
  }
}
