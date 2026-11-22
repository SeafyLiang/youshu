import 'domain.dart';

/// Plain local-calendar dates retain the original month/day anchor.
DateTime recurringDate(DateTime anchor, int offset, int interval, String unit) {
  final n = offset * interval;
  if (unit == 'day' || unit == 'week') {
    return DateTime(
      anchor.year,
      anchor.month,
      anchor.day + n * (unit == 'week' ? 7 : 1),
    );
  }
  final month = DateTime(
    anchor.year + (unit == 'year' ? n : 0),
    anchor.month + (unit == 'month' ? n : 0),
  );
  final last = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(
    month.year,
    month.month,
    anchor.day > last ? last : anchor.day,
  );
}

List<Json> localItems(Json book, String key) =>
    (book[key] as List? ?? const []).cast<Json>();
const recurringUnits = {'day': '天', 'week': '周', 'month': '个月', 'year': '年'};

Json templateFields(Json data) => {
  'type': data['type'] ?? 'expense',
  'category_id': data['category_id'] ?? '',
  'account': data['account'] ?? '银行卡',
  'original_currency': data['original_currency'] ?? 'CNY',
  'original_amount_minor': data['original_amount_minor'] ?? data['amount'],
  'tag_ids': List<String>.from(data['tag_ids'] ?? []),
  'note': data['note'] ?? '',
  for (final k in ['member', 'merchant', 'project'])
    if (data[k] != null) k: data[k],
};

void validateTemplate(Json item, {bool amountRequired = false}) {
  if (item['id'] is! String ||
      (item['id'] as String).isEmpty ||
      item['name'] is! String ||
      (item['name'] as String).trim().isEmpty ||
      (item['name'] as String).length > 50) {
    throw const FormatException('请填写 1–50 字名称');
  }
  final d = item['fields'];
  if (d is! Map ||
      !['income', 'expense'].contains(d['type']) ||
      !currencies.containsKey(d['original_currency']) ||
      d['account'] is! String ||
      d['category_id'] is! String ||
      d['tag_ids'] is! List ||
      (d['tag_ids'] as List).any((e) => e is! String) ||
      d['note'] is! String) {
    throw const FormatException('模板字段不完整');
  }
  final n = d['original_amount_minor'];
  if ((amountRequired && n == null) ||
      (n != null && (n is! int || n <= 0 || n > 999999999999))) {
    throw const FormatException('金额须大于 0 且不超过上限');
  }
}

DateTime calendarDate(Object? value) {
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null ||
      dateKey(date) != value ||
      date.year < 1900 ||
      date.year > 9999) {
    throw const FormatException('日期无效');
  }
  return DateTime(date.year, date.month, date.day);
}

void validateRecurringPlan(Json p) {
  validateTemplate(p, amountRequired: true);
  calendarDate(p['anchor']);
  if (!recurringUnits.containsKey(p['unit']) ||
      p['interval'] is! int ||
      p['interval'] < 1 ||
      p['interval'] > 1200 ||
      p['start'] is! int ||
      p['start'] < 1 ||
      p['start'] > 100000 ||
      p['early'] is! int ||
      p['early'] < 0 ||
      p['early'] > 365 ||
      !['active', 'paused', 'ended'].contains(p['status'])) {
    throw const FormatException('周期、期号或提前天数无效');
  }
  if (p['total'] != null &&
      (p['total'] is! int || p['total'] < p['start'] || p['total'] > 100000)) {
    throw const FormatException('总期数须不小于起始期号，最多 100000 期');
  }
  if ((p['cursor'] != null &&
          (p['cursor'] is! int ||
              p['cursor'] < p['start'] ||
              p['cursor'] > 5000000)) ||
      (p['notify'] != null && p['notify'] is! bool)) {
    throw const FormatException('周期进度或提醒设置无效');
  }
  if (p['coverage'] != null) calendarDate(p['coverage']);
  if (p['end_date'] != null) {
    final end = calendarDate(p['end_date']);
    if (p['coverage'] == null || end.isBefore(calendarDate(p['coverage']))) {
      throw const FormatException('合同结束日须不早于本期租期开始');
    }
  }
  final extra = p['extra'];
  if (extra != null &&
      (extra is! Map ||
          extra['amount'] is! int ||
          extra['amount'] <= 0 ||
          extra['amount'] > 999999999999 ||
          extra['period'] is! int ||
          extra['period'] < 1 ||
          extra['category_id'] is! String ||
          extra['name'] is! String ||
          (p['total'] != null && extra['period'] > p['total']))) {
    throw const FormatException('附加项目金额、分类或发生期无效');
  }
  if (p['total'] != null) {
    final last = recurringDate(
      calendarDate(p['anchor']),
      p['total'] - p['start'],
      p['interval'],
      p['unit'],
    );
    if (last.year > 9999) throw const FormatException('末期日期超出范围');
  }
  if (p['end_date'] != null &&
      p['total'] != null &&
      p['total'] != contractLastPeriod(p)) {
    throw const FormatException('合同结束日与总期数不一致，请清空总期数按合同计算，或调整结束日');
  }
}

