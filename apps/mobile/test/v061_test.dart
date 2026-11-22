import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/store.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/notices.dart';
import 'package:youshu/period_controls.dart';

import 'v050_test.dart' show db, row;
import 'performance_test.dart' show largeStore;
import 'v060_test.dart' show alipay;

import 'package:youshu/payment_import.dart';

class FakeDavStore extends LedgerStore {
  final files = <String, List<int>>{};
  bool failUpload = false, corrupt = false;
  int uploads = 0;
  @override
  Future<Json> davSettings() async => {
    'url': 'https://example.test/dav',
    'name': 'test',
    'password': 'test-only',
  };
  @override
  Future<http.Response> dav(
    String method,
    String path, {
    String? body,
    Map<String, String>? extra,
  }) async {
    if (method == 'PUT') files[path] = utf8.encode(body!);
    if (method == 'DELETE') files.remove(path);
    return http.Response.bytes(files[path] ?? [], 200);
  }

  @override
  Future<void> davFile(
    String method,
    String path,
    File file, {
    int maxBytes = 30 * 1024 * 1024,
  }) async {
    if (method == 'PUT') {
      if (failUpload) throw const FormatException('模拟断网');
      files[path] = await file.readAsBytes();
      uploads++;
    } else {
      await file.writeAsBytes(corrupt ? [1] : files[path]!);
    }
  }

  @override
  Future<List<String>> backups() async =>
      files.keys
          .where((p) => p.endsWith('.manifest.json'))
          .map((p) => p.split('/').last)
          .toList()
        ..sort((a, b) => b.compareTo(a));
}

