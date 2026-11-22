import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/store.dart';
import 'package:youshu/main.dart';
import 'package:youshu/transactions.dart';
import 'package:youshu/statistics_page.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/category_templates.dart';

import 'v062_test.dart' show fixture;
import 'v050_test.dart' show row;
import 'performance_test.dart' show largeStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null),
  );
  Future<LedgerStore> store() async {
    final s = await fixture();
    addTearDown(() async {
      s.backupTimer?.cancel();
      await s.database!.close();
    });
    return s;
  }

  test('退款45计收入，消费100预算回补，历史快照不改写', () async {
    final s = await store(), book = s.active;
    final original = s.records(book).single;
    original['data'].addAll({
      'amount': 10000,
      'base_amount_minor': 10000,
      'original_amount_minor': 10000,
    });
    invalidateLedger(book);
    await s.refund(original, 4500);
    final records = s.records(book),
        refund = records.firstWhere((r) => isRefund(r['data']));
    expect(refund['data']['type'], 'expense');
    expect(s.total(today(), 'expense'), 10000);
    expect(s.total(today(), 'income'), 4500);
    expect(BalanceRule(book).total(records), -5500);
    expect(s.budgetSpent(today()), 5500);
    final income = (EntryFilter()..types = {'income'}).apply(
      book,
      records,
      s.period(today()),
    );
    expect(income.map((r) => r['id']), [refund['id']]);
    final buckets = statisticBuckets(book, records, 'income', '一级分类', 'CNY');
    expect(buckets.single.amount, 4500);
    final detail = EntryFilter()
      ..detailRule = {
        'kind': 'statistics',
        'bucket': buckets.single.id,
        'group': '一级分类',
        'type': 'income',
        'currency': 'CNY',
      };
    expect(
      detail.apply(book, records, s.period(today())).single['id'],
      refund['id'],
    );
  });

  test('分类迁移覆盖关联退款、回收站、预算、筛选、草稿和备份', () async {
    final s = await store(), book = s.active;
    final original = s.records(book).single;
    final source = original['data']['category_id'] as String;
    final target =
        dictionary(
              book,
              'category',
              type: 'expense',
            ).firstWhere((c) => c['data']['parent_id'] == '')['id']
            as String;
    await s.refund(original, 800);
    final trashed = row(book, 'old', today(), 100)..['deleted'] = true;
    trashed['data'].addAll({
      'category_id': source,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    });
    (book['entries'] as List).add(trashed);
    invalidateLedger(book);
    await s.setBudget(today(), source, 10000);
    await s.setBudget(today(), target, 20000);
    s.state['transactionFilters'] = {
      book['id']: (EntryFilter()..categories = {source}).toJson(),
    };
    s.state['importDrafts'] = [
      {
        'id': 'd',
        'target': book['id'],
        'rows': [
          {'category_id': source},
        ],
      },
    ];
    await s.deleteDictionary(source, target);
    expect(dictionary(book, 'category').any((r) => r['id'] == source), isFalse);
    expect(
      (book['entries'] as List)
          .where((r) => r['kind'] == 'entry')
          .every((r) => r['data']['category_id'] == target),
      isTrue,
    );
    expect(s.budget(today(), target), 30000);
    expect(s.total(today(), 'expense'), 3800);
    expect(s.total(today(), 'income'), 800);
    expect(s.budgetSpent(today()), 3000);
    expect(s.state['transactionFilters'][book['id']]['categories'], [target]);
    final saved = (await readState(s.database!))!;
    expect(saved['importDrafts'][0]['rows'][0]['category_id'], target);
    final copy = validateBackup({
      'schema': 5,
      'ledgers': [book],
    }).single;
    expect(ledgerIndex(copy).records.length, 2);
    final deletedName = (book['entries'] as List).firstWhere(
      (r) => r['id'] == source,
    )['data']['name'];
    final addition = recommendedCategories(book)
        .firstWhere((r) => r['data']['name'] == deletedName);
    expect(addition['id'], isNot(source));
    await s.saveDictionaryBatch([addition]);
    expect(
      (book['entries'] as List).firstWhere((r) => r['id'] == source)['deleted'],
      isTrue,
    );
  });

  test('父分类保留子项，同名合并，排除冲突明确选择', () async {
    final s = await store(), book = s.active;
    Json category(String id, String name, String parent) =>
        entity(id, 'category', {
          'name': name,
          'type': 'expense',
          'parent_id': parent,
          'order': 0,
          'archived': false,
        });
    (book['entries'] as List).addAll(<Json>[
      category('a', '来源', ''),
      category('b', '替代', ''),
      category('a1', '同名', 'a'),
      category('a2', '保留', 'a'),
      category('b1', '同名', 'b'),
    ]);
    invalidateLedger(book);
    s.records(book).single['data']['category_id'] = 'a1';
    await s.setBudgetExclusions({'a'}, {});
    await s.setBalanceExclusions({'a'}, {});
    await expectLater(s.deleteDictionary('a', 'b'), throwsFormatException);
    await s.deleteDictionary(
      'a',
      'b',
      budgetPolicy: {'b': true},
      balancePolicy: {'b': true},
    );
    expect(s.records(s.active).single['data']['category_id'], 'b1');
    expect(ledgerIndex(s.active).byId['a2']!['data']['parent_id'], 'b');
    expect(s.budgetSpent(today()), 0);
    expect(BalanceRule(s.active).total(s.records(s.active)), 0);
    expect(ledgerIndex(s.active).byId['a1'], isNull);
  });

  test('共享迁移只入一个队列项，失败重试保持幂等编号', () async {
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousHttp);
    final s = await store(), book = s.active;
    book['shared'] = true;
    final remote = jsonDecode(jsonEncode(book)) as Json;
    final source = s.records(book).single['data']['category_id'];
    final target = dictionary(
      book,
      'category',
      type: 'expense',
    ).firstWhere((c) => c['data']['parent_id'] == '')['id'];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    s.endpoint = 'http://127.0.0.1:${server.port}';
    s.state['dictionaryDeletionServer'] = s.endpoint;
    var attempts = 0;
    final operationIds = <String>[];
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      dynamic result;
      if (request.uri.path.endsWith('/capabilities')) {
        result = {'schema': 5, 'dictionary_deletions': true};
      } else if (request.uri.path.endsWith('/dictionary-deletions')) {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        operationIds.add(body['operation_id']);
        attempts++;
        if (attempts == 1) {
          request.response.statusCode = 503;
          result = {'detail': 'retry'};
        } else {
          final plan = planDictionaryDeletion(remote, source, target);
          expect(body['expected'], plan.expected);
          final patches = {for (final row in plan.changes) row['id']: row};
          remote['entries'] = [
            for (final row in remote['entries']) patches[row['id']] ?? row,
          ];
          result = {'ok': true};
        }
      } else {
        result = {'entries': remote['entries']};
      }
      request.response.write(jsonEncode(result));
      await request.response.close();
    });
    await s.deleteDictionary(source, target);
    expect((book['pending'] as List).length, 1);
    await expectLater(s.sync(), throwsA(isA<ApiError>()));
    expect((book['pending'] as List).length, 1);
    await s.sync();
    expect(book['pending'], isEmpty);
    expect(operationIds.toSet().length, 1);
  });

  test('两万条分类迁移与失败回滚，标签迁移去重', () async {
    final s = await store();
    final large = largeStore(20000).active;
    s.state['ledgers'] = [large];
    s.state['active'] = large['id'];
    final source = s.records(large).first['data']['category_id'];
    final target = dictionary(large, 'category', type: 'expense').firstWhere(
      (r) => r['id'] != source && r['data']['parent_id'] == '',
    )['id'];
    await s.persist();
    final originalTotal = s.total('2026-07', 'expense');
    await s.database!.execute(
      "CREATE TRIGGER fail_dictionary BEFORE INSERT ON entries BEGIN SELECT RAISE(ABORT,'rollback'); END",
    );
    await expectLater(s.deleteDictionary(source, target), throwsA(anything));
    expect(ledgerIndex(s.active).byId[source], isNotNull);
    await s.database!.execute('DROP TRIGGER fail_dictionary');
    await s.deleteDictionary(source, target);
    expect(s.records(s.active).length, 20000);
    expect(s.total('2026-07', 'expense'), originalTotal);
    expect(
      s.records(s.active).any((r) => r['data']['category_id'] == source),
      isFalse,
    );
    for (final id in ['tag-a', 'tag-b']) {
      (s.active['entries'] as List).add(
        entity(id, 'tag', {'name': id, 'archived': false}),
      );
    }
    s.records(s.active).first['data']['tag_ids'] = ['tag-a', 'tag-b'];
    invalidateLedger(s.active);
    await s.deleteDictionary('tag-a', 'tag-b');
    expect(s.records(s.active).first['data']['tag_ids'], ['tag-b']);
  });

  for (final scenario in [(3000, 11), (3800, 12), (0, 0)]) {
    testWidgets('年日预算完整周期 ${scenario.$1}', (t) async {
      final s = (await t.runAsync(store))!;
      await t.runAsync(() => s.setGlobalBudget(scenario.$1));
      await t.pumpWidget(YoushuApp(s));
      await t.pumpAndSettle();
      await t.tap(find.text('分析').last);
      await t.pumpAndSettle();
      await t.tap(find.text('预算').last);
      await t.pumpAndSettle();
      await t.tap(find.text('年').first);
      await t.pumpAndSettle();
      expect(find.text('未超预算月数 ${scenario.$2}/12'), findsOneWidget);
      await t.tap(find.text('日').first);
      await t.pumpAndSettle();
      final count = periodDays(s.period(today())).length;
      expect(
        find.text('未超预算天数 ${scenario.$1 == 0 ? 0 : count - 1}/$count'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('菜单外首次拖动滚动正文，精简头固定且外部点击生效', (t) async {
    final s = (await t.runAsync(store))!;
    final book = s.active;
    (book['entries'] as List).addAll(<Json>[
      for (var i = 0; i < 120; i++) row(book, 'extra-$i', today(), 100),
    ]);
    invalidateLedger(book);
    await t.pumpWidget(YoushuApp(s));
    await t.pumpAndSettle();
    final state = t.state<TransactionsState>(find.byType(Transactions));
    await t.tap(find.byTooltip('更多功能'));
    await t.pumpAndSettle();
    expect(state.moreController.isShowing, isTrue);
    await t.dragFrom(const Offset(90, 450), const Offset(0, -260));
    await t.pumpAndSettle();
    expect(state.moreController.isShowing, isFalse);
    expect(state.scroll.offset, greaterThan(100));
    expect(
      find.byKey(const ValueKey('flow-month')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('日常账本').hitTestable(), findsNothing);
    await t.tap(find.byTooltip('更多功能'));
    await t.pumpAndSettle();
    await t.tap(find.text('分析').last);
    await t.pumpAndSettle();
    await t.tap(find.text('预算').last);
    await t.pumpAndSettle();
    expect(state.moreController.isShowing, isFalse);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
