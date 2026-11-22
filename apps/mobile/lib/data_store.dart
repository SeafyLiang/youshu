part of 'store.dart';

const portableBackupLimit = 50 * 1024 * 1024;

class BackupPreview {
  final Json _bundle;
  final String file;
  final String createdAt;
  final bool checksumVerified;
  const BackupPreview._(
    this._bundle,
    this.file,
    this.createdAt,
    this.checksumVerified,
  );
  List<Json> get copies => (_bundle['ledgers'] as List).cast<Json>();
  int get drafts => (_bundle['drafts'] as List).length;
  int get templates =>
      copies.fold(0, (n, b) => n + localItems(b, 'record_templates').length);
  int get plans =>
      copies.fold(0, (n, b) => n + localItems(b, 'recurring_plans').length);
  int get entryCount => copies.fold(0, (n, book) => n + recordsInBackup(book));
}

int recordsInBackup(Json book) => (book['entries'] as List)
    .where((row) => row['kind'] == 'entry' && row['deleted'] != true)
    .length;

class ImportUndoPreview {
  final String id;
  final Object? _revision;
  final Map<String, Set<String>> _entries;
  final int count, kept;
  const ImportUndoPreview._(
    this.id,
    this._revision,
    this._entries,
    this.count,
    this.kept,
  );
}

extension LocalDataStore on LedgerStore {
  Future<Json> _committedBackup(DateTime now) async {
    await _writeTail;
    final snapshot = await readState(database!);
    if (snapshot == null) throw const FormatException('尚无已保存账本');
    return {
      'schema':
          (snapshot['ledgers'] as List).any(
            (l) => [
              'record_templates',
              'recurring_plans',
            ].any((key) => (l[key] as List? ?? []).isNotEmpty),
          )
          ? 6
          : 5,
      'createdAt': now.toUtc().toIso8601String(),
      'ledgers': snapshot['ledgers'],
      'importDrafts': snapshot['importDrafts'] ?? [],
      'importHistory': snapshot['importHistory'] ?? [],
      'preferences': {
        for (final k in ['showBalance', 'keyHaptic', 'keypadLayout'])
          if (snapshot[k] != null) k: snapshot[k],
      },
    };
  }

  Future<Uint8List> exportBackupFile() async =>
      compute(_encodePortableBackup, await _committedBackup(DateTime.now()));

  Future<BackupPreview> inspectBackupFile(Uint8List bytes, String filename) {
    if (bytes.length > portableBackupLimit) {
      throw const FormatException('备份文件不能超过 50 MB');
    }
    return compute(_inspectBackup, (bytes, filename, false));
  }

  Future<BackupPreview> inspectWebDavBackup(String manifestFile) async {
    if (!_validBackupName(manifestFile) ||
        !manifestFile.endsWith('.manifest.json')) {
      throw const FormatException('备份文件名不合法');
    }
    final manifest = jsonDecode(
      (await dav('GET', '/yousu/$manifestFile')).body,
    );
    final name = manifest['file'];
    if (name is! String ||
        !_validBackupName(name) ||
        name.endsWith('.manifest.json')) {
      throw const FormatException('备份路径不合法');
    }
    final res = await dav('GET', '/yousu/$name');
    return compute(_inspectWebDavChecksum, (
      res.bodyBytes,
      name,
      manifest['sha256']?.toString() ?? '',
      manifest['bytes'] is int ? manifest['bytes'] as int : null,
    ));
  }

