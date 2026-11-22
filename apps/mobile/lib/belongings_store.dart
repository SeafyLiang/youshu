import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'belongings_domain.dart';
export 'belongings_domain.dart';

const belongingsBackupLimit = 80 * 1024 * 1024;

class BelongingsBackup {
  final List<Belonging> items;
  final List<BelongingCost> costs;
  final Map<String, Uint8List> media;
  final String createdAt;
  BelongingsBackup(this.items, this.costs, this.media, this.createdAt);
}

class BelongingsStore extends ChangeNotifier {
  final String path;
  final Directory mediaDirectory;
  Database? _db;
  Future<void>? _opening;
  Future<void> _tail = Future.value();
  List<Belonging> items = [];
  List<BelongingCost> costs = [];
  int revision = 0;
  bool closed = false;
  BelongingsStore(this.path) : mediaDirectory = Directory('$path.media');
  Future<void> open() {
    if (closed) return Future.error(StateError('物品数据库已关闭'));
    return _opening ??= _open().catchError((Object e) {
      _opening = null;
      throw e;
    });
  }

  Future<void> _open() async {
    if (_db != null) return;
    await mediaDirectory.create(recursive: true);
    _db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: (db, v) async {
        await db.execute(
          'CREATE TABLE items (id TEXT PRIMARY KEY, body TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE costs (id TEXT PRIMARY KEY,item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE, body TEXT NOT NULL)',
        );
        await db.execute('CREATE INDEX costs_item ON costs(item_id)');
      },
    );
    try {
      await _reload();
    } catch (_) {
      await _db?.close();
      _db = null;
      rethrow;
    }
  }

  Future<void> _reload() async {
    final result = await _db!.transaction(
      (tx) async => (await tx.query('items'), await tx.query('costs')),
    );
    items = result.$1
        .map((r) => Belonging(jsonDecode(r['body'] as String)))
        .toList();
    costs = result.$2
        .map((r) => BelongingCost(jsonDecode(r['body'] as String)))
        .toList();
    revision++;
    if (!closed) notifyListeners();
  }

  Future<T> _write<T>(Future<T> Function(Database) action) {
    final job = _tail.then((_) async {
      await open();
      final result = await action(_db!);
      await _reload();
      return result;
    });
    _tail = job.then<void>((_) {}).catchError((Object _) {});
    return job;
  }

  List<BelongingCost> costsFor(String id) =>
      costs.where((c) => c.itemId == id).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  Belonging item(String id) => items.firstWhere((i) => i.id == id);
  File mediaFile(String id) {
    if (!validMediaId(id)) throw const FormatException('图片路径无效');
    return File(p.join(mediaDirectory.path, id));
  }

  Future<String> addMedia(Uint8List bytes) async {
    await open();
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('图片不能超过 10 MB');
    }
    final id = '${sha256.convert(bytes)}.png', file = mediaFile(id);
    if (!await file.exists()) {
      final temp = File('${file.path}.${const Uuid().v4()}.tmp');
      try {
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
    return id;
  }

  Future<void> _checkMedia(Iterable<String> ids) async {
    for (final id in ids) {
      if (!await mediaFile(id).exists()) {
        throw const FormatException('物品图片缺失，无法保存');
      }
    }
  }

  Future<void> saveItem(Belonging item) => _write((db) async {
    item.validate();
    await _checkMedia(item.media);
    await db.transaction((tx) async {
      final rows = await tx.query('items', where: 'id=?', whereArgs: [item.id]);
      if (rows.isNotEmpty) {
        final old = Belonging(jsonDecode(rows.first['body'] as String));
        if (old.revision != item.revision) {
          throw const FormatException('物品已更新，请返回后重试');
        }
      } else if (item.revision != 0) {
        throw const FormatException('物品已删除');
      }
      final related = await tx.query(
        'costs',
        where: 'item_id=?',
        whereArgs: [item.id],
      );
      for (final c in related) {
        BelongingCost(jsonDecode(c['body'] as String)).validate(item);
      }
      final row = {
        'id': item.id,
        'body': jsonEncode({...item.data, 'revision': item.revision + 1}),
      };
      if (rows.isEmpty) {
        await tx.insert('items', row);
      } else {
        await tx.update('items', row, where: 'id=?', whereArgs: [item.id]);
      }
    });
  });
  Future<void> saveCost(BelongingCost cost) => _write((db) async {
    if (cost.receipt != null) await _checkMedia([cost.receipt!]);
    await db.transaction((tx) async {
      final itemRows = await tx.query(
        'items',
        where: 'id=?',
        whereArgs: [cost.itemId],
      );
      if (itemRows.isEmpty) throw const FormatException('所属物品已删除');
      cost.validate(Belonging(jsonDecode(itemRows.first['body'] as String)));
      final rows = await tx.query('costs', where: 'id=?', whereArgs: [cost.id]);
      if (rows.isNotEmpty) {
        final old = BelongingCost(jsonDecode(rows.first['body'] as String));
        if (old.revision != cost.revision || old.itemId != cost.itemId) {
          throw const FormatException('费用已更新，请重试');
        }
      } else if (cost.revision != 0) {
        throw const FormatException('费用已删除');
      }
      await tx.insert('costs', {
        'id': cost.id,
        'item_id': cost.itemId,
        'body': jsonEncode({...cost.data, 'revision': cost.revision + 1}),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  });
  Future<void> deleteCost(BelongingCost cost) => _write((db) async {
    await db.transaction((tx) async {
      final rows = await tx.query('costs', where: 'id=?', whereArgs: [cost.id]);
      if (rows.isEmpty) return;
      if (BelongingCost(jsonDecode(rows.first['body'] as String)).revision !=
          cost.revision) {
        throw const FormatException('费用已变化，请重新核对');
      }
      await tx.delete('costs', where: 'id=?', whereArgs: [cost.id]);
    });
  });
  Future<void> deleteItem(Belonging value) => _write((db) async {
    final rows = await db.query('items', where: 'id=?', whereArgs: [value.id]);
    if (rows.isEmpty) return;
    if (Belonging(jsonDecode(rows.first['body'] as String)).revision !=
        value.revision) {
      throw const FormatException('物品已变化，请重新核对');
    }
    await db.delete('items', where: 'id=?', whereArgs: [value.id]);
    // Immutable image files are retained; deleting one item cannot damage another reference.
  });
  Future<Uint8List> exportBackup() async {
    await open();
    await _tail;
    final snapshot = await _db!.transaction(
      (tx) async => (await tx.query('items'), await tx.query('costs')),
    );
    final objects = snapshot.$1
        .map((r) => Belonging(jsonDecode(r['body'] as String)))
        .toList();
    final expenses = snapshot.$2
        .map((r) => BelongingCost(jsonDecode(r['body'] as String)))
        .toList();
    final refs = <String>{
      ...objects.expand((i) => i.media),
      ...expenses.map((c) => c.receipt).whereType<String>(),
    };
    final media = <String, String>{};
    var bytesCount = 0;
    for (final id in refs) {
      final bytes = await mediaFile(id).readAsBytes();
      bytesCount += bytes.length;
      if (bytesCount > 55 * 1024 * 1024) {
        throw const FormatException('图片较多，本次备份超过 80 MB 限制');
      }
      if ('${sha256.convert(bytes)}.png' != id) {
        throw const FormatException('本机图片校验失败');
      }
      media[id] = base64Encode(bytes);
    }
    final payload = {
      'items': objects.map((i) => i.data).toList(),
      'costs': expenses.map((c) => c.data).toList(),
      'media': media,
    };
    final encoded = utf8.encode(jsonEncode(payload));
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'youshu-belongings',
          'version': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'sha256': sha256.convert(encoded).toString(),
          'data': payload,
        }),
      ),
    );
    if (bytes.length > belongingsBackupLimit) {
      throw const FormatException('物品备份超过 80 MB');
    }
    return bytes;
  }

  static BelongingsBackup inspectBackup(Uint8List bytes) {
    if (bytes.length > belongingsBackupLimit) {
      throw const FormatException('物品备份超过 80 MB');
    }
    try {
      final root = jsonDecode(utf8.decode(bytes)) as BJson;
      if (root['format'] != 'youshu-belongings' || root['version'] != 1) {
        throw const FormatException('请选择有数物品备份，账本备份请到我的页面恢复');
      }
      final d = root['data'] as BJson;
      if (sha256.convert(utf8.encode(jsonEncode(d))).toString() !=
          root['sha256']) {
        throw const FormatException('备份校验失败');
      }
      final objects = (d['items'] as List)
          .map((r) => Belonging(Map<String, dynamic>.from(r)))
          .toList();
      final expenses = (d['costs'] as List)
          .map((r) => BelongingCost(Map<String, dynamic>.from(r)))
          .toList();
      final byId = {for (final i in objects) i.id: i};
      if (byId.length != objects.length ||
          expenses.map((c) => c.id).toSet().length != expenses.length) {
        throw const FormatException('备份包含重复编号');
      }
      for (final i in objects) {
        i.validate();
      }
      for (final c in expenses) {
        if (!byId.containsKey(c.itemId)) {
          throw const FormatException('费用所属物品缺失');
        }
        c.validate(byId[c.itemId]!);
      }
      final media = <String, Uint8List>{};
      for (final entry in (d['media'] as Map).entries) {
        if (entry.key is! String || !validMediaId(entry.key)) {
          throw const FormatException('图片路径无效');
        }
        final raw = base64Decode(entry.value);
        if (raw.length > 10 * 1024 * 1024 ||
            '${sha256.convert(raw)}.png' != entry.key) {
          throw const FormatException('图片校验失败');
        }
        media[entry.key] = raw;
      }
      final refs = {
        ...objects.expand((i) => i.media),
        ...expenses.map((c) => c.receipt).whereType<String>(),
      };
      if (!media.keys.toSet().containsAll(refs)) {
        throw const FormatException('备份缺少图片');
      }
      return BelongingsBackup(
        objects,
        expenses,
        media,
        root['createdAt'] as String,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('物品备份格式无效');
    }
  }

  Future<void> restoreCopies(BelongingsBackup backup) => _write((db) async {
    // Media names are content hashes; staging cannot replace unrelated user data.
    for (final entry in backup.media.entries) {
      final f = mediaFile(entry.key);
      if (await f.exists()) {
        if (sha256.convert(await f.readAsBytes()).toString() !=
            entry.key.split('.').first) {
          throw const FormatException('本机图片校验失败');
        }
      } else {
        await f.writeAsBytes(entry.value, flush: true);
      }
    }
    final ids = {for (final i in backup.items) i.id: const Uuid().v4()};
    await db.transaction((tx) async {
      for (final i in backup.items) {
        final id = ids[i.id]!;
        final copied = Belonging({
          ...i.data,
          'id': id,
          'name':
              '${i.name.length > 70 ? i.name.substring(0, 70) : i.name}（恢复）',
          'remind': -1,
          'revision': 1,
        });
        copied.validate();
        await tx.insert('items', {'id': id, 'body': jsonEncode(copied.data)});
      }
      for (final c in backup.costs) {
        final id = const Uuid().v4();
        await tx.insert('costs', {
          'id': id,
          'item_id': ids[c.itemId],
          'body': jsonEncode({
            ...c.data,
            'id': id,
            'itemId': ids[c.itemId],
            'revision': 1,
          }),
        });
      }
    });
  });
  Future<void> close() async {
    await _tail;
    closed = true;
    await _db?.close();
    _db = null;
    super.dispose();
  }
}