Future<T> setup<T extends LedgerStore>(T s) async {
  s.database = await db();
  final l = freshLedger('0.6.1 示例');
  s.state['ledgers'] = [l];
  s.state['active'] = l['id'];
  await s.persist();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null),
  );
  test('年/月模板独立，历史未来与手动例外按修订统一生效', () async {
    final s = await setup(LedgerStore());
    addTearDown(() => s.database!.close());
    await s.setBudget('2026-10', '全部', 3100);
    await s.setDailyBudget('2026-10-01', 500);
    await s.setBudget('2026-10', '餐饮', 900);
    await s.setGlobalBudget(6200);
    await s.setGlobalBudget(90000, yearly: true);
    expect(s.yearlyBudget, 90000);
    expect(s.budget('2026-10', '全部'), 6200);
    expect(s.budget('2038-01', '全部'), 6200);
    expect(s.budget('2026-10', '餐饮'), 900);
    expect(s.dailyBudgets('2026-10')['2026-10-01'], 200);
    await s.setDailyBudget('2026-10-01', 300);
    expect(s.budget('2026-10', '全部'), 6300);
    await s.setGlobalBudget(2800);
    expect(s.budget('2026-10', '全部'), 2800);
    expect(s.yearlyBudget, 90000);
    expect(s.dailyBudgets('2028-02').values.reduce((a, b) => a + b), 2800);
    expect(s.dailyBudgets('2028-02').length, 29);
    final copies = validateBackup({'schema': 5, 'ledgers': s.ledgers});
    expect(settingsOf(copies.first)['monthly_budget'], 2800);
  });
  test('关联退款整组删除与恢复，永久删除只保留墓碑且副本不复活', () async {
    final s = await setup(LedgerStore());
    addTearDown(() => s.database!.close());
    final l = s.active;
    (l['entries'] as List).addAll(<Json>[
      row(l, 'purchase', '2026-11-01', 1000),
      row(l, 'refund', '2026-11-02', 200, refund: 'purchase'),
    ]);
    await s.persist();
    final purchase = ledgerIndex(l).byId['purchase']!;
    await s.trashEntry(purchase);
    expect(s.records(l), isEmpty);
    expect(s.trashEntries(l).length, 2);
    expect(
      (await readState(
        s.database!,
      ))!['ledgers'].first['entries'].where((e) => e['deleted'] == true).length,
      2,
    );
    await s.restoreTrashEntry(l, s.trashEntries(l).first);
    expect(s.records(l).length, 2);
    expect(s.total('2026-11', 'expense'), 1000);
    expect(s.total('2026-11', 'income'), 200);
    await s.trashEntry(ledgerIndex(l).byId['purchase']!);
    await s.purgeTrash(book: l, entry: s.trashEntries(l).first);
    expect(s.trashEntries(s.active), isEmpty);
    expect(s.records(s.active), isEmpty);
    final copy = validateBackup({'schema': 5, 'ledgers': s.ledgers}).single;
    expect(ledgerIndex(copy).records, isEmpty);
    expect(
      (copy['entries'] as List)
          .where((e) => e['data']['purged'] == true)
          .length,
      2,
    );
  });
  test('账本删除切换、恢复与30天清理不覆盖别本，旧删除不误清', () async {
    final s = await setup(LedgerStore());
    addTearDown(() => s.database!.close());
    final book = s.active;
    await s.trashBook(book);
    expect(s.ledgers.length, 1);
    expect(s.active['id'], isNot(book['id']));
    expect(s.trashBooks.length, 1);
    await s.restoreBook(s.trashBooks.single);
    expect(s.ledgers.length, 2);
    expect(s.trashBooks, isEmpty);
    await s.trashBook(s.ledgers.firstWhere((l) => l['id'] == book['id']));
    await s.purgeTrash(
      now: DateTime.now().toUtc().add(const Duration(days: 31)),
    );
    expect(s.trashBooks, isEmpty);
    expect(s.ledgers.length, 1);
  });
  test('删除组事务失败回滚，消费和退款都保留', () async {
    final s = await setup(LedgerStore());
    addTearDown(() => s.database!.close());
    final l = s.active;
    (l['entries'] as List).addAll(<Json>[
      row(l, 'purchase', '2026-11-01', 1000),
      row(l, 'refund', '2026-11-02', 200, refund: 'purchase'),
    ]);
    await s.persist();
    await s.database!.execute(
      "CREATE TRIGGER fail_trash BEFORE INSERT ON entries WHEN NEW.id='purchase' BEGIN SELECT RAISE(ABORT,'rollback'); END",
    );
    await expectLater(
      s.trashEntry(ledgerIndex(l).byId['purchase']!),
      throwsA(anything),
    );
    expect(s.records(s.active).length, 2);
    expect(s.trashEntries(s.active), isEmpty);
    expect(
      (await readState(s.database!))!['ledgers'].first['entries']
          .where((e) => e['kind'] == 'entry' && e['deleted'] != true)
          .length,
      2,
    );
  });
  test('自动备份每天一次，失败不清旧备份，各设备与旧版互不误删', () async {
    final s = await setup(FakeDavStore());
    addTearDown(() async {
      s.backupTimer?.cancel();
      await s.database!.close();
    });
    s.state['backupKeep'] = 2;
    s.state['autoBackup'] = true;
    s.files['/yousu/legacy.manifest.json'] = utf8.encode(
      jsonEncode({'schema': 4, 'file': 'legacy.json', 'sha256': 'old'}),
    );
    s.files['/yousu/other.manifest.json'] = utf8.encode(
      jsonEncode({
        'schema': 5,
        'file': 'other.json',
        'sha256': 'other',
        'device': 'other',
        'createdAt': '2020-01-01',
      }),
    );
    await s.resumeMaintenance();
    expect(s.uploads, 1);
    await s.resumeMaintenance();
    expect(s.uploads, 1);
    await s.backup();
    await s.backup();
    expect(
      (await s.backupHistory())
          .where((m) => m['device'] == s.state['backupDevice'])
          .length,
      2,
    );
    expect(s.files.containsKey('/yousu/legacy.manifest.json'), true);
    expect(s.files.containsKey('/yousu/other.manifest.json'), true);
    final count = s.files.length;
    s.failUpload = true;
    await expectLater(s.backup(), throwsA(anything));
    expect(s.files.length, count);
    expect(s.state['backupDirty'], true);
    s.failUpload = false;
    await s.resumeMaintenance();
    expect(s.state['backupDirty'], false);
    final latest = (await s.backupHistory()).firstWhere(
      (m) => m['device'] == s.state['backupDevice'],
    );
    final snapshot = jsonDecode(
      utf8.decode(s.files['/yousu/${latest['file']}']!),
    );
    expect(snapshot['schema'], 5);
    expect(snapshot.containsKey('token'), false);
  });
  test('图表明细重新求交集，编辑分类后移出，新增匹配记录进入', () {
    final l = freshLedger('明细'),
        a = row(l, 'a', '2026-11-01', 1000),
        b = row(l, 'b', '2026-11-02', 2000);
    (l['entries'] as List).addAll(<Json>[a, b]);
    invalidateLedger(l);
    final f = EntryFilter()
      ..detailRule = {
        'kind': 'statistics',
        'group': '二级分类',
        'bucket': 'category:${a['data']['category_id']}',
        'type': 'expense',
        'currency': 'CNY',
      };
    final period = BookPeriod('2026-11-01', '2026-12-01');
    expect(f.apply(l, ledgerIndex(l).records, period).length, 2);
    a['data']['category_id'] = categoryId(l['id'], 'expense', '交通');
    invalidateLedger(l);
    expect(f.apply(l, ledgerIndex(l).records, period).map((e) => e['id']), [
      'b',
    ]);
  });
  test('全局预算失效旧日额度后修改账期，历史与未来仍一致', () async {
    final s = await setup(LedgerStore());
    addTearDown(() => s.database!.close());
    await s.setBudget('2026-10', '全部', 3100);
    await s.setDailyBudget('2026-10-01', 500);
    await s.setGlobalBudget(6200);
    await s.setCycle(10);
    expect(s.budget('2026-10', '全部'), 6200);
    expect(s.dailyBudgets('2026-10').values.reduce((a, b) => a + b), 6200);
    expect(s.dailyBudgets('2030-10').values.reduce((a, b) => a + b), 6200);
  });
  test('两万条全量备份校验及恢复，损坏备份不清理，墓碑可继续导入查重', () async {
    final s = await setup(FakeDavStore());
    addTearDown(() async {
      s.backupTimer?.cancel();
      await s.database!.close();
    });
    s.state = largeStore(20000).state;
    for (final e in s.records(s.active)) {
      e['data']['fx_rate'] = '1';
      e['data']['fx_mode'] = 'manual';
    }
    await s.persist();
    await s.backup();
    final manifests = await s.backupHistory();
    final m = manifests.first;
    expect(m['bytes'], lessThan(30 * 1024 * 1024));
    await s.restore(m['manifest']);
    expect(s.ledgers.length, 2);
    expect(s.records(s.ledgers.last).length, 20000);
    final original = m['manifest'];
    s.corrupt = true;
    await expectLater(s.backup(), throwsFormatException);
    expect(s.files.containsKey('/yousu/$original'), true);
    s.corrupt = false;
    final d = alipay();
    await s.commitImportDraft(d, target: s.active['id'], name: '');
    final imported = s
        .records(s.active)
        .firstWhere((e) => e['data']['source_key'] == d['rows'][0]['key']);
    await s.trashEntry(imported);
    await s.purgeTrash(book: s.active, entry: s.trashEntries(s.active).first);
    final review = reviewImport((alipay(), s.importMatchRows()));
    expect(review['rows'][0]['status'], isNot('ready'));
  });
  test('导入与分类编辑仍保留回收站，恢复写入失败不产生副本', () async {
    final s = await setup(FakeDavStore());
    addTearDown(() async {
      s.backupTimer?.cancel();
      await s.database!.close();
    });
    await s.trashBook(s.active);
    final id = s.trashBooks.single['id'];
    await s.commitImportDraft(alipay(), target: s.active['id'], name: '');
    expect(s.trashBooks.single['id'], id);
    await s.backup();
    final m = (await s.backupHistory()).first;
    final oldCount = s.allLedgers.length;
    await s.database!.execute(
      "CREATE TRIGGER fail_restore BEFORE INSERT ON ledgers BEGIN SELECT RAISE(ABORT,'rollback'); END",
    );
    await expectLater(s.restore(m['manifest']), throwsA(anything));
    expect(s.allLedgers.length, oldCount);
    expect(s.trashBooks.single['id'], id);
  });
  test('备份草稿退款候选跟随新流水ID，原备份不被修改', () {
    final l = freshLedger('恢复');
    final e = row(l, 'source', '2026-11-01', 1000);
    (l['entries'] as List).add(e);
    final out = restoreBundle({
      'schema': 5,
      'ledgers': [l],
      'importDrafts': [
        {
          'id': 'draft',
          'target': l['id'],
          'errors': [],
          'rows': [
            {
              'id': 'pending',
              'refund_of': 'source',
              'candidates': ['source'],
              'status': 'review',
            },
          ],
        },
      ],
    });
    final copy = (out['ledgers'] as List).single,
        draft = (out['drafts'] as List).single;
    expect(draft['target'], copy['id']);
    expect(
      draft['rows'][0]['refund_of'],
      ledgerIndex(copy).records.single['id'],
    );
    expect(draft['rows'][0]['id'], 'pending');
    expect(e['id'], 'source');
  });
  test('回收站账本在前时，普通保存失败只回滚对应可见账本', () async {
    final s = await setup(LedgerStore());
    addTearDown(() => s.database!.close());
    final trashId = s.active['id'];
    await s.trashBook(s.active);
    final activeId = s.active['id'];
    await s.database!.execute(
      "CREATE TRIGGER fail_save BEFORE INSERT ON entries WHEN NEW.id='new-failure' BEGIN SELECT RAISE(ABORT,'rollback'); END",
    );
    await expectLater(
      s.saveEntry(
        row(s.active, 'x', '2026-11-01', 100)['data'],
        id: 'new-failure',
      ),
      throwsA(anything),
    );
    expect(s.allLedgers.length, 2);
    expect(s.trashBooks.single['id'], trashId);
    expect(s.active['id'], activeId);
    expect(s.records(s.active), isEmpty);
  });
  testWidgets('顶部通知三条堆叠、去重与自动关闭', (t) async {
    notices.value = [];
    await t.pumpWidget(
      MaterialApp(
        builder: (c, child) => NoticeHost(child: child!),
        home: const Scaffold(),
      ),
    );
    for (final text in ['一', '二', '三', '四', '一']) {
      notifyApp(text);
    }
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(notices.value.length, 4);
    expect(find.text('四'), findsNothing);
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 250));
    expect(find.text('四'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    notices.value = [];
  });
  testWidgets('结余热度正负色系一致，大额深于小额', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            expect(balanceHeat(c, 100, 100), isNot(balanceHeat(c, -100, 100)));
            expect(balanceHeat(c, 1, 100), isNot(balanceHeat(c, 100, 100)));
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