  Future<void> restorePreview(BackupPreview preview) async {
    if (busy) throw const FormatException('请稍后再试');
    busy = true;
    changed();
    final before = state;
    try {
      final restored = preview._bundle;
      final copies = List<Json>.from(restored['ledgers']);
      final existingIds = allLedgers.map((l) => l['id']).toSet();
      if (copies.any((l) => existingIds.contains(l['id']))) {
        throw const FormatException('这份预览已恢复，请重新选择备份');
      }
      state = {
        ...state,
        'ledgers': [...allLedgers, ...copies],
        'importDrafts': [
          ...List.from(state['importDrafts'] ?? []),
          ...restored['drafts'],
        ],
        'importHistory': [
          ...List.from(state['importHistory'] ?? []),
          ...restored['history'],
        ],
      };
      await persist();
    } catch (_) {
      state = before;
      rethrow;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<Uint8List> exportCsv(Json book, Iterable<Json> rows) =>
      compute(_encodeCsv, (book, rows.toList()));

  List<Json> get importBatches =>
      (state['importHistory'] as List? ?? []).cast<Json>().reversed.toList();

  Future<ImportUndoPreview> previewImportUndo(Json batch) =>
      compute(_previewUndo, (batch, allLedgers, state['dataRevision']));

  Future<void> undoImportBatch(ImportUndoPreview preview) async {
    if (busy) throw const FormatException('请稍后再试');
    final batch = importBatches
        .where((b) => b['batch_id'] == preview.id)
        .firstOrNull;
    if (preview.count == 0 ||
        batch == null ||
        batch['undone_at'] != null ||
        preview._revision != state['dataRevision']) {
      throw const FormatException('账本或批次已变化，请重新预览');
    }
    busy = true;
    changed();
    final before = state;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      state = {
        ...state,
        'ledgers': [
          for (final book in allLedgers)
            if (!preview._entries.containsKey(book['id']))
              book
            else
              {
                ...book,
                'entries': [
                  for (final row in (book['entries'] as List).cast<Json>())
                    if (!preview._entries[book['id']]!.contains(row['id']))
                      row
                    else
                      {
                        ...row,
                        'deleted': true,
                        'data': {
                          ...row['data'] as Json,
                          'deleted_at': now,
                          'updated_at': now,
                          'trash_group': row['id'],
                        },
                      },
                ],
              },
        ],
        'importHistory': [
          for (final entry in state['importHistory'] ?? [])
            if (entry['batch_id'] != preview.id)
              entry
            else
              {
                ...entry as Json,
                'undone_at': now,
                'undone_count': preview.count,
              },
        ],
      };
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

bool _validBackupName(String name) =>
    RegExp(r'^[\w.\-]+\.json$').hasMatch(name) && !name.contains('..');

Uint8List _encodePortableBackup(Json snapshot) {
  final bytes = utf8.encode(
    jsonEncode({
      'format': 'youshu-backup',
      'version': 1,
      'sha256': sha256.convert(utf8.encode(jsonEncode(snapshot))).toString(),
      'snapshot': snapshot,
    }),
  );
  if (bytes.length > portableBackupLimit) {
    throw const FormatException('备份文件超过 50 MB');
  }
  return bytes;
}

BackupPreview _inspectWebDavChecksum((Uint8List, String, String, int?) input) {
  if ((input.$4 != null && input.$4 != input.$1.length) ||
      sha256.convert(input.$1).toString() != input.$3) {
    throw const FormatException('备份校验失败，未恢复');
  }
  return _inspectBackup((input.$1, input.$2, true));
}

BackupPreview _inspectBackup((Uint8List, String, bool) input) {
  try {
    var snapshot = jsonDecode(utf8.decode(input.$1)) as Json;
    var verified = input.$3;
    if (snapshot['format'] == 'youshu-backup') {
      if (snapshot['version'] != 1 || snapshot['snapshot'] is! Json) {
        throw const FormatException('不支持的完整备份文件版本');
      }
      final expected = snapshot['sha256'];
      snapshot = snapshot['snapshot'] as Json;
      if (sha256.convert(utf8.encode(jsonEncode(snapshot))).toString() !=
          expected) {
        throw const FormatException('备份校验失败，未恢复');
      }
      verified = true;
    }
    return BackupPreview._(
      restoreBundle(snapshot),
      input.$2,
      snapshot['createdAt']?.toString() ?? '',
      verified,
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('备份文件结构无效，未恢复');
  }
}

String _exportType(Json d) => switch (cashFlowType(d)) {
  'income' => isRefund(d) ? '退款' : '收入',
  'transfer' => '转账',
  _ => '支出',
};

Uint8List _encodeCsv((Json, List<Json>) input) {
  String cell(dynamic value) {
    final text = value?.toString() ?? '';
    // A spreadsheet must open user notes and names as text, never as formulas.
    final safe = RegExp(r'^[\s]*[=+\-@]|^[\t\r\n]').hasMatch(text)
        ? "'$text"
        : text;
    return '"${safe.replaceAll('"', '""')}"';
  }

  final file = StringBuffer(
    '\uFEFF账本,日期,时间,类型,分类,账户,原币金额,原币,基准币金额,基准币,转入账户,转入金额,转入币种,备注\r\n',
  );
  for (final row in input.$2) {
    final d = row['data'] as Json;
    final transfer = d['type'] == 'transfer';
    file.write(
      [
        cell(input.$1['name']),
        cell(d['date']),
        cell(d['time']),
        cell(_exportType(d)),
        cell(transfer ? '' : categoryName(input.$1, d)),
        cell(d['account'] == '未指定' ? '' : d['account']),
        formatAmount(
          d['original_amount_minor'] ?? d['amount'],
          d['original_currency'] ?? 'CNY',
        ),
        cell(d['original_currency'] ?? 'CNY'),
        formatAmount(
          d['base_amount_minor'] ?? d['amount'],
          d['base_currency'] ?? 'CNY',
        ),
        cell(d['base_currency'] ?? 'CNY'),
        cell(transfer ? d['to_account'] : ''),
        transfer ? formatAmount(d['to_amount_minor'], d['to_currency']) : '',
        cell(transfer ? d['to_currency'] : ''),
        cell(d['note']),
      ].join(','),
    );
    file.write('\r\n');
  }
  return utf8.encode(file.toString());
}

String _batchFingerprint(Json row) =>
    sha256.convert(utf8.encode(jsonEncode(row['data']))).toString();

Json _batchRecord({
  required String file,
  required String source,
  required List<Json> books,
  required Set<String> ids,
}) => {
  'batch_id': uuid.v4(),
  'file': file,
  'source': source,
  'at': DateTime.now().toUtc().toIso8601String(),
  'count': ids.length,
  'ledger_ids': books.map((b) => b['id']).toList(),
  'ids': ids.toList(),
  'refs': {
    for (final book in books)
      book['id']: {
        for (final row in (book['entries'] as List).cast<Json>())
          if (row['kind'] == 'entry' && ids.contains(row['id']))
            row['id']: _batchFingerprint(row),
      },
  },
};

// Build 19 restored only unedited fingerprints. Earlier restores still carry
// the original import IDs and the ledger's entry origins.
Set<String> importBatchMemberIds(Json batch, Json book) {
  final bookId = book['id'];
  final members = batch['members'] as Map?;
  if (members != null) {
    return Set<String>.from(members[bookId] as List? ?? const []);
  }
  final fingerprints = batch['refs']?[bookId] as Map?;
  final ids = <String>{...?fingerprints?.keys.cast<String>()};
  if (!(batch['ledger_ids'] as List? ?? const []).contains(bookId)) return ids;
  final originals = Set<String>.from(batch['ids'] as List? ?? const []);
  final origins = book['merge_sources'] as Map? ?? const {};
  return {
    ...ids,
    ...originals,
    for (final origin in origins.entries)
      if (originals.contains(origin.value['entry'])) origin.key as String,
  };
}

ImportUndoPreview _previewUndo((Json, List<Json>, Object?) input) {
  final batch = input.$1;
  final refs = (batch['refs'] as Map?) ?? {};
  final matched = <String, Set<String>>{};
  for (final book in input.$2) {
    final id = book['id'] as String;
    final included = refs[id] as Map?;
    if (included == null ||
        book['deleted_at'] != null ||
        book['shared'] == true ||
        batch['undone_at'] != null) {
      continue;
    }
    final index = ledgerIndex(book);
    for (final entry in included.entries) {
      final row = index.byId[entry.key];
      if (row != null &&
          row['kind'] == 'entry' &&
          !index.refunds.containsKey(row['id']) &&
          entry.value == _batchFingerprint(row)) {
        (matched[id] ??= {}).add(row['id']);
      }
    }
  }
  final count = matched.values.fold<int>(0, (n, rows) => n + rows.length);
  return ImportUndoPreview._(
    batch['batch_id']?.toString() ?? '',
    input.$3,
    matched,
    count,
    (batch['count'] as int? ?? count) - count,
  );
}
