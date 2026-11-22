import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import 'belongings_store.dart';
import 'belongings_page.dart';
import 'store.dart' show LedgerStore;

class BelongingsBackupPage extends StatefulWidget {
  final BelongingsStore store;
  final LedgerStore ledger;
  const BelongingsBackupPage(this.store, this.ledger, {super.key});
  @override
  State<BelongingsBackupPage> createState() => _BelongingsBackupPageState();
}

class _BelongingsBackupPageState extends State<BelongingsBackupPage> {
  bool busy = false;
  List<String>? files;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) bToast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore(Uint8List bytes) async {
    final p = BelongingsStore.inspectBackup(bytes);
    if (!mounted) return;
    if (!await bConfirm(
      context,
      '恢复物品副本？',
      '包含 ${p.items.length} 件物品、${p.costs.length} 条养护记录、${p.media.length} 张图片。将全部创建为副本，不覆盖已有物品；副本的到期提醒默认关闭。',
    )) {
      return;
    }
    await widget.store.restoreCopies(p);
    if (mounted) bToast(context, '已恢复 ${p.items.length} 件物品副本');
  }

  Future<void> listRemote() async {
    final res = await widget.ledger.dav(
      'PROPFIND',
      '/yousu-belongings/',
      body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>',
      extra: {'Depth': '1', 'Content-Type': 'application/xml'},
    );
    final names =
        XmlDocument.parse(res.body).descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'href')
            .map((e) => Uri.decodeComponent(e.innerText.split('/').last))
            .where((v) => RegExp(r'^[\w.\-]+\.manifest\.json$').hasMatch(v))
            .toList()
          ..sort((a, b) => b.compareTo(a));
    if (mounted) setState(() => files = names);
  }

  Future<void> upload() async {
    final bytes = await widget.store.exportBackup();
    final directory = await Directory.systemTemp.createTemp(
      'belongings-upload-',
    );
    try {
      final id =
              '${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}-${const Uuid().v4()}',
          name = '$id.items.json';
      final f = File('${directory.path}/upload.json');
      await f.writeAsBytes(bytes);
      await widget.ledger.dav('MKCOL', '/yousu-belongings');
      await widget.ledger.davFile(
        'PUT',
        '/yousu-belongings/$name',
        f,
        maxBytes: belongingsBackupLimit,
      );
      final downloaded = File('${directory.path}/verify.json');
      await widget.ledger.davFile(
        'GET',
        '/yousu-belongings/$name',
        downloaded,
        maxBytes: belongingsBackupLimit,
      );
      final hash = sha256.convert(bytes).toString();
      if (sha256.convert(await downloaded.readAsBytes()).toString() != hash) {
        throw const FormatException('上传校验失败');
      }
      await widget.ledger.dav(
        'PUT',
        '/yousu-belongings/$id.manifest.json',
        body: jsonEncode({'file': name, 'sha256': hash, 'bytes': bytes.length}),
        extra: {'Content-Type': 'application/json', 'If-None-Match': '*'},
      );
      if (mounted) bToast(context, '物品与图片已备份到 WebDAV');
      await listRemote();
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<void> restoreRemote(String manifest) async {
    final response = await widget.ledger.dav(
      'GET',
      '/yousu-belongings/$manifest',
    );
    final p = jsonDecode(response.body) as Map;
    final name = p['file'];
    if (name is! String || !RegExp(r'^[\w.\-]+\.items\.json$').hasMatch(name)) {
      throw const FormatException('远端备份路径无效');
    }
    final directory = await Directory.systemTemp.createTemp(
      'belongings-download-',
    );
    try {
      final file = File('${directory.path}/backup.json');
      await widget.ledger.davFile(
        'GET',
        '/yousu-belongings/$name',
        file,
        maxBytes: belongingsBackupLimit,
      );
      final bytes = await file.readAsBytes();
      if (bytes.length != p['bytes'] ||
          sha256.convert(bytes).toString() != p['sha256']) {
        throw const FormatException('远端备份校验失败');
      }
      await restore(bytes);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('物品数据备份')),
    body: AbsorbPointer(
      absorbing: busy,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          bCard(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '物品独立保存',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                bCaption(
                  '物品、维修记录、照片和凭证一起备份。与账本数据分开；换机时请分别备份与恢复。本页为手动备份，单份上限 80 MB。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('保存物品备份到文件'),
            subtitle: const Text('包含全部物品及引用的图片'),
            onTap: () => run(() async {
              final bytes = await widget.store.exportBackup();
              final path = await FilePicker.saveFile(
                dialogTitle: '保存物品备份',
                fileName: '有数物品-${bDay()}.json',
                bytes: bytes,
              );
              if (path != null && context.mounted) bToast(context, '物品备份已保存');
            }),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('从文件恢复副本'),
            subtitle: const Text('先校验，再确认恢复'),
            onTap: () => run(() async {
              final result = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['json'],
              );
              if (result.isEmpty) return;
              final selected = result.single;
              if ((await selected.length() ?? 0) > belongingsBackupLimit) {
                throw const FormatException('备份超过 80 MB');
              }
              await restore(await selected.readAsBytes());
            }),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('备份到 WebDAV'),
            subtitle: const Text('沿用“我的”中设置的连接，保存至独立目录'),
            onTap: () => run(upload),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('查看 WebDAV 物品备份'),
            onTap: () => run(listRemote),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (files != null && files!.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('暂无物品备份')),
          ...?files?.map(
            (f) => ListTile(
              title: Text(f.split('T').first),
              subtitle: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.restore),
              onTap: () => run(() => restoreRemote(f)),
            ),
          ),
          const SizedBox(height: 16),
          bCaption('备份文件含图片和备注，请保存在私人位置。删除物品不会删除你已经保存的备份。'),
        ],
      ),
    ),
  );
}
