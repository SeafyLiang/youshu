import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';
import 'ui.dart';

Future<void> openExternal(String value) async {
  final uri = Uri.parse(value);
  if (!['https', 'mailto'].contains(uri.scheme) || uri.userInfo.isNotEmpty) {
    throw const FormatException('链接无效');
  }
  if (await system.invokeMethod<bool>('openExternal', value) != true) {
    await Clipboard.setData(ClipboardData(text: value));
    notifyApp('链接已复制');
  }
}

class TrashPage extends StatefulWidget {
  final LedgerStore s;
  const TrashPage(this.s, {super.key});
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final selected = <String>{};
  bool working = false;
  LedgerStore get s => widget.s;
  List<Json> get items => [
    for (final l in s.trashBooks)
      {
        'key': 'book:${l['id']}',
        'book': l,
        'title': l['name'],
        'at': l['deleted_at'],
      },
    for (final l in s.ledgers)
      for (final e in s.trashEntries(l))
        {
          'key': '${l['id']}/${e['id']}',
          'book': l,
          'entry': e,
          'title':
              '${categoryName(l, e['data'])} · ${formatAmount(e['data']['amount'], e['data']['base_currency'])}',
          'at': e['data']['deleted_at'],
        },
  ];
  Future<void> apply(bool restore, {bool all = false}) async {
    final rows = items
        .where((i) => all || selected.contains(i['key']))
        .toList();
    if (rows.isEmpty) return;
    if (!restore &&
        !await approve(context, '永久删除 ${rows.length} 项？', '删除后无法从回收站恢复。')) {
      return;
    }
    setState(() => working = true);
    try {
      for (final row in rows) {
        final l = row['book'] as Json, e = row['entry'] as Json?;
        if (restore) {
          if (e == null) {
            await s.restoreBook(l);
          } else if (s.trashEntries(l).any((v) => v['id'] == e['id'])) {
            await s.restoreTrashEntry(l, e);
          }
        } else {
          await s.purgeTrash(book: l, entry: e);
        }
      }
      selected.clear();
      notifyApp(restore ? '已恢复' : '已永久删除');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: s,
    builder: (c, _) {
      final rows = items;
      return Scaffold(
        appBar: AppBar(
          title: const Text('回收站'),
          actions: [
            TextButton(
              onPressed: working ? null : () => apply(false, all: true),
              child: const Text('清空'),
            ),
          ],
        ),
        body: rows.isEmpty
            ? const Center(child: Text('回收站为空'))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (c, i) {
                  final row = rows[i];
                  return CheckboxListTile(
                    value: selected.contains(row['key']),
                    onChanged: working
                        ? null
                        : (v) => setState(
                            () => v == true
                                ? selected.add(row['key'])
                                : selected.remove(row['key']),
                          ),
                    title: Text(row['title']),
                    subtitle: Text(
                      '${row['book']['name']} · ${30 - DateTime.now().toUtc().difference(DateTime.parse(row['at'])).inDays.clamp(0, 30)}天后清理',
                    ),
                    secondary: Icon(
                      row['entry'] == null
                          ? Icons.menu_book_outlined
                          : Icons.receipt_long_outlined,
                    ),
                  );
                },
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: working || selected.isEmpty
                        ? null
                        : () => apply(false),
                    child: const Text('永久删除'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: working || selected.isEmpty
                        ? null
                        : () => apply(true),
                    child: const Text('恢复'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class BackupHistoryPage extends StatefulWidget {
  final LedgerStore s;
  const BackupHistoryPage(this.s, {super.key});
  @override
  State<BackupHistoryPage> createState() => _BackupHistoryPageState();
}

class _BackupHistoryPageState extends State<BackupHistoryPage> {
  late Future<List<Json>> future = widget.s.backupHistory();
  bool working = false;
  Future<void> act(Json m, bool restore) async {
    if (!await approve(
      context,
      restore ? '恢复备份？' : '删除备份？',
      restore ? '恢复为独立本地副本。' : '永久删除这份远端备份。',
    )) {
      return;
    }
    setState(() => working = true);
    try {
      if (restore) {
        await widget.s.restore(m['manifest']);
      } else {
        await widget.s.deleteBackup(m);
      }
      notifyApp(restore ? '已恢复为副本' : '备份已删除');
      if (mounted) setState(() => future = widget.s.backupHistory());
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('历史备份'),
      actions: [
        IconButton(
          onPressed: working
              ? null
              : () => setState(() => future = widget.s.backupHistory()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<Json>>(
      future: future,
      builder: (c, snap) {
        if (snap.hasError) return Center(child: Text('读取失败，点击刷新重试'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) return const Center(child: Text('暂无备份'));
        return ListView.builder(
          itemCount: snap.data!.length,
          itemBuilder: (c, i) {
            final m = snap.data![i];
            return panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (m['createdAt'] ?? m['manifest'])
                        .toString()
                        .replaceAll('T', ' ')
                        .split('.')
                        .first,
                  ),
                  Text(
                    '${m['platform'] ?? '旧版本'} · ${m['trigger'] == 'auto' ? '自动' : '手动'} · ${m['bytes'] == null ? '' : '${((m['bytes'] as num) / 1024).toStringAsFixed(0)} KB'}',
                    style: TextStyle(color: secondaryInk(c), fontSize: 12),
                  ),
                  if (m['invalid'] == true)
                    const Text('清单不可读')
                  else
                    Row(
                      children: [
                        TextButton(
                          onPressed: working ? null : () => act(m, true),
                          child: const Text('恢复副本'),
                        ),
                        TextButton(
                          onPressed: working ? null : () => act(m, false),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
