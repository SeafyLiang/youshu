import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youshu/store.dart';

LedgerStore largeStore(int count) {
  final s = LedgerStore(), l = freshLedger('性能样本');
  final cats = dictionary(l, 'category', type: 'expense');
  for (var i = 0; i < count; i++) {
    final c = cats[i % cats.length];
    (l['entries'] as List).add(
      entity('row-$i', 'entry', {
        'date': dateKey(DateTime(2020, 1, 1).add(Duration(days: i % 2400))),
        'time': '12:30',
        'type': 'expense',
        'category_id': c['id'],
        'category': c['data']['name'],
        'amount': 1234,
        'base_amount_minor': 1234,
        'original_amount_minor': 1234,
        'original_currency': 'CNY',
        'base_currency': 'CNY',
        'tag_ids': <String>[],
        'account': '现金',
        'note': '合成性能记录',
      }),
    );
  }
  s.state['ledgers'] = [l];
  s.state['active'] = l['id'];
  return s;
}

void main() {
  test('6000/10000 条查询性能', () {
    final results = <String, dynamic>{};
    for (final size in [6000, 10000]) {
      final s = largeStore(size), watch = Stopwatch()..start();
      for (final c in s.choices('category', type: 'expense')) {
        s.total('2026-07', 'expense', category: c['id']);
        s.budget('2026-07', c['id']);
      }
      final budgetMs = watch.elapsedMicroseconds / 1000;
      watch.reset();
      final f = EntryFilter()
        ..start = '2020-01-01'
        ..end = '2027-01-01';
      expect(
        f.apply(s.active, s.records(s.active), s.period('2026-07')).length,
        size,
      );
      expect(budgetMs, lessThan(1000), reason: '预算查询退化');
      expect(watch.elapsedMilliseconds, lessThan(1000), reason: '流水筛选退化');
      results['$size'] = {
        'budget_ms': budgetMs,
        'filter_ms': watch.elapsedMicroseconds / 1000,
      };
    }
    stdout.writeln(jsonEncode(results));
    final output = Platform.environment['YOUSHU_PERF_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(jsonEncode(results));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
