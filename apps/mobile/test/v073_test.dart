import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/store.dart';

import 'v050_test.dart' show db, row;
import 'v060_test.dart' show alipay;
import 'v061_test.dart' show FakeDavStore, setup;

class PausedDavStore extends FakeDavStore {
  Completer<void>? upload;
  final started = Completer<void>();

  @override
  Future<void> davFile(
    String method,
    String path,
    File file, {
    int maxBytes = 30 * 1024 * 1024,
  }) async {
    if (method == 'PUT' && upload != null) {
      started.complete();
      await upload!.future;
    }
    await super.davFile(method, path, file, maxBytes: maxBytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null);
  });

  test('凭据不可用时读取并转换旧共享账本，旧队列封存、后续写入本机', () async {
    final book = freshLedger('旧共享账本')
      ..addAll({
        'shared': true,
        'role': 'viewer',
        'lastSync': '2026-10-03T02:00:00Z',
        'pending': [
          {'operation_id': 'old-operation', 'entry_id': 'old-entry'},
        ],
      });
    (book['entries'] as List).add(row(book, 'old-entry', '2026-10-02', 2400));
    final database = await db();
    addTearDown(database.close);
    await database.transaction(
      (tx) => writeState(tx, {
        'schema': 5,
        'ledgers': [book],
        'active': book['id'],
        'autoBackup': true,
      }),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const secure = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    var calls = 0;
    messenger.setMockMethodCallHandler(secure, (_) async {
      calls++;
      throw PlatformException(code: 'unavailable');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(secure, null));
    final s = LedgerStore()..database = database;
    addTearDown(s.dispose);
    await s.initialize();
    expect(calls, 0);
    expect(s.active['id'], book['id']);
    expect(s.active['role'], 'owner');
    expect(s.active['shared'], isFalse);
    expect(
      s.active['retired_sharing']['operations'].single['operation_id'],
      'old-operation',
    );
    expect(await database.query('outbox'), isEmpty);
    await s.resumeMaintenance();
    expect(calls, 1);
    await s.saveEntry(row(s.active, 'new', '2026-10-02', 1200)['data']);
    expect(s.total('2026-10', 'expense'), 3600);

    final after = LedgerStore()..database = database;
    addTearDown(after.dispose);
    await after.initialize();
    expect(after.records(after.active).length, 2);
    expect(after.state['dataRevision'], s.state['dataRevision']);
    expect(after.active['retired_sharing']['role'], 'viewer');
  });

  test('CSV 按给定范围导出原币、退款及带换行的公式前缀文本', () async {
    final s = LedgerStore();
    addTearDown(s.dispose);
    final book = freshLedger('日常,家用');
    final refund = row(book, 'refund', '2026-10-04', 4500, refund: 'expense');
    refund['data'].addAll({
      'original_currency': 'USD',
      'original_amount_minor': 600,
      'note': '=金额,"备注"\n第二行',
      'account': '未指定',
    });
    final csv = utf8.decode(await s.exportCsv(book, [refund]));
    expect(csv, startsWith('账本,日期,'));
    expect(csv, contains('"日常,家用","2026-10-04","12:30","退款"'));
    expect(csv, contains('"",6.00,"USD",45.00,"CNY"'));
    expect(csv, contains('"\'=金额,""备注""\n第二行"'));
  });

  test('完整文件读取提交快照、拒绝损坏，恢复关系和草稿并保留原账本', () async {
    final s = await setup(LedgerStore());
    addTearDown(s.dispose);
    addTearDown(s.database!.close);
    final l = s.active;
    (l['entries'] as List).addAll(<Json>[
      row(l, 'base', '2026-11-04', 10000),
      row(l, 'refund', '2026-11-05', 4500, refund: 'base'),
      row(l, 'trash', '2026-11-07', 1000),
    ]);
    await s.persist();
    await s.trashEntry(ledgerIndex(l).byId['trash']!);
    await s.saveImportDraft({
      'id': 'draft',
      'target': l['id'],
      'file': '对账.csv',
      'rows': <Json>[],
      'errors': <String>[],
    });
    s.token = 'test-credential-only';
    final bytes = await s.exportBackupFile();
    expect(utf8.decode(bytes), isNot(contains(s.token)));
    final damaged = utf8.encode(
      utf8.decode(bytes).replaceAll('对账.csv', '替换.csv'),
    );
    await expectLater(
      s.inspectBackupFile(damaged, '坏.json'),
      throwsFormatException,
    );
    final preview = await s.inspectBackupFile(bytes, '备份.json');
    expect(preview.checksumVerified, isTrue);
    expect(preview.entryCount, 2);
    expect(preview.drafts, 1);
    expect(s.ledgers.length, 1);
    await s.restorePreview(preview);
    expect(s.ledgers.length, 2);
    expect(s.active['id'], l['id']);
    final copy = s.ledgers.last;
    final refund = s.records(copy).firstWhere((e) => isRefund(e['data']));
    expect(
      ledgerIndex(copy).byId[refund['data']['refund_of']]!['data']['amount'],
      10000,
    );
    expect(s.trashEntries(copy).length, 1);
    expect((s.state['importDrafts'] as List).last['target'], copy['id']);
    await expectLater(s.restorePreview(preview), throwsFormatException);
    final raw = utf8.encode(
      jsonEncode({
        'schema': 5,
        'ledgers': [l],
      }),
    );
    expect(
      (await s.inspectBackupFile(raw, '历史.json')).checksumVerified,
      isFalse,
    );
  });

  test('导入批次只撤销原样记录，旧预览被拒绝且回收站可恢复', () async {
    final s = await setup(LedgerStore());
    addTearDown(s.dispose);
    addTearDown(s.database!.close);
    await s.commitImportDraft(
      alipay('demo-a'),
      target: s.active['id'],
      name: '',
    );
    await s.commitImportDraft(
      alipay('demo-b'),
      target: s.active['id'],
      name: '',
    );
    final batch = s.importBatches.first;
    final preview = await s.previewImportUndo(batch);
    expect(preview.count, 1);
    final older = s
        .records(s.active)
        .firstWhere((r) => r['id'] != batch['ids'].single);
    await s.saveEntry({
      ...older['data'] as Json,
      'note': '改过',
    }, existing: older);
    expect((await s.previewImportUndo(s.importBatches.last)).count, 0);
    await expectLater(s.undoImportBatch(preview), throwsFormatException);
    await s.undoImportBatch(await s.previewImportUndo(batch));
    expect(s.records(s.active).length, 1);
    expect(s.records(s.active).single['data']['note'], '改过');
    final removed = s.trashEntries(s.active).single;
    await s.restoreTrashEntry(s.active, removed);
    expect(s.records(s.active).length, 2);
  });

  test('备份上传挂起及失败不挡记账，重试成功保留可恢复的新版本', () async {
    final s = await setup(PausedDavStore());
    addTearDown(s.dispose);
    addTearDown(s.database!.close);
    await s.backup();
    final last = s.state['lastBackup'];
    s.upload = Completer<void>();
    final backup = s.backup();
    final failed = expectLater(backup, throwsFormatException);
    await s.started.future;
    expect(s.busy, isFalse);
    await s.saveEntry(row(s.active, 'local-save', '2026-10-02', 1600)['data']);
    s.failUpload = true;
    s.upload!.complete();
    await failed;
    expect(s.state['lastBackup'], last);
    expect(s.state['backupDirty'], isTrue);
    expect(s.records(s.active).length, 1);
    s.upload = null;
    s.failUpload = false;
    await s.backup();
    final version = (await s.backupHistory()).first;
    expect((await s.inspectWebDavBackup(version['manifest'])).entryCount, 1);
    expect(s.state['backupDirty'], isFalse);
    expect(s.state['backupError'], '');
  });
}