int contractLastPeriod(Json p) {
  final end = calendarDate(p['end_date']), start = calendarDate(p['coverage']);
  for (var offset = 1; offset <= 100000; offset++) {
    if (recurringDate(start, offset, p['interval'], p['unit']).isAfter(end)) {
      return (p['start'] as int) + offset - 1;
    }
  }
  throw const FormatException('合同期数超出上限');
}

Json? recurringOccurrence(Json plan, int period) {
  if (period < plan['start'] ||
      (plan['total'] != null && period > plan['total'])) {
    return null;
  }
  final offset = period - (plan['start'] as int);
  final due = recurringDate(
    calendarDate(plan['anchor']),
    offset,
    plan['interval'],
    plan['unit'],
  );
  if (due.year > 9999) return null;
  String? coverageStart, coverageEnd;
  bool partial = false;
  if (plan['coverage'] != null) {
    final start = recurringDate(
      calendarDate(plan['coverage']),
      offset,
      plan['interval'],
      plan['unit'],
    );
    var end = recurringDate(
      calendarDate(plan['coverage']),
      offset + 1,
      plan['interval'],
      plan['unit'],
    ).subtract(const Duration(days: 1));
    if (plan['end_date'] != null) {
      final contractEnd = calendarDate(plan['end_date']);
      if (start.isAfter(contractEnd)) return null;
      if (end.isAfter(contractEnd)) {
        end = contractEnd;
        partial = true;
      }
    }
    coverageStart = dateKey(start);
    coverageEnd = dateKey(end);
  }
  final extra = plan['extra'];
  return {
    'id': '${plan['id']}:$period',
    'plan_id': plan['id'],
    'period': period,
    'due': dateKey(due),
    'status': 'pending',
    'name': plan['name'],
    'fields': templateFields(Map<String, dynamic>.from(plan['fields'])),
    'coverage_start': coverageStart,
    'coverage_end': coverageEnd,
    'partial': partial,
    if (extra != null && extra['period'] == period && extra['paid'] != true)
      'extra': Map<String, dynamic>.from(extra),
    'entry_ids': <String>[],
  };
}

String recurringFrequency(Json p) =>
    '每 ${p['interval']} ${recurringUnits[p['unit']]}';

List<Json> pendingOccurrences(Json book) =>
    localItems(
        book,
        'recurring_occurrences',
      ).where((o) => o['status'] == 'pending').toList()
      ..sort((a, b) => (a['due'] as String).compareTo(b['due']));

/// Immutable snapshots are keyed by plan ID + period; processed periods never regenerate.
bool generateRecurring(
  Json book,
  String day, {
  bool skipDue = false,
  String? onlyPlan,
}) {
  final now = calendarDate(day);
  final list = List<Json>.from(localItems(book, 'recurring_occurrences'));
  final ids = list.map((o) => o['id']).toSet();
  bool changed = false;
  for (final plan in localItems(book, 'recurring_plans')) {
    if (plan['status'] != 'active' ||
        (onlyPlan != null && plan['id'] != onlyPlan)) {
      continue;
    }
    validateRecurringPlan(plan);
    final until = DateTime(
      now.year,
      now.month,
      now.day + (plan['early'] as int),
    );
    var count = 0;
    // Persist the cursor so long-lived daily plans do not rescan history.
    var period = plan['cursor'] as int? ?? plan['start'] as int;
    for (; count < 100000; period++, count++) {
      final next = recurringOccurrence(plan, period);
      if (next == null) break;
      if (calendarDate(next['due']).isAfter(until)) break;
      if (ids.add(next['id'])) {
        if (skipDue) next['status'] = 'skipped';
        list.add(next);
        changed = true;
      }
    }
    if (plan['cursor'] != period) {
      plan['cursor'] = period;
      changed = true;
    }
    final remaining = list.any(
      (o) => o['plan_id'] == plan['id'] && o['status'] == 'pending',
    );
    if (recurringOccurrence(plan, period) == null && !remaining) {
      plan['status'] = 'ended';
      changed = true;
    }
  }
  if (changed) book['recurring_occurrences'] = list;
  return changed;
}

