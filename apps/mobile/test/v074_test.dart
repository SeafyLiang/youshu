import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/store.dart';
import 'package:youshu/local_database.dart';
import 'package:youshu/templates_page.dart';
import 'package:youshu/recurring_page.dart';
import 'package:youshu/record_page.dart';

import 'v061_test.dart' show setup;

Json fields(LedgerStore s, {int? amount = 900000, String currency = 'CNY'}) => {
  'type': 'expense',
  'category_id': s.categoryKey('房租'),
  'account': '银行卡',
  'original_currency': currency,
  'original_amount_minor': amount,
  'tag_ids': <String>[],
  'note': '',
};
Json plan(
  LedgerStore s, {
  String id = 'rent',
  String? anchor,
  int start = 1,
  int? total = 4,
  int interval = 3,
  String unit = 'month',
  bool deposit = false,
}) => {
  'id': id,
  'name': '房租',
  'fields': fields(s),
  'anchor': anchor ?? today(),
  'start': start,
  'total': total,
  'interval': interval,
  'unit': unit,
  'early': 0,
  'status': 'active',
  if (deposit)
    'extra': {
      'name': '押金',
      'amount': 300000,
      'period': 1,
      'category_id': s.categoryKey('其他'),
      'paid': false,
    },
};
Future<LedgerStore> store() async {
  final s = await setup(LedgerStore());
  addTearDown(s.dispose);
  addTearDown(s.database!.close);
  return s;
}

