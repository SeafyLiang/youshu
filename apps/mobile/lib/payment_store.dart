part of 'store.dart';

extension PaymentImportStore on LedgerStore {
  List<Json> importMatchRows() => [
    for (final l in ledgers)
      for (final e in l['entries'])
        if (e['kind'] == 'entry')
          {
            'id': e['id'],
            'ledger_id': l['id'],
            'deleted': e['deleted'] == true,
            'key':
                e['data']['source_key'] ??
                l['import_manifest']?['rows']?[e['id']]?['source_id'] ??
                '',
            'dateTime':
                l['import_manifest']?['rows']?[e['id']]?['date_time'] ??
                '${e['data']['date'] ?? '1900-01-01'} ${e['data']['time'] ?? '00:00'}',
            'amount': e['data']['original_amount_minor'],
            'currency': e['data']['original_currency'],
            'type': e['data']['type'],
            'refund': isRefund(e['data']),
            'original':
                l['import_manifest']?['rows']?[e['id']]?['original'] ?? {},
            'note': e['data']['note'],
            'fingerprint': e['data']['source_fingerprint'] ?? '',
            'source_status': e['data']['source_status'] ?? '',
          },
  ];
  Future<void> saveImportDraft(Json draft) async {
    final before = state['importDrafts'], dirty = state['backupDirty'];
    final list = List<dynamic>.from(before ?? []);
    list.removeWhere((e) => e['id'] == draft['id']);
    list.add(draft);
    state['importDrafts'] = list;
    state['backupDirty'] = true;
    try {
      await persist(preferencesOnly: true);
    } catch (_) {
      state['importDrafts'] = before;
      state['backupDirty'] = dirty;
      rethrow;
    }
    scheduleBackup();
  }

