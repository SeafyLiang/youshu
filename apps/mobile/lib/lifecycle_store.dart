part of 'store.dart';

extension LifecycleStore on LedgerStore {
  Future<void> batchEntries(
    Set<String> ids,
    String operation,
    Json changes,
  ) async {
    if (!['edit', 'copy', 'delete'].contains(operation)) {
      throw const FormatException('未知批量操作');
    }
    for (final key in ['account', 'member', 'merchant', 'project']) {
      if (changes[key] != null &&
          (changes[key] is! String || (changes[key] as String).length > 50)) {
        throw const FormatException('标签不能超过50字');
      }
    }
    final selected = records(active)
        .where((e) => ids.contains(e['id']))
        .toList();
    if (selected.length != ids.length) {
      throw const FormatException('部分流水已变化，请重新选择');
    }
    if (operation == 'copy' && selected.any((e) => isRefund(e['data']))) {
      throw const FormatException('退款流水不能直接复制，请取消选择退款');
    }
    final affected = {for (final e in selected) e['id']: e};
    if (operation == 'delete') {
      for (final e in records(active)) {
        if (ids.contains(e['data']['refund_of'])) affected[e['id']] = e;
      }
    }
    await atomicBook(() async {
      final trashGroup = uuid.v4();
      final ordered = affected.values.toList()
        ..sort(
          (a, b) => (isRefund(b['data']) ? 1 : 0).compareTo(
            isRefund(a['data']) ? 1 : 0,
          ),
        );
      for (final entry in ordered) {
        final d = Map<String, dynamic>.from(entry['data']);
        if (operation == 'delete') {
          d['trash_group'] = trashGroup;
        }
        if (operation == 'copy') {
          for (final key in [
            'source_key',
            'source_fingerprint',
            'source_status',
            'refund_of',
            'deleted_at',
            'trash_group',
          ]) {
            d.remove(key);
          }
        }
        if (operation == 'edit') {
          for (final patch in changes.entries) {
            if (patch.key == 'category_id') {
              final cat = ledgerIndex(active).byId[patch.value];
              if (cat == null ||
                  cat['data']['type'] != d['type'] ||
                  isRefund(d) ||
                  records(active)
                      .any((e) => e['data']['refund_of'] == entry['id'])) {
                continue;
              }
              d['category_id'] = patch.value;
              d['category'] = cat['data']['name'];
            } else if (patch.key == 'account') {
              if (d['type'] != 'transfer') {
                d['account'] = patch.value == '' ? '未指定' : patch.value;
              }
            } else if ([
              'member',
              'merchant',
              'project',
              'tag_ids',
            ].contains(patch.key)) {
              d[patch.key] = patch.value;
            }
          }
        }
        await saveEntry(
          d,
          existing: operation == 'copy' ? null : entry,
          deleted: operation == 'delete',
        );
        invalidateLedger(active);
      }
    });
  }

  Future<void> setGlobalBudget(int amount, {bool yearly = false}) async {
    if (amount < 0 || amount > 999999999999) {
      throw const FormatException('预算金额无效');
    }
    final row = ledgerIndex(active).byId['settings']!;
    await saveEntry(
      {
        ...row['data'] as Json,
        if (yearly) 'yearly_budget': amount,
        if (!yearly) 'monthly_budget': amount,
        if (!yearly)
          'budget_generation':
              (row['data']['budget_generation'] as int? ?? 0) + 1,
      },
      kind: 'ledger_settings',
      existing: row,
    );
  }

  int? get yearlyBudget => settingsOf(active)['yearly_budget'] as int?;

