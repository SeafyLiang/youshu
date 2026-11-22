import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'import_page.dart';
import 'store.dart';
import 'ui.dart';

Future<T?> openDataPage<T>(BuildContext context, Widget page) =>
    Navigator.push<T>(context, AppPageRoute<T>(builder: (_) => page));

Widget dataGroup(String title, List<Widget> rows) => Padding(
  padding: const EdgeInsets.only(top: 16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 3, bottom: 6),
        child: hint(title),
      ),
      GlassPanel(
        radius: 20,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15),
                  child: Divider(height: 1),
                ),
              rows[i],
            ],
          ],
        ),
      ),
    ],
  ),
);

Widget dataRow(
  String title,
  IconData icon, {
  String? subtitle,
  String? value,
  VoidCallback? onTap,
}) => ListTile(
  minTileHeight: 54,
  leading: Icon(icon, size: 21),
  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
  subtitle: subtitle == null ? null : Text(subtitle),
  trailing: value != null
      ? Text(value)
      : onTap == null
      ? null
      : const Icon(CupertinoIcons.chevron_right, size: 14),
  onTap: onTap,
);

String dataTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '时间未知';
  return date.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
}

Widget localSummary(BuildContext c, String title, String detail) => GlassPanel(
  radius: 18,
  color: Theme.of(c).colorScheme.primaryContainer,
  child: ListTile(
    leading: Icon(CupertinoIcons.checkmark_shield, color: expenseInk(c)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(detail),
  ),
);

String localCounts(LedgerStore s) =>
    '${s.ledgers.length} 本账 · ${s.ledgers.fold<int>(0, (n, b) => n + s.records(b).length)} 笔流水';

Widget dataScaffold(
  String title,
  List<Widget> children, {
  Widget? footer,
  List<Widget> actions = const [],
}) => Scaffold(
  appBar: AppBar(title: Text(title), actions: actions),
  body: SafeArea(
    bottom: footer == null,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: children,
    ),
  ),
  bottomNavigationBar: footer == null
      ? null
      : SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: footer,
          ),
        ),
);

class DataPage extends StatelessWidget {
  final LedgerStore s;
  const DataPage(this.s, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) => dataScaffold('导入与导出', [
      localSummary(context, '本机账本', localCounts(s)),
      dataGroup('账单文件', [
        dataRow(
          '导入账单',
          CupertinoIcons.square_arrow_down,
          subtitle: '微信、支付宝、随手记',
          onTap: () => openDataPage(context, ImportPage(s)),
        ),
        dataRow(
          '导出流水',
          CupertinoIcons.square_arrow_up,
          subtitle: '选择范围，保存 CSV',
          onTap: () => openDataPage(context, ExportEntriesPage(s)),
        ),
        dataRow(
          '导入记录',
          CupertinoIcons.time,
          subtitle: '核对草稿与导入批次',
          onTap: () => openDataPage(context, ImportHistoryPage(s)),
        ),
      ]),
      dataGroup('完整账本', [
        dataRow(
          '备份与恢复',
          CupertinoIcons.archivebox,
          subtitle: '包括分类、预算及关联记录',
          onTap: () => openDataPage(context, BackupsPage(s)),
        ),
      ]),
    ]),
  );
}

class ExportEntriesPage extends StatefulWidget {
  final LedgerStore s;
  final String? period;
  final Map<String, Set<String>>? filtered;
  const ExportEntriesPage(this.s, {super.key, this.period, this.filtered});
  @override
  State<ExportEntriesPage> createState() => _ExportEntriesPageState();
}

class _ExportEntriesPageState extends State<ExportEntriesPage> {
  LedgerStore get s => widget.s;
  late String bookId = s.active['id'];
  late String scope = widget.filtered?.containsKey(bookId) == true
      ? 'filtered'
      : 'period';
  bool working = false;

