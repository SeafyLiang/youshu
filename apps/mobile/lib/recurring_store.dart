part of 'store.dart';

extension RecurringStore on LedgerStore {
  List<Json> get recordTemplates =>
      List<Json>.from(localItems(active, 'record_templates'))..sort(
        (a, b) => (a['order'] as int? ?? 0).compareTo(b['order'] as int? ?? 0),
      );
  List<Json> get recurringPlans => localItems(active, 'recurring_plans');
  List<Json> get recurringPending => pendingOccurrences(active);

  void _schedulePermission() {
    if (!canEdit) throw const FormatException('当前账本只读');
  }

  void validateScheduleFields(Json fields) {
    _schedulePermission();
    final cat = choices(
      'category',
      type: fields['type'],
    ).where((c) => c['id'] == fields['category_id']);
    if (cat.isEmpty) throw const FormatException('模板分类已停用或删除，请重新选择');
    final tags = choices('tag').map((t) => t['id']).toSet();
    if (!tags.containsAll(List<String>.from(fields['tag_ids'] ?? []))) {
      throw const FormatException('模板标签已停用或删除，请重新选择');
    }
  }

  Future<void> saveRecordTemplate(
    Json input, {
    bool replaceName = false,
  }) async {
    _schedulePermission();
    final item = jsonDecode(jsonEncode(input)) as Json;
    item['name'] = (item['name'] as String).trim();
    item['fields'] = templateFields(item['fields']);
    validateTemplate(item);
    validateScheduleFields(item['fields']);
    await atomicBook(() async {
      final list = recordTemplates;
      final same = list
          .where((t) => t['id'] != item['id'] && t['name'] == item['name'])
          .firstOrNull;
      if (same != null && !replaceName) throw const FormatException('同名模板已存在');
      final originalId = item['id'];
      if (same != null) item['id'] = same['id'];
      list.removeWhere((t) => t['id'] == item['id'] || t['id'] == originalId);
      list.add(item);
      active['record_templates'] = list;
    });
  }

  Future<void> removeRecordTemplate(String id) async {
    _schedulePermission();
    await atomicBook(() async {
      active['record_templates'] = recordTemplates
          .where((t) => t['id'] != id)
          .toList();
    });
  }

  Future<void> reorderRecordTemplates(List<String> ids) async {
    _schedulePermission();
    await atomicBook(() async {
      final list = recordTemplates;
      if (ids.toSet().length != list.length ||
          !ids.toSet().containsAll(list.map((e) => e['id']))) {
        throw const FormatException('模板列表已变化，请重试');
      }
      active['record_templates'] = [
        for (final t in list) {...t, 'order': ids.indexOf(t['id'])},
      ];
    });
  }

  Future<void> saveRecurringPlan(
    Json input, {
    bool updatePending = false,
  }) async {
    _schedulePermission();
    final plan = jsonDecode(jsonEncode(input)) as Json;
    plan['name'] = (plan['name'] as String).trim();
    plan['fields'] = templateFields(plan['fields']);
    validateRecurringPlan(plan);
    if (plan['end_date'] != null && plan['total'] == null) {
      plan['total'] = contractLastPeriod(plan);
    }
    validateScheduleFields(plan['fields']);
    if (plan['extra'] != null) {
      validateScheduleFields({
        ...plan['fields'] as Json,
        'category_id': plan['extra']['category_id'],
      });
    }
    await atomicBook(() async {
      final plans = List<Json>.from(recurringPlans);
      final old = plans.where((p) => p['id'] == plan['id']).firstOrNull;
      if (old != null &&
          plan['revision'] != null &&
          old['revision'] != plan['revision']) {
        throw const FormatException('计划已变化，请重新打开后编辑');
      }
      final occurrences = localItems(active, 'recurring_occurrences');
      final hasHistory = occurrences.any((o) => o['plan_id'] == plan['id']);
      if (old != null && hasHistory) {
        if (old['start'] != plan['start']) {
          throw const FormatException('已有期次不能改变接入期号；请从下一期新建接续计划');
        }
        final structureChanged = [
          'anchor',
          'unit',
          'interval',
          'total',
          'coverage',
          'end_date',
          'extra',
        ].any((key) => jsonEncode(old[key]) != jsonEncode(plan[key]));
        final pending = occurrences
            .where(
              (o) => o['plan_id'] == plan['id'] && o['status'] == 'pending',
            )
            .toList();
        if (structureChanged && pending.isNotEmpty && !updatePending) {
          throw const FormatException('日期或周期已改变，请勾选同时更新待确认项，核对后保存');
        }
        final processed = occurrences
            .where(
              (o) => o['plan_id'] == plan['id'] && o['status'] != 'pending',
            )
            .toList();
        final lastProcessed = processed.fold<int>(
          0,
          (n, o) => o['period'] > n ? o['period'] as int : n,
        );
        if (plan['total'] != null && plan['total'] < lastProcessed) {
          throw const FormatException('总期数不能少于已处理期号');
        }
        final next = recurringOccurrence(plan, lastProcessed + 1);
        if (structureChanged &&
            next != null &&
            processed.any(
              (o) =>
                  (o['due'] as String).compareTo(next['due']) >= 0 ||
                  (o['coverage_end'] != null &&
                      next['coverage_start'] != null &&
                      (o['coverage_end'] as String).compareTo(
                            next['coverage_start'],
                          ) >=
                          0),
            )) {
          throw const FormatException('新计划与已处理日期或租期重叠，请调整首次日期');
        }
        if (structureChanged) {
          for (final item in pending) {
            final replacement = recurringOccurrence(plan, item['period']);
            if (replacement == null) continue;
            final overlaps = processed.any(
              (done) =>
                  done['due'] == replacement['due'] ||
                  (done['coverage_start'] != null &&
                      replacement['coverage_start'] != null &&
                      (replacement['coverage_start'] as String).compareTo(
                            done['coverage_end'],
                          ) <=
                          0 &&
                      (replacement['coverage_end'] as String).compareTo(
                            done['coverage_start'],
                          ) >=
                          0),
            );
            if (overlaps) throw const FormatException('修改后的待确认项与已处理日期或租期重叠');
          }
        }
        plan['cursor'] = structureChanged ? plan['start'] : old['cursor'];
        plan['status'] = old['status'];
      }
      plan['revision'] = (old?['revision'] as int? ?? 0) + 1;
      plans.removeWhere((p) => p['id'] == plan['id']);
      plans.add(plan);
      active['recurring_plans'] = plans;
      if (updatePending) {
        active['recurring_occurrences'] = [
          for (final o in occurrences)
            if (o['plan_id'] == plan['id'] && o['status'] == 'pending')
              recurringOccurrence(plan, o['period']) ??
                  {...o, 'status': 'cancelled'}
            else
              o,
        ];
      }
      generateRecurring(active, today());
    });
  }