  Future<void> atomicBook(Future<void> Function() action) async {
    if (busy) throw const FormatException('请稍后再试');
    final book = active;
    busy = true;
    changed();
    final before = await compute(_cloneBook, book);
    try {
      _batchEditing = true;
      await action();
      validateLocalSchedules(active);
      _batchEditing = false;
      await persist();
    } catch (_) {
      _batchEditing = false;
      state['ledgers'][allLedgers.indexWhere((l) => l['id'] == book['id'])] =
          before;
      rethrow;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> trashEntry(Json entry) async {
    final group = uuid.v4();
    final linked = records(active)
        .where((e) => e['data']['refund_of'] == entry['id'])
        .toList();
    await atomicBook(() async {
      for (final e in [...linked, entry]) {
        await saveEntry(
          {...e['data'] as Json, 'trash_group': group},
          existing: e,
          deleted: true,
        );
        invalidateLedger(active);
      }
    });
  }

  List<Json> get trashBooks =>
      allLedgers.where((l) => l['deleted_at'] != null).toList();
  List<Json> trashEntries(Json l) => (l['entries'] as List)
      .cast<Json>()
      .where(
        (e) =>
            e['kind'] == 'entry' &&
            e['deleted'] == true &&
            e['data']['deleted_at'] != null &&
            e['data']['purged'] != true,
      )
      .toList();
  Future<void> trashBook(Json book) async {
    if (busy) throw const FormatException('请稍后再试');
    final before = {
      ...state,
      'ledgers': [...allLedgers],
    };
    final replacement = {
      ...book,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    };
    state['ledgers'] = allLedgers
        .map((l) => l == book ? replacement : l)
        .toList();
    if (book['shared'] == true) {
      state['hiddenSharedBooks'] = [
        ...List<String>.from(state['hiddenSharedBooks'] ?? []),
        book['id'],
      ];
    }
    if (ledgers.isEmpty) {
      state['ledgers'] = [...allLedgers, freshLedger('日常账本')];
    }
    if (state['active'] == book['id']) state['active'] = ledgers.first['id'];
    state['viewLedgers'] = List<String>.from(state['viewLedgers'] ?? [])
        .where((id) => id != book['id'])
        .toList();
    try {
      await persist();
    } catch (_) {
      state = before;
      rethrow;
    }
  }

  Future<void> restoreBook(Json book) async {
    if (book['shared'] == true) {
      final remote = await api('/api/ledgers') as List;
      final permission = remote
          .cast<Json>()
          .where((l) => l['id'] == book['id'])
          .firstOrNull;
      if (permission == null) throw const FormatException('共享权限已变更，可复制为本地账本');
      // Preserve local pending operations; normal revision checks run on explicit sync.
      await api('/api/ledgers/${book['id']}/snapshot');
      book['role'] = permission['role'];
    }
    final before = {...book};
    final hiddenBefore = state['hiddenSharedBooks'];
    book.remove('deleted_at');
    state['hiddenSharedBooks'] = List<String>.from(
      state['hiddenSharedBooks'] ?? [],
    )..remove(book['id']);
    try {
      await persist();
    } catch (_) {
      state['hiddenSharedBooks'] = hiddenBefore;
      book
        ..clear()
        ..addAll(before);
      rethrow;
    }
  }

  Future<void> copyBook(Json book) async {
    final input = await compute(_cloneBook, book);
    input.remove('deleted_at');
    input['entries'] = (input['entries'] as List)
        .where((e) => e['deleted'] != true)
        .toList();
    final copy = validateBackup({
      'schema': 5,
      'ledgers': [input],
    }).single;
    copy['name'] = '${book['name']} · 副本';
    final before = state;
    state = {
      ...state,
      'ledgers': [...allLedgers, copy],
      'active': copy['id'],
      'viewLedgers': [copy['id']],
    };
    try {
      await persist();
    } catch (_) {
      state = before;
      rethrow;
    }
  }

  Future<void> restoreTrashEntry(Json book, Json entry) async {
    final oldActive = state['active'];
    state['active'] = book['id'];
    try {
      final group = entry['data']['trash_group'];
      final rows =
          trashEntries(book)
              .where(
                (e) => group != null && group != ''
                    ? e['data']['trash_group'] == group
                    : e['id'] == entry['id'],
              )
              .toList()
            ..sort(
              (a, b) => (isRefund(a['data']) ? 1 : 0).compareTo(
                isRefund(b['data']) ? 1 : 0,
              ),
            );
      await atomicBook(() async {
        for (final e in rows) {
          await saveEntry(e['data'], existing: e);
          invalidateLedger(book);
        }
      });
    } finally {
      state['active'] = oldActive;
      await persist(preferencesOnly: true);
    }
  }

  Future<void> purgeTrash({
    bool all = false,
    Json? book,
    Json? entry,
    DateTime? now,
  }) async {
    if (busy) throw const FormatException('请稍后再试');
    final time = now ?? DateTime.now().toUtc();
    bool expired(dynamic at) =>
        at is String &&
        !DateTime.parse(at).add(const Duration(days: 30)).isAfter(time);
    if (!all && book == null && entry == null) {
      final hasExpired = allLedgers.any(
        (ledger) =>
            expired(ledger['deleted_at']) ||
            (ledger['deleted_at'] == null &&
                (ledger['entries'] as List).any(
                  (row) =>
                      row['deleted'] == true &&
                      row['data']['purged'] != true &&
                      expired(row['data']['deleted_at']),
                )),
      );
      if (!hasExpired) return;
    }
    final before = state;
    final revision = state['dataRevision'];
    final next = await compute(_cloneBook, state);
    if (busy || revision != state['dataRevision']) {
      throw const FormatException('账本已变更，请重试');
    }
    var changed = false;
    final books = (next['ledgers'] as List).cast<Json>();
    for (final l in books.toList()) {
      final selected = book?['id'] == l['id'];
      if (l['deleted_at'] != null) {
        if (all || (selected && entry == null) || expired(l['deleted_at'])) {
          books.remove(l);
          changed = true;
        }
        continue;
      }
      for (final e in (l['entries'] as List).cast<Json>()) {
        if (e['deleted'] != true ||
            e['data']['deleted_at'] == null ||
            e['data']['purged'] == true) {
          continue;
        }
        final d = e['data'] as Json;
        final sameGroup =
            selected &&
            entry != null &&
            (entry['id'] == e['id'] ||
                (d['trash_group'] != '' &&
                    d['trash_group'] != null &&
                    d['trash_group'] == entry['data']['trash_group']));
        if (all || sameGroup || expired(d['deleted_at'])) {
          // Keep outbox deletion payload until acknowledged; remove visible recovery data now.
          (l['import_manifest']?['rows'] as Map?)?.remove(e['id']);
          (l['fx_audit'] as Map?)?.remove(e['id']);
          e['purge_pending'] = l['shared'] == true;
          e['data'] = {
            'purged': true,
            'deleted_at': d['deleted_at'],
            'source_key': d['source_key'] ?? '',
          };
          changed = true;
        }
      }
    }
    if (!changed) return;
    next['ledgers'] = books;
    state = next;
    try {
      await persist();
    } catch (_) {
      state = before;
      rethrow;
    }
  }
}

Json _cloneBook(Json input) => jsonDecode(jsonEncode(input)) as Json;

Future<String> _hashFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
Future<Json> _writeBackupFile((Json, String) args) async {
  final file = File(args.$2);
  await file.writeAsString(jsonEncode(args.$1));
  return {'sha256': await _hashFile(file), 'bytes': await file.length()};
}

extension BackupScheduler on LedgerStore {
  void scheduleBackup() {
    if (!autoBackupReady || state['autoBackup'] != true) return;
    state['backupDirty'] = true;
    backupBurst ??= DateTime.now();
    backupTimer?.cancel();
    final overdue = DateTime.now().difference(backupBurst!).inSeconds >= 60;
    backupTimer = Timer(
      Duration(seconds: overdue ? 0 : 10),
      () => runAutomaticBackup(),
    );
  }

  Future<void> resumeMaintenance() async {
    if (database == null) return;
    return _maintenance ??= _resumeMaintenance().whenComplete(
      () => _maintenance = null,
    );
  }

  Future<void> _resumeMaintenance() async {
    unawaited(updateRates().catchError((Object _) {}));
    await flushViewPreferences();
    queueWidgetRefresh();
    if (busy) return;
    await purgeTrash();
    await maintainRecurring();
    if (state['autoBackup'] != true) return;
    try {
      autoBackupReady = (await davSettings())['url'] != null;
    } catch (_) {
      autoBackupReady = false;
      return; // Local startup and recording do not depend on credential storage.
    }
    if (autoBackupReady &&
        (state['backupDirty'] == true || state['backupDay'] != today())) {
      await runAutomaticBackup();
    }
  }

  Future<void> runAutomaticBackup() async {
    if (!autoBackupReady || state['autoBackup'] != true) return;
    if (busy || backupRunning) {
      scheduleBackup();
      return;
    }
    try {
      await backup(automatic: true);
    } catch (_) {
      /* Persistent status on the backup page; retry on resume. */
    }
    if (state['backupDirty'] == true && (state['backupError'] ?? '') == '') {
      scheduleBackup();
    }
  }

  Future<List<Json>> backupHistory() async {
    final result = <Json>[];
    for (final name in await backups()) {
      try {
        final m = jsonDecode((await dav('GET', '/yousu/$name')).body) as Json;
        result.add({...m, 'manifest': name});
      } catch (_) {
        result.add({'manifest': name, 'invalid': true});
      }
    }
    return result;
  }

  Future<void> deleteBackup(Json m) async {
    final name = m['file'], manifest = m['manifest'];
    if (name is! String ||
        manifest is! String ||
        !RegExp(r'^[\w.\-]+\.json$').hasMatch(name) ||
        name.contains('..') ||
        !manifest.endsWith('.manifest.json') ||
        manifest.contains('/') ||
        manifest.contains('..')) {
      throw const FormatException('备份文件名无效');
    }
    // Data first: an interrupted delete remains visible and can be retried.
    await dav('DELETE', '/yousu/$name');
    await dav('DELETE', '/yousu/$manifest');
  }

  Future<void> pruneBackups() async {
    final own =
        (await backupHistory())
            .where(
              (m) =>
                  m['device'] == state['backupDevice'] && m['invalid'] != true,
            )
            .toList()
          ..sort(
            (a, b) =>
                (b['createdAt'] as String).compareTo(a['createdAt'] as String),
          );
    final keep = (state['backupKeep'] as int? ?? 7).clamp(1, 365);
    for (final m in own.skip(keep)) {
      await deleteBackup(m);
    }
  }
}