Future<Json> price(LedgerStore s, Json o, {int? amount}) => s.schedulePricing({
  ...o['fields'] as Json,
  'original_amount_minor': ?amount,
}, today());
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  FlutterSecureStorage.setMockInitialValues({});
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (_) async => null),
  );
  test('日历周期保留月末和闰年锚点', () {
    final anchor = DateTime(2028, 1, 31);
    expect(dateKey(recurringDate(anchor, 1, 1, 'month')), '2028-02-29');
    expect(dateKey(recurringDate(anchor, 2, 1, 'month')), '2028-03-31');
    expect(
      dateKey(recurringDate(DateTime(2024, 2, 29), 1, 1, 'year')),
      '2025-02-28',
    );
    expect(
      dateKey(recurringDate(DateTime(2024, 2, 29), 4, 1, 'year')),
      '2028-02-29',
    );
    expect(
      dateKey(recurringDate(DateTime(2026, 12, 28), 1, 1, 'week')),
      '2027-01-04',
    );
  });
  test('中途接入5/12余8期、押金不挪期、跳过末期结束', () async {
    final s = await store();
    final p = plan(
      s,
      anchor: '2026-12-15',
      start: 5,
      total: 12,
      interval: 1,
      deposit: true,
    );
    expect(recurringOccurrence(p, 4), isNull);
    expect(recurringOccurrence(p, 5)!['extra'], isNull);
    expect(recurringOccurrence(p, 12)!['due'], '2027-07-15');
    expect(recurringOccurrence(p, 13), isNull);
    await s.saveRecurringPlan(p);
    await s.maintainRecurring(day: '2028-01-01');
    expect(s.recurringPending.length, 8);
    expect(s.records(s.active), isEmpty);
    await s.maintainRecurring(day: '2028-01-01');
    expect(s.recurringPending.length, 8);
    for (final o in [...s.recurringPending]) {
      await s.skipRecurring(o['id']);
    }
    expect(s.recurringPlans.single['status'], 'ended');
  });
  test('押一付三原子双笔、重复确认、SQL重读与二次副本关联', () async {
    final s = await store();
    await s.saveRecurringPlan(plan(s, deposit: true));
    final o = s.recurringPending.single;
    final main = await price(s, o),
        extra = await s.schedulePricing({
          ...o['fields'] as Json,
          'original_amount_minor': 300000,
          'category_id': o['extra']['category_id'],
        }, today());
    await s.confirmRecurring(o['id'], main, extra: extra);
    await s.confirmRecurring(o['id'], main, extra: extra);
    expect(s.records(s.active).length, 2);
    expect(
      s
          .records(s.active)
          .fold<int>(0, (n, e) => n + (e['data']['amount'] as int)),
      1200000,
    );
    final state = (await readState(s.database!))!;
    final book = (state['ledgers'] as List).single as Json;
    expect(
      localItems(book, 'recurring_occurrences').single['entry_ids'].length,
      2,
    );
    final restored = validateBackup({
      'schema': 6,
      'ledgers': [book],
    }).single;
    expect(restored['id'], isNot(book['id']));
    expect(localItems(restored, 'recurring_plans').single['status'], 'paused');
    final refs = localItems(
      restored,
      'recurring_occurrences',
    ).single['entry_ids'];
    expect(
      refs.toSet().intersection((o['entry_ids'] as List).toSet()),
      isEmpty,
    );
    expect(
      refs.every((id) => ledgerIndex(restored).byId.containsKey(id)),
      isTrue,
    );
    validateLocalSchedules(
      validateBackup({
        'schema': 6,
        'ledgers': [restored],
      }).single,
    );
    final second = recurringOccurrence(s.recurringPlans.single, 2)!;
    await s.maintainRecurring(day: second['due']);
    expect(s.recurringPending.single['extra'], isNull);
  });
  test('第二笔SQL失败回滚整期，重试同发生键', () async {
    final s = await store();
    await s.saveRecurringPlan(plan(s, deposit: true));
    final id = s.recurringPending.single['id'];
    final p = await price(s, s.recurringPending.single);
    final x = await s.schedulePricing({
      ...s.recurringPending.single['fields'] as Json,
      'original_amount_minor': 300000,
    }, today());
    await s.database!.execute(
      "CREATE TRIGGER reject_extra BEFORE INSERT ON entries WHEN NEW.id LIKE '%:extra' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(s.confirmRecurring(id, p, extra: x), throwsA(anything));
    expect(s.records(s.active), isEmpty);
    expect(s.recurringPending.length, 1);
    final state = (await readState(s.database!))!;
    expect(
      (state['ledgers'][0]['entries'] as List).where(
        (e) => e['kind'] == 'entry',
      ),
      isEmpty,
    );
    await s.database!.execute('DROP TRIGGER reject_extra');
    await s.confirmRecurring(id, p, extra: x);
    expect(s.records(s.active).length, 2);
  });
  test('并发确认仅一次提交，末期自动结束', () async {
    final s = await store();
    await s.saveRecurringPlan(plan(s, total: 1, deposit: true));
    final o = s.recurringPending.single,
        p = await price(s, s.recurringPending.single);
    final x = await s.schedulePricing({
      ...o['fields'] as Json,
      'original_amount_minor': 300000,
    }, today());
    final errors = <Object>[];
    await Future.wait([
      for (var i = 0; i < 2; i++)
        s.confirmRecurring(o['id'], p, extra: x).catchError((Object e) {
          errors.add(e);
        }),
    ]);
    expect(errors.length, 1);
    expect(s.records(s.active).length, 2);
    expect(s.recurringPlans.single['status'], 'ended');
  });
  test('本期与未来金额分离，待确认显式更新，已确认快照不变', () async {
    final s = await store();
    await s.saveRecurringPlan(
      plan(s, anchor: '2026-01-01', interval: 1, total: 12),
    );
    final first = s.recurringPending.first;
    await s.confirmRecurring(
      first['id'],
      await price(s, first, amount: 620000),
    );
    expect(s.recurringPlans.single['fields']['original_amount_minor'], 900000);
    final second = s.recurringPending.first;
    await s.confirmRecurring(
      second['id'],
      await price(s, second, amount: 610000),
      updateFuture: true,
      updatePending: true,
    );
    expect(s.recurringPlans.single['fields']['original_amount_minor'], 610000);
    expect(s.recurringPending.first['fields']['original_amount_minor'], 610000);
    expect(s.records(s.active).map((e) => e['data']['amount']).toSet(), {
      620000,
      610000,
    });
  });
  test('暂停恢复补齐或跳过，结束后不再生成', () async {
    final s = await store();
    await s.saveRecurringPlan(
      plan(s, anchor: '2026-01-01', interval: 1, total: null),
    );
    final count = s.recurringPending.length;
    await s.setRecurringStatus('rent', 'paused');
    await s.maintainRecurring(day: '2027-12-01');
    expect(s.recurringPending.length, count);
    s.active['recurring_occurrences'] = <Json>[];
    s.recurringPlans.single.remove('cursor');
    await s.persist();
    await s.setRecurringStatus('rent', 'active', skipMissed: true);
    expect(s.recurringPending, isEmpty);
    expect(localItems(s.active, 'recurring_occurrences'), isNotEmpty);
    await s.setRecurringStatus('rent', 'ended');
    await s.maintainRecurring(day: '2028-01-01');
    expect(s.recurringPlans.single['status'], 'ended');
  });
  test('关联已有流水不新增，错误日期或重复关联拒绝', () async {
    final s = await store();
    await s.saveRecurringPlan(plan(s));
    final o = s.recurringPending.single,
        d = await price(s, s.recurringPending.single);
    await s.saveEntry(d, id: 'imported');
    await expectLater(
      s.confirmRecurring(o['id'], {
        ...d,
        'date': '2020-01-01',
      }, existingId: 'imported'),
      throwsFormatException,
    );
    await s.confirmRecurring(o['id'], d, existingId: 'imported');
    expect(s.records(s.active).length, 1);
    await s.saveRecurringPlan(plan(s, id: 'other'));
    await expectLater(
      s.confirmRecurring(
        s.recurringPending.single['id'],
        d,
        existingId: 'imported',
      ),
      throwsFormatException,
    );
  });
  test('删除恢复关联流水保留期次，退款可追溯', () async {
    final s = await store();
    await s.saveRecurringPlan(plan(s));
    final o = s.recurringPending.single;
    await s.confirmRecurring(o['id'], await price(s, o));
    final entry = s.records(s.active).single;
    await s.refund(entry, 100000);
    expect(s.refundable(entry), 800000);
    await s.trashEntry(entry);
    expect(s.recurringPending, isEmpty);
    expect(s.hasRecurringLink(entry['id']), isTrue);
    final trashed = s
        .trashEntries(s.active)
        .firstWhere((e) => e['id'] == entry['id']);
    await s.restoreTrashEntry(s.active, trashed);
    expect(s.records(s.active).length, 2);
    validateBackup({'schema': 6, 'ledgers': s.ledgers});
  });
  test('模板白名单、空金额、同名替换和排序持久化', () async {
    final s = await store();
    final clean = templateFields({
      ...fields(s, amount: null),
      'source_key': 'order',
      'refund_of': 'old',
      'date': '2000-01-01',
      'fx_rate': '8',
    });
    expect(clean.containsKey('source_key'), isFalse);
    expect(clean.containsKey('fx_rate'), isFalse);
    expect(clean.containsKey('date'), isFalse);
    final t = {
      'id': 'one',
      'name': '午餐',
      'fields': clean,
      'order': 0,
      'pinned': true,
    };
    await s.saveRecordTemplate(t);
    await expectLater(
      s.saveRecordTemplate({...t, 'id': 'two'}),
      throwsFormatException,
    );
    await s.saveRecordTemplate({...t, 'id': 'two', 'name': '咖啡'});
    await s.reorderRecordTemplates(['two', 'one']);
    expect(s.recordTemplates.first['name'], '咖啡');
    await s.saveRecordTemplate({
      ...t,
      'id': 'three',
      'fields': fields(s, amount: 3000),
      'order': 1,
    }, replaceName: true);
    expect(s.recordTemplates.length, 2);
    expect(s.recordTemplates.last['id'], 'one');
    expect(
      (await readState(s.database!))!['ledgers'][0]['record_templates'].length,
      2,
    );
    await s.removeRecordTemplate('one');
    expect(s.recordTemplates.length, 1);
  });
  test('分类迁移模板、计划与待确认，失效引用阻止保存', () async {
    final s = await store();
    await s.saveRecordTemplate({'id': 't', 'name': '租金', 'fields': fields(s)});
    await s.saveRecurringPlan(plan(s));
    final old = s.categoryKey('房租'), next = s.categoryKey('水电燃气');
    await s.deleteDictionary(old, next);
    expect(s.recordTemplates.single['fields']['category_id'], next);
    expect(s.recurringPlans.single['fields']['category_id'], next);
    expect(s.recurringPending.single['fields']['category_id'], next);
    await s.deleteDictionary(next, '');
    expect(
      () => s.validateScheduleFields(s.recordTemplates.single['fields']),
      throwsFormatException,
    );
    expect(s.recurringPending.length, 1);
  });
  test('编辑周期保留历史快照、更新待确认且禁止与历史重叠', () async {
    final s = await store();
    await s.saveRecurringPlan(
      plan(s, anchor: '2026-01-31', interval: 1, total: 12),
    );
    final first = s.recurringPending.first;
    await s.confirmRecurring(first['id'], await price(s, first));
    final p = {...s.recurringPlans.single, 'anchor': '2026-02-01'};
    await expectLater(s.saveRecurringPlan(p), throwsFormatException);
    await s.saveRecurringPlan(p, updatePending: true);
    expect(
      localItems(s.active, 'recurring_occurrences').first['due'],
      '2026-01-31',
    );
    expect(s.recurringPending.first['due'], '2026-03-01');
    await expectLater(
      s.saveRecurringPlan({
        ...s.recurringPlans.single,
        'anchor': '2020-01-01',
      }, updatePending: true),
      throwsFormatException,
    );
  });
  test('乱序确认后修改日期不允许待确认期与已处理期重叠', () async {
    final s = await store();
    await s.saveRecurringPlan({
      ...plan(s, anchor: '2026-01-01', interval: 1, total: 12),
      'coverage': '2026-01-01',
    });
    final fifth = s.recurringPending.firstWhere((o) => o['period'] == 5);
    await s.confirmRecurring(fifth['id'], await price(s, fifth));
    await expectLater(
      s.saveRecurringPlan({
        ...s.recurringPlans.single,
        'anchor': '2026-02-01',
        'coverage': '2026-02-01',
      }, updatePending: true),
      throwsFormatException,
    );
    expect(s.recurringPending.first['due'], '2026-01-01');
  });
  test('租期独立付款日，末期不足整期标记', () async {
    final s = await store();
    final p = {
      ...plan(s, anchor: '2026-11-15'),
      'coverage': '2026-11-20',
      'end_date': '2027-09-30',
    };
    validateRecurringPlan(p);
    expect(recurringOccurrence(p, 1)!['due'], '2026-11-15');
    expect(recurringOccurrence(p, 1)!['coverage_end'], '2027-02-19');
    expect(recurringOccurrence(p, 4)!['partial'], isTrue);
  });
  test('备份拒绝重复发生键与缺失引用，旧备份兼容', () async {
    final s = await store();
    expect(
      validateBackup({'schema': 5, 'ledgers': s.ledgers})
          .single['record_templates'],
      isNull,
    );
    await s.saveRecurringPlan(plan(s));
    final copy = jsonDecode(jsonEncode(s.active)) as Json;
    (copy['recurring_occurrences'] as List).add(
      copy['recurring_occurrences'][0],
    );
    expect(
      () => validateBackup({
        'schema': 6,
        'ledgers': [copy],
      }),
      throwsFormatException,
    );
    final o = s.recurringPending.single;
    o['status'] = 'confirmed';
    o['entry_ids'] = ['missing'];
    expect(
      () => validateBackup({'schema': 6, 'ledgers': s.ledgers}),
      throwsFormatException,
    );
  });
  test('外币实际扣款离线保存，报价更新不重算', () async {
    final s = await store();
    await s.saveRecurringPlan({
      ...plan(s),
      'fields': fields(s, amount: 10000, currency: 'USD'),
    });
    final o = s.recurringPending.single;
    await s.confirmRecurring(
      o['id'],
      await s.schedulePricing(o['fields'], today(), actual: 72000),
    );
    expect(s.records(s.active).single['data']['fx_mode'], 'actual');
    s.state['fxLatest'] = {'bad': 'new'};
    expect(s.records(s.active).single['data']['amount'], 72000);
  });
  test('通知最多三日，暂停副本不安排', () async {
    final s = await store();
    final p = {
      ...plan(s, anchor: '2026-12-01', interval: 1, total: 12),
      'notify': true,
    };
    s.active['recurring_plans'] = [p];
    expect(recurringReminderDays(s.ledgers, '2026-11-01').length, 3);
    p['status'] = 'paused';
    expect(recurringReminderDays(s.ledgers, '2026-11-01'), isEmpty);
  });
  test('完整文件备份使用版本6，恢复模板及暂停计划，旧空账本保持版本5', () async {
    final s = await store();
    final old = await s.exportBackupFile();
    expect(jsonDecode(utf8.decode(old))['snapshot']['schema'], 5);
    await s.saveRecordTemplate({
      'id': 't',
      'name': '午餐',
      'fields': fields(s, amount: null),
      'pinned': true,
    });
    await s.saveRecurringPlan(plan(s));
    final file = await s.exportBackupFile();
    expect(jsonDecode(utf8.decode(file))['snapshot']['schema'], 6);
    await s.restorePreview(await s.inspectBackupFile(file, 'v074.json'));
    final copy = s.ledgers.last;
    expect(
      localItems(
        copy,
        'record_templates',
      ).single['fields']['original_amount_minor'],
      isNull,
    );
    expect(localItems(copy, 'recurring_plans').single['status'], 'paused');
    expect(pendingOccurrences(copy).length, 1);
  });
  test('合同结束自动算期数，冲突期数拒绝；旧编辑修订不能覆盖新默认值', () async {
    final s = await store();
    final p = {
      ...plan(s, anchor: '2026-01-01', total: null),
      'coverage': '2026-01-01',
      'end_date': '2026-11-30',
    };
    await s.saveRecurringPlan(p);
    expect(s.recurringPlans.single['total'], 4);
    expect(
      () => validateRecurringPlan({...p, 'total': 2}),
      throwsFormatException,
    );
    final stale = jsonDecode(jsonEncode(s.recurringPlans.single)) as Json;
    final o = s.recurringPending.first;
    await s.confirmRecurring(
      o['id'],
      await price(s, o, amount: 620000),
      updateFuture: true,
    );
    await expectLater(s.saveRecurringPlan(stale), throwsFormatException);
    expect(s.recurringPlans.single['fields']['original_amount_minor'], 620000);
  });
  testWidgets('模板进入完整记账页，全选金额且单次修改不影响模板', (t) async {
    late LedgerStore s;
    await t.runAsync(() async {
      s = await store();
      await s.saveRecordTemplate({
        'id': 'lunch',
        'name': '午餐',
        'fields': fields(s, amount: 2800),
        'pinned': true,
      });
    });
    await t.pumpWidget(MaterialApp(home: TemplatesPage(s)));
    await t.tap(find.text('午餐'));
    await t.pumpAndSettle();
    expect(find.byType(RecordPage), findsOneWidget);
    final c = t
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((w) => w.controller?.text == '28.00')
        .controller!;
    expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
    c.text = '36';
    expect(s.recordTemplates.single['fields']['original_amount_minor'], 2800);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('360像素房贷设置与确认页无布局异常', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    late LedgerStore s;
    await t.runAsync(() async {
      s = await store();
      await s.saveRecurringPlan(plan(s, deposit: true));
    });
    await t.pumpWidget(MaterialApp(home: RecurringEditor(s, kind: 'mortgage')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('购房还贷'), findsWidgets);
    await t.drag(find.byType(ListView).first, const Offset(0, -1500));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(
      MaterialApp(
        home: RecurringConfirmation(s, s.recurringPending.single['id']),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('本期账单'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
