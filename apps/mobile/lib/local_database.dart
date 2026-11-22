import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'domain.dart';

Future<void> createV2(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE IF NOT EXISTS import_drafts (id TEXT PRIMARY KEY, body TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE IF NOT EXISTS preferences (id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE IF NOT EXISTS ledgers (id TEXT PRIMARY KEY, body TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE IF NOT EXISTS entries (ledger_id TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL, book_date TEXT, body TEXT NOT NULL, PRIMARY KEY(ledger_id,id))',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS entry_date ON entries(ledger_id,kind,book_date)',
  );
  await db.execute(
    'CREATE TABLE IF NOT EXISTS outbox (ledger_id TEXT NOT NULL, id TEXT NOT NULL, position INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(ledger_id,id))',
  );
}

Future<void> writeState(DatabaseExecutor db, Json state) async {
  final prefs = Map<String, dynamic>.from(state)..remove('ledgers');
  await db.insert('preferences', {
    'id': 1,
    'body': jsonEncode(prefs),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  for (final ledger in state['ledgers']) {
    final meta = Map<String, dynamic>.from(ledger)
      ..remove('entries')
      ..remove('pending');
    await db.insert('ledgers', {
      'id': ledger['id'],
      'body': jsonEncode(meta),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final existing = {
      for (final r in await db.query(
        'entries',
        where: 'ledger_id=?',
        whereArgs: [ledger['id']],
      ))
        r['id']: r['body'],
    };
    for (final e in ledger['entries']) {
      final body = jsonEncode(e);
      if (existing[e['id']] != body) {
        await db.insert('entries', {
          'ledger_id': ledger['id'],
          'id': e['id'],
          'kind': e['kind'],
          'book_date': e['data']['date'],
          'body': body,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      existing.remove(e['id']);
    }
    for (final id in existing.keys) {
      await db.delete(
        'entries',
        where: 'ledger_id=? AND id=?',
        whereArgs: [ledger['id'], id],
      );
    }
    await db.delete('outbox', where: 'ledger_id=?', whereArgs: [ledger['id']]);
    var position = 0;
    for (final op in ledger['pending']) {
      await db.insert('outbox', {
        'ledger_id': ledger['id'],
        'id': op['operation_id'],
        'position': position++,
        'body': jsonEncode(op),
      });
    }
  }
}

Future<Json?> readState(
  Database db, {
  StateWriter? seedWriter,
  void Function(Json)? onPreferencesLoaded,
}) async {
  final raw = await db.transaction<Json?>((txn) async {
    final prefs = await txn.query('preferences', where: 'id=1');
    if (prefs.isEmpty) return null;
    final body = prefs.first['body'] as String;
    onPreferencesLoaded?.call(jsonDecode(body) as Json);
    return {
      'preferences': body,
      'drafts': await txn.query('import_drafts'),
      'ledgers': await txn.query('ledgers'),
      'entries': await txn.query('entries'),
      'outbox': await txn.query('outbox', orderBy: 'position'),
    };
  });
  if (raw == null) return null;
  final decoded = await compute(decodeDatabaseState, raw);
  seedWriter?.last = decoded.$2;
  return decoded.$1;
}

(Json, Json) decodeDatabaseState(Json raw) {
  final state = jsonDecode(raw['preferences'] as String) as Json;
  final books = <String, Json>{};
  final baseline = <String, Json>{};
  final drafts = <String, String>{};
  for (final row in raw['drafts']) {
    drafts[row['id']] = row['body'];
  }
  if (drafts.isNotEmpty) {
    state['importDrafts'] = drafts.values
        .map((body) => jsonDecode(body))
        .toList();
  }
  for (final row in raw['ledgers']) {
    final book = jsonDecode(row['body'] as String) as Json;
    book['entries'] = <dynamic>[];
    book['pending'] = <dynamic>[];
    books[row['id']] = book;
    baseline[row['id']] = {
      'id': row['id'],
      'body': row['body'],
      'entries': <String, dynamic>{},
      'pending': <dynamic>[],
    };
  }
  for (final row in raw['entries']) {
    final book = books[row['ledger_id']];
    if (book == null) continue;
    (book['entries'] as List).add(jsonDecode(row['body'] as String));
    baseline[row['ledger_id']]!['entries'][row['id']] = {
      'kind': row['kind'],
      'book_date': row['book_date'],
      'body': row['body'],
    };
  }
  for (final row in raw['outbox']) {
    final book = books[row['ledger_id']];
    if (book == null) continue;
    (book['pending'] as List).add(jsonDecode(row['body'] as String));
    (baseline[row['ledger_id']]!['pending'] as List).add({
      'id': row['id'],
      'body': row['body'],
    });
  }
  state['ledgers'] = books.values.toList();
  return (
    state,
    {
      'preferences': raw['preferences'],
      'widgetScope': {
        'active': state['active'],
        'revision': state['dataRevision'] ?? 0,
      },
      'drafts': drafts,
      'ledgers': baseline.values.toList(),
    },
  );
}

Future<Database> openLedgerDatabase(String path) async => openDatabase(
  path,
  version: 2,
  onOpen: (db) => db.execute(
    'CREATE TABLE IF NOT EXISTS import_drafts (id TEXT PRIMARY KEY, body TEXT NOT NULL)',
  ),
  onCreate: (db, _) async {
    await db.execute(
      'CREATE TABLE state (id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
    );
    await createV2(db);
  },
  onUpgrade: (db, old, next) async {
    await createV2(db);
    final rows = await db.query('state', where: 'id=1');
    if (rows.isNotEmpty) {
      // 原始 state 保留为一致性恢复点；sqflite 将升级放在事务中。
      final legacy = jsonDecode(rows.first['body'] as String) as Json;
      legacy['ledgers'] = (legacy['ledgers'] as List)
          .map((e) => migrateLedger(e))
          .toList();
      legacy['schema'] = 2;
      await writeState(db, legacy);
    }
  },
);

/// 大对象编码在 isolate 执行，UI isolate 只处理差异键与一次 SQL batch。
Json encodePersistence((Json, bool) input) {
  final state = input.$1;
  final prefs = Map<String, dynamic>.from(state)
    ..remove('ledgers')
    ..remove('importDrafts');
  return {
    'preferences': jsonEncode(prefs),
    'widgetScope': {
      'active': state['active'],
      'revision': state['dataRevision'] ?? 0,
    },
    if (state.containsKey('importDrafts'))
      'drafts': {
        for (final d in state['importDrafts'] ?? []) d['id']: jsonEncode(d),
      },
    if (!input.$2)
      'ledgers': [
        for (final l in state['ledgers'])
          {
            'id': l['id'],
            'body': jsonEncode(
              Map<String, dynamic>.from(l)
                ..remove('entries')
                ..remove('pending'),
            ),
            'entries': {
              for (final e in l['entries'])
                e['id']: {
                  'kind': e['kind'],
                  'book_date': e['data']['date'],
                  'body': jsonEncode(e),
                },
            },
            'pending': [
              for (final op in l['pending'])
                {'id': op['operation_id'], 'body': jsonEncode(op)},
            ],
          },
      ],
  };
}

class StateWriter {
  Json? last;
  int lastEntryWrites = 0;
  Future<void> write(
    Database db,
    Json next, {
    bool preferencesOnly = false,
  }) async {
    final previous = {for (final l in last?['ledgers'] ?? []) l['id']: l};
    var writes = 0;
    await db.transaction((txn) async {
      final batch = txn.batch();
      if (last?['preferences'] != next['preferences']) {
        batch.insert('preferences', {
          'id': 1,
          'body': next['preferences'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (next['drafts'] is Map) {
        for (final row in await txn.query('import_drafts', columns: ['id'])) {
          if (!(next['drafts'] as Map).containsKey(row['id'])) {
            batch.delete(
              'import_drafts',
              where: 'id=?',
              whereArgs: [row['id']],
            );
          }
        }
        for (final e in (next['drafts'] as Map).entries) {
          if (last?['drafts']?[e.key] != e.value) {
            batch.insert('import_drafts', {
              'id': e.key,
              'body': e.value,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
      if (!preferencesOnly) {
        final nextIds = {for (final l in next['ledgers']) l['id']};
        final storedIds = (await txn.query(
          'ledgers',
          columns: ['id'],
        )).map((r) => r['id']);
        for (final id in storedIds.where((id) => !nextIds.contains(id))) {
          batch.delete('entries', where: 'ledger_id=?', whereArgs: [id]);
          batch.delete('outbox', where: 'ledger_id=?', whereArgs: [id]);
          batch.delete('ledgers', where: 'id=?', whereArgs: [id]);
        }
        for (final l in next['ledgers']) {
          final old = previous[l['id']];
          if (old?['body'] != l['body']) {
            batch.insert('ledgers', {
              'id': l['id'],
              'body': l['body'],
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          final oldEntries = old?['entries'] as Map? ?? {};
          final entries = l['entries'] as Map;
          for (final item in entries.entries) {
            if (oldEntries[item.key]?['body'] == item.value['body']) continue;
            writes++;
            batch.insert('entries', {
              'ledger_id': l['id'],
              'id': item.key,
              ...item.value as Map<String, dynamic>,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          // 首次写入时读取主键，不将所有 JSON body 从数据库传回 UI。
          final oldIds = old == null
              ? (await txn.query(
                  'entries',
                  columns: ['id'],
                  where: 'ledger_id=?',
                  whereArgs: [l['id']],
                )).map((e) => e['id'])
              : oldEntries.keys;
          for (final id in oldIds) {
            if (!entries.containsKey(id)) {
              batch.delete(
                'entries',
                where: 'ledger_id=? AND id=?',
                whereArgs: [l['id'], id],
              );
            }
          }
          if (jsonEncode(old?['pending']) != jsonEncode(l['pending'])) {
            batch.delete('outbox', where: 'ledger_id=?', whereArgs: [l['id']]);
            var i = 0;
            for (final op in l['pending']) {
              batch.insert('outbox', {
                'ledger_id': l['id'],
                'id': op['id'],
                'position': i++,
                'body': op['body'],
              });
            }
          }
        }
      }
      await batch.commit(noResult: true);
    });
    lastEntryWrites = writes;
    last = preferencesOnly
        ? {...?last, ...next}
        : {
            ...next,
            if (next['drafts'] == null && last?['drafts'] != null)
              'drafts': last!['drafts'],
          };
  }
}