void validateLocalSchedules(Json book) {
  for (final key in [
    'record_templates',
    'recurring_plans',
    'recurring_occurrences',
  ]) {
    if (book[key] != null && book[key] is! List) {
      throw const FormatException('周期或模板数据无效');
    }
    final ids = <String>{};
    for (final item in localItems(book, key)) {
      if (item['id'] is! String || !ids.add(item['id'])) {
        throw const FormatException('模板或周期记录重复');
      }
      if (key == 'record_templates') {
        validateTemplate(item);
        if ((item['order'] != null && item['order'] is! int) ||
            (item['pinned'] != null && item['pinned'] is! bool)) {
          throw const FormatException('模板排序或置顶字段无效');
        }
      }
      if (key == 'recurring_plans') validateRecurringPlan(item);
    }
  }
  final plans = {
    for (final p in localItems(book, 'recurring_plans')) p['id']: p,
  };
  final usedEntries = <String>{};
  final entries = {for (final e in book['entries']) e['id']: e};
  for (final o in localItems(book, 'recurring_occurrences')) {
    if (!plans.containsKey(o['plan_id']) ||
        o['period'] is! int ||
        o['period'] < 1 ||
        o['id'] != '${o['plan_id']}:${o['period']}' ||
        ![
          'pending',
          'confirmed',
          'skipped',
          'cancelled',
        ].contains(o['status']) ||
        o['entry_ids'] is! List) {
      throw const FormatException('周期发生记录无效');
    }
    calendarDate(o['due']);
    validateTemplate({
      'id': o['id'],
      'name': o['name'],
      'fields': o['fields'],
    }, amountRequired: true);
    if (o['coverage_start'] != null) {
      calendarDate(o['coverage_start']);
      calendarDate(o['coverage_end']);
    }
    if (o['extra'] != null) {
      final x = o['extra'];
      if (x is! Map ||
          x['amount'] is! int ||
          x['amount'] <= 0 ||
          x['amount'] > 999999999999 ||
          x['category_id'] is! String ||
          x['name'] is! String) {
        throw const FormatException('周期附加项目无效');
      }
    }
    if (o['status'] != 'confirmed' && (o['entry_ids'] as List).isNotEmpty) {
      throw const FormatException('未确认周期不能关联流水');
    }
    for (final id in o['entry_ids']) {
      if (!entries.containsKey(id) ||
          entries[id]['kind'] != 'entry' ||
          !usedEntries.add(id)) {
        throw const FormatException('周期流水关联缺失或重复');
      }
    }
    if (o['status'] == 'confirmed' && (o['entry_ids'] as List).isEmpty) {
      throw const FormatException('已确认周期缺少流水');
    }
  }
}

/// Aggregate upcoming generation dates to fit the OS pending notification limit.
List<Json> recurringReminderDays(List<Json> books, String today) {
  final groups = <String, Set<String>>{};
  for (final book in books) {
    for (final p in localItems(book, 'recurring_plans')) {
      if (p['status'] != 'active' || p['notify'] != true) continue;
      final processed = localItems(book, 'recurring_occurrences')
          .where((o) => o['plan_id'] == p['id'] && o['status'] != 'pending')
          .map((o) => o['period'])
          .toSet();
      var added = 0;
      // Start at the latest generated period, but include pending snapshots.
      final candidates = <int>{
        for (final o in localItems(book, 'recurring_occurrences'))
          if (o['plan_id'] == p['id'] && o['status'] == 'pending') o['period'],
        for (var i = 0; i < 4; i++)
          (p['cursor'] as int? ?? p['start'] as int) + i,
      }.toList()..sort();
      for (final period in candidates) {
        if (processed.contains(period)) continue;
        final o = recurringOccurrence(p, period);
        if (o == null) break;
        final due = calendarDate(o['due']);
        final day = dateKey(
          DateTime(due.year, due.month, due.day - (p['early'] as int)),
        );
        if (day.compareTo(today) < 0) continue;
        (groups[day] ??= {}).add('${book['name']} · ${p['name']}');
        if (++added >= 3) break;
      }
    }
  }
  final days = groups.keys.toList()..sort();
  return [
    for (final day in days.take(3))
      {'day': day, 'names': groups[day]!.join('、')},
  ];
}