  Future<void> maintainRecurring({String? day}) async {
    if (busy) return;
    final eligible = ledgers
        .where(
          (l) =>
              l['role'] != 'viewer' &&
              localItems(
                l,
                'recurring_plans',
              ).any((p) => p['status'] == 'active'),
        )
        .toList();
    if (eligible.isEmpty) return;
    busy = true;
    final before = await compute(_cloneBook, state);
    try {
      var changed = false;
      for (final book in eligible) {
        changed = generateRecurring(book, day ?? today()) || changed;
      }
      if (changed) await persist();
    } catch (_) {
      state = before;
      rethrow;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> setRecurringStatus(
    String id,
    String status, {
    bool skipMissed = false,
    bool cancelPending = false,
  }) async {
    _schedulePermission();
    if (!['active', 'paused', 'ended'].contains(status)) {
      throw const FormatException('未知周期状态');
    }
    await atomicBook(() async {
      final plan = recurringPlans.firstWhere((p) => p['id'] == id);
      if (plan['status'] == 'ended') throw const FormatException('已结束计划请新建接续');
      plan['status'] = status;
      if (status == 'ended' && cancelPending) {
        for (final o in localItems(active, 'recurring_occurrences')) {
          if (o['plan_id'] == id && o['status'] == 'pending') {
            o['status'] = 'cancelled';
          }
        }
      }
      if (status == 'active') {
        generateRecurring(active, today(), onlyPlan: id, skipDue: skipMissed);
      }
    });
  }

  Future<void> skipRecurring(String id) async {
    _schedulePermission();
    await atomicBook(() async {
      final o = localItems(
        active,
        'recurring_occurrences',
      ).firstWhere((o) => o['id'] == id);
      if (o['status'] != 'pending') return;
      o['status'] = 'skipped';
      _finishRecurring(o['plan_id']);
    });
  }

  void _finishRecurring(String id) {
    final p = recurringPlans.firstWhere((p) => p['id'] == id);
    final rows = localItems(
      active,
      'recurring_occurrences',
    ).where((o) => o['plan_id'] == id).toList();
    if (rows.any((o) => o['status'] == 'pending')) return;
    final maxPeriod = rows.fold<int>(
      0,
      (n, o) => (o['period'] as int) > n ? o['period'] as int : n,
    );
    if (maxPeriod > 0 && recurringOccurrence(p, maxPeriod + 1) == null) {
      p['status'] = 'ended';
    }
  }

  Future<Json> schedulePricing(
    Json fields,
    String date, {
    String? manualRate,
    int? actual,
  }) async {
    final currency = fields['original_currency'] as String;
    final n = fields['original_amount_minor'] as int;
    final base = this.currency;
    Json quote = {
      'rate': '1',
      'date': date,
      'source': 'identity',
      'cached': false,
    };
    if (currency != base) {
      quote = actual != null || manualRate != null
          ? {
              'rate': manualRate ?? '1',
              'date': date,
              'source': 'user',
              'cached': false,
            }
          : await exchange(currency, base, date);
    }
    final converted = actual ?? convertAmount(n, currency, base, quote['rate']);
    if (converted <= 0 || converted > 999999999999) {
      throw const FormatException('折合金额无效');
    }
    return {
      ...fields,
      'amount': converted,
      'base_amount_minor': converted,
      'base_currency': base,
      'currency_scale': currencies[currency],
      'fx_rate': quote['rate'],
      'fx_rate_date': quote['date'],
      'fx_source': quote['source'],
      'fx_mode': currency == base
          ? 'identity'
          : actual != null
          ? 'actual'
          : manualRate != null
          ? 'manual'
          : quote['cached'] == true
          ? 'cached'
          : 'auto',
      'date': date,
      'time': DateTime.now().toIso8601String().substring(11, 16),
      'category':
          ledgerIndex(active).byId[fields['category_id']]?['data']['name'] ??
          '',
      'refund_of': '',
      'to_account': '',
      'to_currency': base,
      'to_amount_minor': 0,
    };
  }

  Future<void> confirmRecurring(
    String id,
    Json primary, {
    Json? extra,
    String? existingId,
    String? existingExtraId,
    bool updateFuture = false,
    bool updatePending = false,
  }) async {
    _schedulePermission();
    await atomicBook(() async {
      final o = localItems(
        active,
        'recurring_occurrences',
      ).firstWhere((o) => o['id'] == id);
      if (o['status'] == 'confirmed') {
        return; // Safe retry after a successful commit.
      }
      if (o['status'] != 'pending') throw const FormatException('本期已处理');
      if ((o['extra'] != null) != (extra != null)) {
        throw const FormatException('请同时核对本期附加项目');
      }
      final ids = <String>[];
      Future<void> saveLine(Json data, String suffix, String? existing) async {
        validateScheduleFields(data);
        calendarDate(data['date']);
        if (data['original_amount_minor'] is! int ||
            data['original_amount_minor'] <= 0 ||
            data['amount'] is! int ||
            data['amount'] <= 0 ||
            data['base_amount_minor'] != data['amount'] ||
            data['base_currency'] != currency) {
          throw const FormatException('请核对实际金额');
        }
        if (data['type'] != o['fields']['type'] ||
            data['original_currency'] != o['fields']['original_currency']) {
          throw const FormatException('收支方向或币种已变化');
        }
        if (data['amount'] > 999999999999 ||
            data['original_amount_minor'] > 999999999999 ||
            (data['fx_mode'] != 'actual' &&
                convertAmount(
                      data['original_amount_minor'],
                      data['original_currency'],
                      currency,
                      data['fx_rate'],
                    ) !=
                    data['amount'])) {
          throw const FormatException('汇率快照与实际金额不一致');
        }
        if (existing != null) {
          final entry = records(active)
              .where((e) => e['id'] == existing)
              .firstOrNull;
          if (entry == null ||
              isRefund(entry['data']) ||
              entry['data']['type'] != data['type'] ||
              entry['data']['original_currency'] != data['original_currency'] ||
              entry['data']['original_amount_minor'] !=
                  data['original_amount_minor'] ||
              entry['data']['date'] != data['date'] ||
              entry['data']['amount'] != data['amount'] ||
              entry['data']['account'] != data['account'] ||
              localItems(
                active,
                'recurring_occurrences',
              ).any((x) => (x['entry_ids'] as List).contains(existing)) ||
              ids.contains(existing)) {
            throw const FormatException('已有流水不匹配或已关联，请核对日期、币种、方向和金额');
          }
          ids.add(existing);
        } else {
          final entryId = 'recurring:$id:$suffix';
          if ((active['entries'] as List).any((e) => e['id'] == entryId)) {
            throw const FormatException('本期已有付款记录，请关联已有流水');
          }
          await saveEntry({
            ...data,
            'note': [
              if ((data['note'] ?? '').isNotEmpty) data['note'],
              '${o['name']} · 第 ${o['period']} 期',
              if (o['coverage_start'] != null)
                '${o['coverage_start']} 至 ${o['coverage_end']}',
            ].join(' · '),
          }, id: entryId);
          invalidateLedger(active);
          ids.add(entryId);
        }
      }

      await saveLine(primary, 'main', existingId);
      if (extra != null) await saveLine(extra, 'extra', existingExtraId);
      o['entry_ids'] = ids;
      o['status'] = 'confirmed';
      o['confirmed_at'] = DateTime.now().toUtc().toIso8601String();
      if (updateFuture) {
        final p = recurringPlans.firstWhere((p) => p['id'] == o['plan_id']);
        p['revision'] = (p['revision'] as int? ?? 0) + 1;
        p['fields'] = {
          ...p['fields'] as Json,
          'original_amount_minor': primary['original_amount_minor'],
        };
        if (updatePending) {
          for (final row in localItems(active, 'recurring_occurrences')) {
            if (row['plan_id'] == o['plan_id'] &&
                row['status'] == 'pending' &&
                row['period'] > o['period']) {
              row['fields'] = {
                ...row['fields'] as Json,
                'original_amount_minor': primary['original_amount_minor'],
              };
            }
          }
        }
      }
      _finishRecurring(o['plan_id']);
    });
  }

  /// Deleting a linked transaction preserves processed status and exposes missing
  /// links in history; restoring the transaction restores visibility automatically.
  bool hasRecurringLink(String entryId) => localItems(
    active,
    'recurring_occurrences',
  ).any((o) => (o['entry_ids'] as List).contains(entryId));
}
