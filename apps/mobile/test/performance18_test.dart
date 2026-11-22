import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/icon_catalog.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/main.dart';
import 'package:youshu/store.dart';
import 'package:youshu/transactions.dart';

import 'icon_dictionary_test.dart' show imageData;
import 'performance_test.dart' show largeStore;

class LoadingStore extends LedgerStore {
  final gate = Completer<void>();
  final bool failFirst;
  int attempts = 0;
  LoadingStore({this.failFirst = false});
  @override
  Future<void> initialize({void Function(Json)? onPreferencesLoaded}) async {
    attempts++;
    onPreferencesLoaded?.call({'theme': 'dark'});
    if (failFirst && attempts == 1) throw const FormatException('模拟存储故障');
    await gate.future;
    final book = freshLedger('首屏验收');
    state.addAll({
      'ledgers': [book],
      'active': book['id'],
      'notificationPermissionAsked': true,
      'theme': 'dark',
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null),
  );

  Future<LedgerStore> loadedStore([int count = 20]) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => createV2(db),
      ),
    );
    final fixture = largeStore(count);
    fixture.state['importDrafts'] = [
      {
        'id': 'draft',
        'rows': [1],
      },
    ];
    await StateWriter().write(db, encodePersistence((fixture.state, false)));
    fixture.dispose();
    final store = LedgerStore()..database = db;
    await store.initialize();
    addTearDown(() async {
      await store.flushViewPreferences();
      store.dispose();
      await db.close();
    });
    return store;
  }

  test('空备注隐藏占位，保留真实账户、来源、成员与标签', () {
    final book = freshLedger('备注');
    final tag = entity('tag', 'tag', {'name': '日常'});
    (book['entries'] as List).add(tag);
    final row = entity('row', 'entry', {
      'note': '',
      'account': '未指定',
      'tag_ids': [],
    });
    expect(transactionSubtitle(book, row), '');
    row['data']['note'] = null;
    expect(transactionSubtitle(book, row), '');
    row['data']['account'] = '微信';
    expect(transactionSubtitle(book, row), '微信');
    row['data'].addAll({
      'note': ' 午餐 ',
      'tag_ids': ['tag'],
      'merchant': '食堂',
    });
    expect(
      transactionSubtitle(book, row, sourceLedger: '家庭', shared: true),
      '家庭 · 午餐 · 微信 · 我 · 食堂 · #日常',
    );
    row['data']['tag_ids'] = ['tag', 'tag'];
    expect(transactionSubtitle(book, row), '午餐 · 微信 · 食堂 · #日常');
  });

  test('正常冷加载不增修订和SQL写入，重启后首次编辑只写一笔', () async {
    final s = await loadedStore(6000), db = s.database!;
    final before = (await db.rawQuery('SELECT total_changes() AS n'))
        .first['n'];
    final revision = s.state['dataRevision'];
    await s.initialize();
    expect(
      (await db.rawQuery('SELECT total_changes() AS n')).first['n'],
      before,
    );
    expect(s.state['dataRevision'], revision);
    await db.execute('CREATE TABLE audit (id TEXT)');
    await db.execute(
      'CREATE TRIGGER audit_entry AFTER INSERT ON entries BEGIN INSERT INTO audit VALUES (new.id); END',
    );
    final row = s.records(s.active).first;
    await s.saveEntry({...row['data'] as Json, 'note': '修改后'}, existing: row);
    expect((await db.query('audit')).length, 1);
    expect(
      (await readState(
        db,
      ))!['ledgers'][0]['entries'].where((r) => r['kind'] == 'entry').length,
      6000,
    );
  });

  test('视图防抖只合并页面字段，不通知或提交未保存草稿', () async {
    final s = await loadedStore();
    var notices = 0;
    s.addListener(() => notices++);
    final revision = s.state['dataRevision'];
    s.state['transactionViews'] = {
      'demo': {'offset': 1},
    };
    s.queueViewPreferences();
    s.state['transactionViews']['demo']['offset'] = 42;
    s.state['budgetViews'] = {
      'demo': {'mode': '年'},
    };
    s.state['statisticsViews'] = {
      'demo': {'chart': '条形图'},
    };
    s.queueViewPreferences();
    s.state['importDrafts'] = [
      {
        'id': 'uncommitted',
        'rows': [2],
      },
    ];
    await s.flushViewPreferences();
    final restored = (await readState(s.database!))!;
    expect(restored['transactionViews']['demo']['offset'], 42);
    expect(restored['budgetViews']['demo']['mode'], '年');
    expect(restored['statisticsViews']['demo']['chart'], '条形图');
    expect(restored['importDrafts'][0]['id'], 'draft');
    expect(restored['dataRevision'], revision);
    expect(notices, 0);
  });

  test('页面偏好失败可重试，财务保存携带最新视图', () async {
    final s = await loadedStore();
    s.state['lastTab'] = 3;
    s.queueViewPreferences();
    await s.database!.execute(
      "CREATE TRIGGER fail_pref BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT,'failed'); END",
    );
    await expectLater(
      s.flushViewPreferences(),
      throwsA(isA<DatabaseException>()),
    );
    await s.database!.execute('DROP TRIGGER fail_pref');
    final row = s.records(s.active).first;
    await s.saveEntry({...row['data'] as Json, 'note': '恢复保存'}, existing: row);
    expect((await readState(s.database!))!['lastTab'], 3);
  });

  test('Widget合并连续保存，偏好保存跳过原生刷新', () async {
    final s = await loadedStore();
    final payloads = <Json>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async {
          if (call.method == 'updateWidget') {
            payloads.add(Map<String, dynamic>.from(call.arguments));
          }
          return null;
        });
    s.queueWidgetRefresh();
    await s.flushWidgetRefresh();
    expect(payloads.length, 1);
    s.state['theme'] = 'dark';
    await s.persist(preferencesOnly: true);
    await s.flushWidgetRefresh();
    expect(payloads.length, 1);
    for (var i = 0; i < 2; i++) {
      await s.saveEntry({
        'type': 'expense',
        'amount': 100,
        'date': today(),
        'category': '餐饮',
        'account': '现金',
        'note': '',
      });
    }
    await s.flushWidgetRefresh();
    expect(payloads.length, 2);
    expect(
      payloads.last['expense'],
      '${s.currency} ${s.display(s.total(today(), 'expense'))}',
    );
  });

  test('图标延迟解码与LRU淘汰，来源删除后回退', () {
    IconCatalog.custom.clear();
    final book = freshLedger(
      '图片',
    )..['custom_icons'] = {for (var i = 0; i < 70; i++) 'custom:$i': imageData};
    IconCatalog.sync([book]);
    expect(IconCatalog.custom.length, 0);
    final first = IconCatalog.custom['custom:0'];
    expect(first, base64Decode(imageData));
    for (var i = 1; i < 70; i++) {
      expect(IconCatalog.custom['custom:$i'], isNotNull);
    }
    expect(IconCatalog.custom.length, 64);
    expect(identical(first, IconCatalog.custom['custom:0']), isFalse);
    book['custom_icons'] = <String, dynamic>{};
    IconCatalog.sync([book]);
    expect(IconCatalog.custom['custom:0'], isNull);
    IconCatalog.custom.clear();
  });

  test('Widget只读取事务确认的快照', () async {
    final s = await loadedStore();
    final payloads = <Json>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async {
          if (call.method == 'updateWidget') {
            payloads.add(Map<String, dynamic>.from(call.arguments));
          }
          return null;
        });
    final expected = '${s.currency} ${s.display(s.total(today(), 'expense'))}';
    final row = s.records(s.active).first;
    final original = row['data'];
    row['data'] = {
      ...original as Json,
      'date': today(),
      'amount': 999900,
      'base_amount_minor': 999900,
    };
    invalidateLedger(s.active);
    s.queueWidgetRefresh();
    await s.flushWidgetRefresh();
    expect(payloads.single['expense'], expected);
    row['data'] = original;
    invalidateLedger(s.active);
  });

  testWidgets('账本等待时首帧可见，读取外观并在完成后进入首页', (t) async {
    final s = LoadingStore();
    await t.pumpWidget(YoushuBootstrap(store: s));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(Home), findsNothing);
    await t.pump(const Duration(milliseconds: 310));
    expect(find.text('正在打开账本'), findsOneWidget);
    expect(
      Theme.of(t.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    s.gate.complete();
    await t.pumpAndSettle();
    expect(find.byType(Home), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });

  testWidgets('启动失败可重试', (t) async {
    final s = LoadingStore(failFirst: true);
    await t.pumpWidget(YoushuBootstrap(store: s));
    await t.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    await t.tap(find.text('重试'));
    s.gate.complete();
    await t.pumpAndSettle();
    expect(s.attempts, 2);
    expect(find.byType(Home), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });

  testWidgets('流水缓存随数据、ID范围及捕获变量筛选更新', (t) async {
    final s = largeStore(20);
    var include = true;
    bool predicate(Json row) => include;
    Widget flow(Set<String>? ids) => MaterialApp(
      home: Scaffold(
        body: Transactions(
          s,
          periodKey: today(),
          onlyIds: ids,
          includeRecord: predicate,
          tile: (e) => Text(e['id']),
          add: (_) {},
        ),
      ),
    );
    await t.pumpWidget(flow(null));
    final state = t.state<TransactionsState>(find.byType(Transactions));
    expect(state.queryRows(s.period(today())).length, 20);
    include = false;
    expect(state.queryRows(s.period(today())), isEmpty);
    include = true;
    final id = s.records(s.active).first['id'] as String;
    await t.pumpWidget(flow({id}));
    expect(state.queryRows(s.period(today())).single['id'], id);
    s.active['entries'] = (s.active['entries'] as List)
        .where((r) => r['id'] != id)
        .toList();
    invalidateLedger(s.active);
    expect(state.queryRows(s.period(today())), isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
}