  Future<int> commitImportDraft(
    Json draft, {
    required String target,
    required String name,
  }) async {
    if (busy) throw const FormatException('请稍后再试');
    if ((draft['errors'] as List).isNotEmpty) {
      throw const FormatException('请先修正文件中的错误行');
    }
    final ready = (draft['rows'] as List)
        .cast<Json>()
        .where((e) => e['status'] == 'ready')
        .toList();
    if (ready.isEmpty) throw const FormatException('没有待导入记录');
    final old = target.isEmpty
        ? null
        : ledgers.where((e) => e['id'] == target).firstOrNull;
    if (target.isNotEmpty &&
        (old == null || !['owner', 'editor'].contains(old['role']))) {
      throw const FormatException('账本不可写');
    }
    if (target.isEmpty && (name.trim().isEmpty || name.trim().length > 40)) {
      throw const FormatException('填写1–40字账本名称');
    }
    final base = old == null
        ? 'CNY'
        : settingsOf(old)['base_currency'] as String;
    final needed = <String, Set<String>>{};
    for (final r in ready) {
      if (r['currency'] != base && r['refund'] != true) {
        (needed[r['currency']] ??= {}).add(r['dateTime'].substring(0, 10));
      }
    }
    final rates = historicalQuotes(needed, base);
    busy = true;
    changed();
    final before = state;
    try {
      final book = old == null
          ? freshLedger(name.trim())
          : {
              ...old,
              'entries': List<dynamic>.from(old['entries']),
              'pending': List<dynamic>.from(old['pending']),
            };
      final index = ledgerIndex(book),
          entries = book['entries'] as List,
          added = <Json>[],
          cat = <String, String>{},
          tags = <String, String>{};
      for (final c in index.byKind['category'] ?? <Json>[]) {
        cat['${c['data']['type']}/${c['data']['parent_id']}/${c['data']['name']}'] =
            c['id'];
      }
      for (final t in index.byKind['tag'] ?? <Json>[]) {
        tags[t['data']['name']] = t['id'];
      }
      String ensureCat(String type, String label, String parent) {
        final key = '$type/$parent/$label';
        return cat.putIfAbsent(key, () {
          final id = uuid.v4();
          added.add(
            entity(id, 'category', {
              'name': label,
              'type': type,
              'parent_id': parent,
              'icon': 'category',
              'color': type == 'income' ? '#BD672D' : '#126C62',
              'order': cat.length,
              'archived': false,
            }),
          );
          return id;
        });
      }

      final audit = Map<String, dynamic>.from(
            book['import_manifest']?['rows'] ?? {},
          ),
          ids = {for (final e in entries) e['id']: e},
          knownKeys = {
            for (final e in entries)
              if ((e['data']['source_key'] ?? '') != '')
                e['data']['source_key'],
          };
      final used = {...index.refunds}, usedOriginal = <String, int>{};
      for (final e in index.records) {
        final d = e['data'];
        if (isRefund(d)) {
          usedOriginal[d['refund_of']] =
              (usedOriginal[d['refund_of']] ?? 0) +
              (d['original_amount_minor'] as int);
        }
      }
      final ordered = [...ready]
        ..sort(
          (a, b) => (a['refund'] == true ? 1 : 0).compareTo(
            b['refund'] == true ? 1 : 0,
          ),
        );
      for (final r in ordered) {
        if (ids.containsKey(r['id']) || knownKeys.contains(r['key'])) {
          throw const FormatException('订单已存在，请返回预览重新核对');
        }
        final source = r['refund'] == true ? ids[r['refund_of']] : null;
        if (r['refund'] == true &&
            (source == null ||
                source['deleted'] == true ||
                source['data']['type'] != 'expense' ||
                isRefund(source['data']))) {
          throw const FormatException('退款原消费须在目标账本或本批导入中');
        }
        final type = r['refund'] == true ? 'expense' : r['type'] as String;
        final cid = source != null
            ? source['data']['category_id']
            : ensureCat(type, r['category'], ensureCat(type, r['parent'], ''));
        final tagIds = <String>[];
        for (final label in r['tags']) {
          tagIds.add(
            tags.putIfAbsent(label, () {
              final id = uuid.v4();
              added.add(
                entity(id, 'tag', {
                  'name': label,
                  'color': '#4265A8',
                  'order': tags.length,
                  'archived': false,
                }),
              );
              return id;
            }),
          );
        }
        final date = (r['dateTime'] as String).substring(0, 10),
            rate = source != null
                ? <String, dynamic>{
                    'rate': source['data']['fx_rate'],
                    'date': source['data']['fx_rate_date'],
                    'source': 'refund-proportion',
                  }
                : r['currency'] == base
                ? <String, dynamic>{
                    'rate': '1',
                    'date': date,
                    'source': 'identity',
                  }
                : r['manual_fx_base'] == base && r['manual_fx_rate'] is String
                ? <String, dynamic>{
                    'rate': r['manual_fx_rate'],
                    'date': date,
                    'source': 'manual',
                  }
                : rates['${r['currency']}/$date'];
        if (rate == null) {
          throw FormatException('${r['currency']} $date 缺少本机汇率，请核对后补填');
        }
        var amount = convertAmount(
          r['amount'],
          r['currency'],
          base,
          rate['rate'],
        );
        if (source != null) {
          if (source['data']['original_currency'] != r['currency']) {
            throw const FormatException('退款原币与原消费不一致，请核对');
          }
          final previous = usedOriginal[source['id']] ?? 0,
              cumulative = previous + (r['amount'] as int),
              originalAmount = source['data']['original_amount_minor'] as int;
          if (cumulative > originalAmount) {
            throw const FormatException('累计原币退款超出原消费');
          }
          amount =
              ((BigInt.from(cumulative) *
                              BigInt.from(source['data']['amount']) +
                          BigInt.from(originalAmount ~/ 2)) ~/
                      BigInt.from(originalAmount))
                  .toInt() -
              (used[source['id']] ?? 0);
          usedOriginal[source['id']] = cumulative;
          if (base == 'CNY' &&
              r['currency'] == 'CNY' &&
              amount != r['amount']) {
            throw const FormatException('人民币实退额与原消费比例不一致，请核对');
          }
        }
        if (amount <= 0 || amount > 999999999999) {
          throw const FormatException('折算金额无效');
        }
        if (source != null) {
          final sum = (used[source['id']] ?? 0) + amount;
          if (date.compareTo(source['data']['date']) < 0 ||
              sum > source['data']['amount']) {
            throw const FormatException('退款日期或累计金额超出原消费，请核对');
          }
          used[source['id']] = sum;
        }
        final value = entity(r['id'], 'entry', {
          'source_key': draft['platform'] == 'suishouji' ? '' : r['key'],
          'source_fingerprint': r['fingerprint'],
          'source_status': r['source_status'],
          'type': type,
          'date': date,
          'time': r['dateTime'].substring(11, 16),
          'category': source?['data']['category'] ?? r['category'],
          'category_id': cid,
          'tag_ids': source?['data']['tag_ids'] ?? tagIds,
          'account': r['account'],
          'note': r['note'],
          'amount': amount,
          'base_amount_minor': amount,
          'base_currency': base,
          'original_amount_minor': r['amount'],
          'original_currency': r['currency'],
          'currency_scale': currencies[r['currency']],
          'fx_rate': rate['rate'],
          'fx_rate_date': rate['date'],
          'fx_source': rate['source'],
          'fx_mode': r['currency'] == base
              ? 'identity'
              : source != null
              ? 'actual'
              : rate['source'] == 'manual'
              ? 'manual'
              : 'auto',
          'refund_of': source?['id'] ?? '',
          'to_currency': base,
          'to_amount_minor': 0,
          'to_account': '',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        if ((r['account'] as String).isEmpty ||
            (r['account'] as String).length > 50 ||
            (r['note'] as String).length > 500 ||
            tagIds.length > 40) {
          throw const FormatException('账户、备注或标签超出限制');
        }
        added.add(value);
        ids[value['id']] = value;
        knownKeys.add(r['key']);
        audit[value['id']] = {
          'source_id': r['key'],
          'date_time': r['dateTime'],
          'original': r['original'],
          'line': r['line'],
          'batch': draft['id'],
        };
      }
      // Editors may use existing dictionaries only; owners create missing items.
      if (book['role'] != 'owner' && added.any((e) => e['kind'] != 'entry')) {
        throw const FormatException('请先由所有者添加所需分类和标签');
      }
      for (final e in added) {
        e['author'] = userId;
        e['author_name'] = '我';
        e['revision'] = book['shared'] == true ? 1 : 0;
        entries.add(e);
        if (book['shared'] == true) {
          (book['pending'] as List).add({
            'operation_id': uuid.v4(),
            'id': e['id'],
            'kind': e['kind'],
            'data': e['data'],
            'base_revision': 0,
            'deleted': false,
          });
        }
      }
      book['import_manifest'] = {'rows': audit};
      invalidateLedger(book);
      final updated = {
        ...draft,
        'target': book['id'],
        'rows': [
          for (final r in (draft['rows'] as List).cast<Json>())
            if (r['status'] == 'ready') {...r, 'status': 'imported'} else r,
        ],
      };
      state = {
        ...state,
        'ledgers': [
          for (final l in allLedgers)
            if (l['id'] != book['id']) l,
          book,
        ],
        'active': book['id'],
        'viewLedgers': [book['id']],
        'importDrafts': [
          for (final d in state['importDrafts'] ?? [])
            if (d['id'] != draft['id']) d,
          updated,
        ],
        'importHistory': [
          ...state['importHistory'] as List? ?? [],
          _batchRecord(
            file: draft['file'],
            source: draft['platform'],
            books: [book],
            ids: ready.map((e) => e['id'] as String).toSet(),
          ),
        ],
      };
      await persist();
      return ready.length;
    } catch (_) {
      state = before;
      rethrow;
    } finally {
      busy = false;
      changed();
    }
  }
}