  Future<void> save(Json book, List<Json> rows, BookPeriod period) async {
    setState(() => working = true);
    try {
      final bytes = await s.exportCsv(book, rows);
      final stamp = switch (scope) {
        'all' => '全部流水',
        'filtered' => '筛选流水',
        _ => period.start,
      };
      final name = book['name'].toString().replaceAll(
        RegExp(r'[\/\\:*?"<>|\r\n]'),
        '_',
      );
      final file = await FilePicker.saveFile(
        fileName: '有数_${name}_$stamp.csv',
        bytes: bytes,
        mimeType: 'text/csv',
      );
      if (mounted && file != null) notifyApp('已保存 ${rows.length} 笔流水');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = s.ledgers.firstWhere(
      (b) => b['id'] == bookId,
      orElse: () => s.active,
    );
    final period = s.period(widget.period ?? today(), ledger: book);
    final all = s.records(book);
    final current = ledgerIndex(book).between(period.start, period.end);
    final selected = widget.filtered?[book['id']];
    final filters = selected == null
        ? null
        : all.where((e) => selected.contains(e['id'])).toList();
    final options = <(String, String, String, List<Json>)>[
      ('period', '本期流水', period.label, current),
      ('all', '全部流水', '不限日期和类型', all),
      if (filters != null) ('filtered', '当前筛选', '流水页筛选结果', filters),
    ];
    final rows = options
        .firstWhere((o) => o.$1 == scope, orElse: () => options.first)
        .$4;
    return dataScaffold(
      '导出流水',
      [
        GlassPanel(
          radius: 20,
          child: dataRow(
            '流水表格',
            CupertinoIcons.doc_text,
            subtitle: 'CSV · 可用表格软件打开',
          ),
        ),
        dataGroup('账本', [
          Padding(
            padding: const EdgeInsets.all(13),
            child: DropdownButtonFormField<String>(
              initialValue: book['id'],
              decoration: const InputDecoration(labelText: '导出账本'),
              items: [
                for (final v in s.ledgers)
                  DropdownMenuItem(
                    value: v['id'] as String,
                    child: Text(v['name']),
                  ),
              ],
              isExpanded: true,
              onChanged: working
                  ? null
                  : (id) => setState(() {
                      bookId = id!;
                      if (scope == 'filtered' &&
                          widget.filtered?.containsKey(bookId) != true) {
                        scope = 'period';
                      }
                    }),
            ),
          ),
        ]),
        dataGroup('导出范围', [
          RadioGroup<String>(
            groupValue: scope,
            onChanged: (next) {
              if (!working && next != null) setState(() => scope = next);
            },
            child: Column(
              children: [
                for (final o in options)
                  RadioListTile<String>(
                    value: o.$1,
                    enabled: !working,
                    title: Text(o.$2),
                    subtitle: Text('${o.$3} · ${o.$4.length} 笔'),
                  ),
              ],
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 3),
          child: hint('CSV 包含日期、类型、分类、账户、金额、币种和备注。换机请保存账本备份。'),
        ),
      ],
      footer: FilledButton(
        onPressed: working || rows.isEmpty
            ? null
            : () => save(book, rows, period),
        child: Text(working ? '正在导出' : '导出 ${rows.length} 笔流水'),
      ),
    );
  }
}

class ImportHistoryPage extends StatelessWidget {
  final LedgerStore s;
  const ImportHistoryPage(this.s, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) {
      final drafts = (s.state['importDrafts'] as List? ?? [])
          .cast<Json>()
          .reversed
          .where(
            (d) => (d['rows'] as List).any(
              (r) => ['ready', 'review'].contains(r['status']),
            ),
          );
      return dataScaffold('导入记录', [
        dataGroup('导入批次', [
          if (s.importBatches.isEmpty)
            dataRow('暂无导入记录', CupertinoIcons.doc_text),
          for (final batch in s.importBatches)
            dataRow(
              batch['file']?.toString() ?? '账单',
              CupertinoIcons.doc_on_doc,
              subtitle:
                  '${dataTime(batch['at'])} · ${batch['count']} 笔'
                  '${batch['undone_at'] == null ? '' : ' · 已撤销 ${batch['undone_count']} 笔'}',
              onTap: () => openDataPage(context, _ImportBatchPage(s, batch)),
            ),
        ]),
        dataGroup('待核对草稿', [
          if (drafts.isEmpty) dataRow('暂无待核对账目', CupertinoIcons.doc_text),
          for (final d in drafts)
            dataRow(
              d['file'].toString(),
              CupertinoIcons.doc_text,
              subtitle:
                  '${(d['rows'] as List).where((row) => row['status'] == 'review').length} 笔待核对',
              onTap: () =>
                  openDataPage(context, ImportPage(s, initialDraft: d)),
            ),
        ]),
      ]);
    },
  );
}

class _ImportBatchPage extends StatefulWidget {
  final LedgerStore s;
  final Json batch;
  const _ImportBatchPage(this.s, this.batch);
  @override
  State<_ImportBatchPage> createState() => _ImportBatchPageState();
}

class _ImportBatchPageState extends State<_ImportBatchPage> {
  bool working = false;
  Future<void> undo(Json batch) async {
    setState(() => working = true);
    try {
      final preview = await widget.s.previewImportUndo(batch);
      if (!mounted) return;
      if (preview.count == 0) {
        notifyApp('本批次没有可撤销的流水');
        return;
      }
      if (!await approve(
        context,
        '移入回收站 ${preview.count} 笔？',
        '${preview.kept == 0 ? '' : '保留 ${preview.kept} 笔已变更、已移除或有关联退款的流水。'}移入回收站后仍可恢复。',
      )) {
        return;
      }
      await widget.s.undoImportBatch(preview);
      if (mounted) notifyApp('已移入回收站 ${preview.count} 笔');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.batch['batch_id'];
    final batch = id == null
        ? widget.batch
        : widget.s.importBatches
                  .where((b) => b['batch_id'] == id)
                  .firstOrNull ??
              widget.batch;
    final rows = <(Json, Json)>[];
    for (final b in widget.s.allLedgers) {
      final ids = importBatchMemberIds(batch, b);
      if (ids.isEmpty) continue;
      for (final row in (b['entries'] as List).cast<Json>()) {
        if (row['kind'] == 'entry' && ids.contains(row['id'])) {
          rows.add((b, row));
        }
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('导入批次')),
      body: SafeArea(
        bottom: false,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return GlassPanel(
                radius: 18,
                child: dataRow(
                  batch['file']?.toString() ?? '账单',
                  CupertinoIcons.doc_on_doc,
                  subtitle:
                      '${batch['count']} 笔 · ${dataTime(batch['at'])}'
                      '${batch['undone_at'] == null ? '' : '\n已撤销 ${batch['undone_count']} 笔'}',
                ),
              );
            }
            final (book, row) = rows[i - 1];
            final d = row['data'] as Json;
            return dataRow(
              categoryName(book, d),
              CupertinoIcons.doc_text,
              subtitle:
                  '${d['date'] ?? ''} · ${book['name']}${row['deleted'] == true ? ' · 已移除' : ''}',
              value: d['amount'] == null
                  ? null
                  : formatAmount(d['amount'], d['base_currency'] ?? 'CNY'),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: FilledButton.tonal(
            onPressed:
                working || batch['refs'] == null || batch['undone_at'] != null
                ? null
                : () => undo(batch),
            child: Text(working ? '正在处理' : '预览撤销本批次'),
          ),
        ),
      ),
    );
  }
}

class BackupsPage extends StatefulWidget {
  final LedgerStore s;
  const BackupsPage(this.s, {super.key});
  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  LedgerStore get s => widget.s;
  late Future<Json> configuration = s.davSettings();
  bool saving = false;
  Future<void> saveFile() async {
    setState(() => saving = true);
    try {
      final bytes = await s.exportBackupFile();
      final file = await FilePicker.saveFile(
        fileName: '有数备份_${today()}.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (file != null && mounted) notifyApp('账本备份已保存到文件');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> settings() async {
    await openDataPage(context, _WebDavSettingsPage(s));
    if (mounted) setState(() => configuration = s.davSettings());
  }

  Future<void> backup() async {
    try {
      await s.backup();
      if (mounted) notifyApp('备份已校验');
    } catch (_) {
      // The backup card shows failure and retains the last verified version.
    }
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: s,
    builder: (c, _) => dataScaffold(
      '备份与恢复',
      [
        localSummary(c, '账本保存在本机', localCounts(s)),
        dataGroup('本地文件', [
          dataRow(
            '保存账本备份',
            CupertinoIcons.archivebox,
            subtitle: saving ? '正在生成备份' : '将账本保存到文件，可用于换机',
            onTap: saving ? null : saveFile,
          ),
          dataRow(
            '从备份恢复',
            CupertinoIcons.time,
            subtitle: '查看内容后恢复为独立副本',
            onTap: () => openDataPage(c, _RestoreSourcesPage(s)),
          ),
        ]),
        dataGroup('网络备份', [
          FutureBuilder<Json>(
            future: configuration,
            builder: (context, info) {
              final configured = info.data?['url'] != null;
              final last = s.state['lastBackup']?.toString() ?? '';
              final failed =
                  (s.state['backupError']?.toString() ?? '').isNotEmpty;
              final title = switch ((
                info.hasError,
                configured,
                info.connectionState,
              )) {
                (true, _, _) => '设置读取失败',
                (_, false, ConnectionState.waiting) => '正在读取设置',
                (_, false, _) => '未配置',
                _ when s.backupRunning => '正在备份',
                _ when failed => '备份失败',
                _ when last.isEmpty => '尚未备份',
                _ when s.state['backupDirty'] == true => '有更新待备份',
                _ => '已备份',
              };
              return Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.cloud, size: 19),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            'WebDAV 备份',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: failed && configured
                                  ? Theme.of(c).colorScheme.error
                                  : expenseInk(c),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (configured && last.isNotEmpty) ...[
                      hint('上次成功备份'),
                      Text(
                        '${dataTime(last)} · 已校验',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ] else
                      hint(
                        info.hasError
                            ? '请重新打开设置。本机账目可照常保存。'
                            : '使用你自己的 WebDAV 目录备份。',
                      ),
                    if (configured && failed) ...[
                      const SizedBox(height: 7),
                      Text(
                        '无法完成备份。本机账目可照常保存。',
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (configured)
                          FilledButton(
                            onPressed: s.backupRunning ? null : backup,
                            child: Text(failed ? '重试备份' : '立即备份'),
                          ),
                        FilledButton.tonal(
                          onPressed: s.backupRunning ? null : settings,
                          child: Text(configured ? '设置' : '设置 WebDAV'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ]),
      ],
      actions: [
        IconButton(
          icon: const Icon(CupertinoIcons.question_circle),
          tooltip: '查看备份内容',
          onPressed: () => showDialog<void>(
            context: c,
            builder: (context) => AlertDialog(
              title: const Text('备份内容'),
              content: const Text(
                '账本备份包括账本、分类、标签、预算、退款关联、回收站和导入草稿。物品及其照片请到物品页面单独备份。文件含账目内容，请保存在私人位置。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _WebDavSettingsPage extends StatefulWidget {
  final LedgerStore s;
  const _WebDavSettingsPage(this.s);
  @override
  State<_WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<_WebDavSettingsPage> {
  final url = TextEditingController(),
      user = TextEditingController(),
      password = TextEditingController(),
      limit = TextEditingController();
  bool loading = true, saving = false, auto = false;
  LedgerStore get s => widget.s;
  @override
  void initState() {
    super.initState();
    auto = s.state['autoBackup'] == true;
    limit.text = (s.state['backupKeep'] ?? 7).toString();
    load();
  }

  Future<void> load() async {
    try {
      final current = await s.davSettings();
      if (!mounted) return;
      url.text = current['url'] ?? '';
      user.text = current['name'] ?? '';
      password.text = current['password'] ?? '';
    } catch (_) {
      if (mounted) notifyApp('备份设置读取失败', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [url, user, password, limit]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final keep = int.tryParse(limit.text.trim());
    if (keep == null || keep < 1 || keep > 365) {
      notifyApp('每台设备保留数量须为 1–365', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      await s.configureDav(
        url.text.trim(),
        user.text.trim(),
        password.text,
        automatic: auto,
        keep: keep,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => dataScaffold(
    'WebDAV 设置',
    [
      if (loading) const LinearProgressIndicator(),
      GlassPanel(
        radius: 20,
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              enabled: !loading && !saving,
              decoration: const InputDecoration(labelText: '目录地址（HTTPS）'),
            ),
            TextField(
              controller: user,
              enabled: !loading && !saving,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            TextField(
              controller: password,
              enabled: !loading && !saving,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码或应用专用密码'),
            ),
          ],
        ),
      ),
      dataGroup('备份时机', [
        SwitchListTile(
          title: const Text('前台自动备份'),
          subtitle: const Text('有更新且网络可用时执行'),
          value: auto,
          onChanged: saving ? null : (v) => setState(() => auto = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 4, 15, 12),
          child: TextField(
            controller: limit,
            keyboardType: TextInputType.number,
            enabled: !saving,
            decoration: const InputDecoration(labelText: '每台设备保留份数'),
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: hint('使用自己的私人目录。留空地址并保存可断开此设备的配置，已备份文件仍保留。'),
      ),
    ],
    footer: FilledButton(
      onPressed: loading || saving ? null : save,
      child: Text(saving ? '正在保存' : '保存配置'),
    ),
  );
}

class _RestoreSourcesPage extends StatefulWidget {
  final LedgerStore s;
  const _RestoreSourcesPage(this.s);
  @override
  State<_RestoreSourcesPage> createState() => _RestoreSourcesPageState();
}

class _RestoreSourcesPageState extends State<_RestoreSourcesPage> {
  bool loading = false;
  Future<void> pick() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final out = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (out.length + chunk.length > portableBackupLimit) {
          throw const FormatException('备份文件不能超过 50 MB');
        }
        out.add(chunk);
      }
      final preview = await widget.s.inspectBackupFile(
        out.takeBytes(),
        file.name,
      );
      if (mounted) {
        await openDataPage(context, RestoreBackupPage(widget.s, preview));
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => dataScaffold('从备份恢复', [
    dataGroup('选择备份来源', [
      dataRow(
        '本地备份文件',
        CupertinoIcons.folder_open,
        subtitle: '选择有数的账本备份',
        onTap: loading ? null : pick,
      ),
      dataRow(
        'WebDAV 备份',
        CupertinoIcons.cloud,
        subtitle: '按设备及时间查看版本',
        onTap: loading
            ? null
            : () => openDataPage(context, _WebDavVersionsPage(widget.s)),
      ),
    ]),
    if (loading) const LinearProgressIndicator(),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: hint('恢复会创建账本副本，现有账本仍保留。'),
    ),
  ]);
}

class _WebDavVersionsPage extends StatefulWidget {
  final LedgerStore s;
  const _WebDavVersionsPage(this.s);
  @override
  State<_WebDavVersionsPage> createState() => _WebDavVersionsPageState();
}

class _WebDavVersionsPageState extends State<_WebDavVersionsPage> {
  late Future<List<Json>> versions = widget.s.backupHistory();
  bool loading = false;
  Future<void> preview(Json version) async {
    setState(() => loading = true);
    try {
      final result = await widget.s.inspectWebDavBackup(version['manifest']);
      if (mounted) {
        await openDataPage(context, RestoreBackupPage(widget.s, result));
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Json>>(
    future: versions,
    builder: (context, snapshot) => dataScaffold('选择 WebDAV 备份', [
      if (loading || snapshot.connectionState == ConnectionState.waiting)
        const LinearProgressIndicator(),
      if (snapshot.hasError) ...[
        const Text('读取备份失败。可以返回并选择本地文件。'),
        OutlinedButton(
          onPressed: () => setState(() => versions = widget.s.backupHistory()),
          child: const Text('重试读取'),
        ),
      ] else if (snapshot.hasData)
        dataGroup('可恢复的版本', [
          if (snapshot.data!.isEmpty)
            dataRow('这个目录暂无备份', CupertinoIcons.archivebox),
          for (final m in snapshot.data!)
            dataRow(
              m['invalid'] == true ? '清单不可读' : dataTime(m['createdAt']),
              CupertinoIcons.archivebox,
              subtitle:
                  '${m['platform'] ?? '旧版本'}'
                  '${m['device'] == null ? '' : ' · 设备 ${m['device'].toString().split('-').last}'}',
              onTap: loading || m['invalid'] == true ? null : () => preview(m),
            ),
        ]),
    ]),
  );
}

class RestoreBackupPage extends StatefulWidget {
  final LedgerStore s;
  final BackupPreview preview;
  const RestoreBackupPage(this.s, this.preview, {super.key});
  @override
  State<RestoreBackupPage> createState() => _RestoreBackupPageState();
}

class _RestoreBackupPageState extends State<RestoreBackupPage> {
  bool working = false, done = false;
  Future<void> restore() async {
    setState(() => working = true);
    try {
      await widget.s.restorePreview(widget.preview);
      if (mounted) setState(() => done = true);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    return dataScaffold(
      done ? '恢复完成' : '核对备份',
      [
        GlassPanel(
          radius: 18,
          child: dataRow(
            p.file,
            CupertinoIcons.archivebox,
            subtitle: dataTime(p.createdAt),
          ),
        ),
        const SizedBox(height: 10),
        localSummary(
          context,
          done
              ? '已创建 ${p.copies.length} 本账本副本'
              : p.checksumVerified
              ? '备份校验通过'
              : '已核对备份结构',
          '${p.copies.length} 本账 · ${p.entryCount} 笔流水',
        ),
        dataGroup(done ? '恢复的账本' : '将创建的副本', [
          for (final book in p.copies)
            dataRow(
              book['name'],
              CupertinoIcons.doc_on_doc,
              subtitle: '独立账本',
              value: '${recordsInBackup(book)} 笔',
            ),
        ]),
        dataGroup('同时恢复', [
          dataRow('分类、预算和关联退款', CupertinoIcons.square_stack),
          dataRow('导入草稿', CupertinoIcons.doc_text, value: '${p.drafts} 份'),
          if (p.templates > 0)
            dataRow(
              '随手记模板',
              CupertinoIcons.square_grid_2x2,
              value: '${p.templates} 个',
            ),
          if (p.plans > 0)
            dataRow(
              '周期记账与发生记录',
              CupertinoIcons.calendar,
              value: '${p.plans} 个计划',
            ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: hint(
            '已有账本保留。恢复后可在账本列表切换至副本核对。${p.plans > 0 ? '\n副本中的周期计划默认暂停，核对后再恢复；已有待确认项保留。' : ''}',
          ),
        ),
      ],
      footer: FilledButton(
        onPressed: working
            ? null
            : done
            ? () => Navigator.pop(context)
            : restore,
        child: Text(
          working
              ? '正在恢复'
              : done
              ? '完成'
              : '恢复为副本',
        ),
      ),
    );
  }
}
