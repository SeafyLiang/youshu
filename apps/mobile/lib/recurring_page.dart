import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'store.dart';
import 'dictionary_page.dart';
import 'templates_page.dart';
import 'reminders.dart';
import 'ui.dart';

Future<void> newRecurring(BuildContext context, LedgerStore s) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '新增周期记账',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              subtitle: Text('选一个模板，填写金额、日期与期数'),
            ),
            for (final t in [
              ('rent', '房租', '按月／季付款，支持押金与租期', CupertinoIcons.house),
              (
                'mortgage',
                '房贷',
                '每月还款，按实际账单确认',
                CupertinoIcons.building_2_fill,
              ),
              ('custom', '自定义周期', '分期账单、订阅、固定收入等', CupertinoIcons.add),
            ])
              ListTile(
                leading: Icon(t.$4, color: expenseInk(c)),
                title: Text(t.$2),
                subtitle: Text(t.$3),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, t.$1),
              ),
          ],
        ),
      ),
    ),
  );
  if (kind != null && context.mounted) {
    await Navigator.push(
      context,
      AppPageRoute(builder: (_) => RecurringEditor(s, kind: kind)),
    );
  }
}

class RecurringList extends StatefulWidget {
  final LedgerStore s;
  const RecurringList(this.s, {super.key});
  @override
  State<RecurringList> createState() => _RecurringListState();
}

class _RecurringListState extends State<RecurringList> {
  LedgerStore get s => widget.s;
  @override
  void initState() {
    super.initState();
    s.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        '${s.active['name']} · ${s.recurringPlans.length} 个计划',
        style: TextStyle(color: secondaryInk(context)),
      ),
      const SizedBox(height: 8),
      hint('按期生成待确认账单，确认收付后计入流水。'),
      const SizedBox(height: 16),
      if (s.recurringPending.isNotEmpty) ...[
        Text(
          '待确认 · ${s.recurringPending.length}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final o in s.recurringPending.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassPanel(
              child: ListTile(
                title: Text('${o['name']} · 第 ${o['period']} 期'),
                subtitle: Text(
                  '${o['due']} · ${o['fields']['original_currency']} ${formatAmount(o['fields']['original_amount_minor'], o['fields']['original_currency'])}${o['extra'] != null ? ' + ${o['extra']['name']}' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  AppPageRoute(
                    builder: (_) => RecurringConfirmation(s, o['id']),
                  ),
                ),
              ),
            ),
          ),
        if (s.recurringPending.length > 5)
          TextButton(
            onPressed: () => Navigator.push(
              context,
              AppPageRoute(builder: (_) => RecurringHistory(s)),
            ),
            child: const Text('查看全部待确认'),
          ),
        const SizedBox(height: 16),
      ],
      if (s.recurringPlans.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Text('让固定收付按期待办\n房租、房贷、分期都可以', textAlign: TextAlign.center),
        ),
      for (final p in s.recurringPlans)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassPanel(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(
                p['name'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${recurringFrequency(p)} · ${p['fields']['original_currency']} ${formatAmount(p['fields']['original_amount_minor'], p['fields']['original_currency'])}\n${planProgress(s.active, p)}',
                ),
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                AppPageRoute(builder: (_) => RecurringDetail(s, p['id'])),
              ),
            ),
          ),
        ),
      FilledButton.icon(
        onPressed: s.canEdit ? () => newRecurring(context, s) : null,
        icon: const Icon(Icons.add),
        label: const Text('新增周期记账'),
      ),
    ],
  );
}

String planProgress(Json book, Json p) {
  if (p['status'] == 'paused') return '已暂停 · 历史和待确认项保留';
  if (p['status'] == 'ended') return '计划已结束';
  final rows = localItems(
    book,
    'recurring_occurrences',
  ).where((o) => o['plan_id'] == p['id']).toList();
  final pending = rows.where((o) => o['status'] == 'pending').toList()
    ..sort((a, b) => (a['period'] as int).compareTo(b['period']));
  final next =
      pending.firstOrNull ?? recurringOccurrence(p, p['cursor'] ?? p['start']);
  return next == null
      ? '等待完成本期待确认'
      : '下期 ${next['due']} · 第 ${next['period']}${p['total'] == null ? '' : ' / ${p['total']}'} 期';
}

class RecurringEditor extends StatefulWidget {
  final LedgerStore s;
  final String kind;
  final Json? existing;
  const RecurringEditor(
    this.s, {
    super.key,
    this.kind = 'custom',
    this.existing,
  });
  @override
  State<RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<RecurringEditor> {
  final name = TextEditingController(),
      interval = TextEditingController(),
      total = TextEditingController(),
      first = TextEditingController(),
      early = TextEditingController(),
      extra = TextEditingController(),
      extraName = TextEditingController(),
      extraPeriod = TextEditingController();
  late Json draft;
  late String unit, anchor, kind, bookId;
  String? coverage, endDate, extraCategory;
  bool paid = false, notify = false, saving = false;
  final monthly = TextEditingController();
  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    kind = p?['preset'] ?? widget.kind;
    bookId = widget.s.active['id'];
    draft = p != null ? editableDefaults(p['fields']) : blankDefaults(widget.s);
    name.text =
        p?['name'] ??
        (kind == 'rent'
            ? '房租'
            : kind == 'mortgage'
            ? '房贷'
            : '');
    if (p == null && kind != 'custom') {
      final matches = widget.s
          .choices('category', type: 'expense')
          .where(
            (c) => (c['data']['name'] as String).contains(
              kind == 'rent' ? '房租' : '还贷',
            ),
          );
      // Do not silently classify a mortgage as an unrelated category.
      draft['category_id'] = matches.firstOrNull?['id'] ?? '';
    }
    unit = p?['unit'] ?? 'month';
    anchor = p?['anchor'] ?? today();
    coverage = p?['coverage'] ?? (kind == 'rent' ? today() : null);
    endDate = p?['end_date'];
    interval.text = '${p?['interval'] ?? (kind == 'rent' ? 3 : 1)}';
    total.text = p?['total']?.toString() ?? '';
    first.text = '${p?['start'] ?? 1}';
    early.text = '${p?['early'] ?? (kind == 'rent' ? 7 : 3)}';
    final x = p?['extra'];
    extra.text = x == null
        ? ''
        : formatAmount(x['amount'], draft['original_currency']);
    extraName.text = x?['name'] ?? (kind == 'rent' ? '租房押金' : '一次性费用');
    extraPeriod.text = '${x?['period'] ?? 1}';
    extraCategory = x?['category_id'];
    paid = x?['paid'] ?? false;
    notify = p?['notify'] ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      name,
      interval,
      total,
      first,
      early,
      extra,
      extraName,
      extraPeriod,
      monthly,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick(String value, ValueChanged<String> apply) async {
    final d = await showDatePicker(
      context: context,
      initialDate: calendarDate(value),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (d != null) setState(() => apply(dateKey(d)));
  }

  Widget dateRow(String label, String value, ValueChanged<String> apply) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(value),
        trailing: const Icon(Icons.calendar_today_outlined, size: 20),
        onTap: () => pick(value, apply),
      );
  Widget number(TextEditingController c, String label) => TextField(
    controller: c,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
  );
  Json readPlan() {
    final fields = readDefaults(draft, requiredAmount: true);
    final p = <String, dynamic>{
      'id': widget.existing?['id'] ?? uuid.v4(),
      'name': name.text.trim(),
      'preset': kind,
      'fields': fields,
      'interval': int.tryParse(interval.text),
      'unit': unit,
      'anchor': anchor,
      'start': int.tryParse(first.text),
      'total': total.text.trim().isEmpty ? null : int.tryParse(total.text),
      'early': int.tryParse(early.text),
      'status': widget.existing?['status'] ?? 'active',
      'revision': widget.existing?['revision'],
      'notify': notify,
      'coverage': coverage,
      'end_date': endDate,
    };
    if (total.text.trim().isNotEmpty && p['total'] == null) {
      throw const FormatException('总期数无效');
    }
    if (extra.text.trim().isNotEmpty) {
      p['extra'] = {
        'name': extraName.text.trim(),
        'amount': parseAmount(extra.text, fields['original_currency']),
        'period': int.tryParse(extraPeriod.text),
        'category_id': extraCategory ?? '',
        'paid': paid,
      };
    }
    validateRecurringPlan(p);
    if (p['end_date'] != null && p['total'] == null) {
      p['total'] = contractLastPeriod(p);
    }
    widget.s.validateScheduleFields(fields);
    if (p['extra'] != null) {
      widget.s.validateScheduleFields({
        ...fields,
        'category_id': extraCategory ?? '',
      });
    }
    return p;
  }

  Future<void> preview() async {
    try {
      if (widget.s.active['id'] != bookId) {
        throw const FormatException('账本已切换，请重新打开');
      }
      final p = readPlan();
      final result = await Navigator.push<bool>(
        context,
        AppPageRoute(
          builder: (_) =>
              RecurringPreview(widget.s, p, editing: widget.existing != null),
        ),
      );
      if (result == true && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? '新增周期记账' : '编辑周期')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.s.active['name'],
            style: TextStyle(color: expenseInk(context)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: '计划名称',
              hintText: '例如手机分期',
            ),
          ),
          DefaultsForm(
            widget.s,
            draft,
            amountRequired: true,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: number(interval, '每隔')),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: '重复单位'),
                  items: recurringUnits.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => unit = v!),
                ),
              ),
            ],
          ),
          dateRow('首次待记日期', anchor, (v) => anchor = v),
          Row(
            children: [
              Expanded(child: number(total, '总期数（留空持续）')),
              const SizedBox(width: 12),
              Expanded(child: number(first, '从第几期开始')),
            ],
          ),
          const SizedBox(height: 12),
          hint('从第 5 / 12 期接入，只安排余下 8 期。前面的期次不新增流水。'),
          if (kind == 'rent') ...[
            const SizedBox(height: 16),
            const Text('租期与月租', style: TextStyle(fontWeight: FontWeight.w600)),
            dateRow('本次租期开始', coverage ?? anchor, (v) => coverage = v),
            if (endDate != null) dateRow('合同结束日', endDate!, (v) => endDate = v),
            TextButton(
              onPressed: () => endDate != null
                  ? setState(() => endDate = null)
                  : pick(coverage ?? anchor, (v) => endDate = v),
              child: Text(endDate == null ? '设置合同结束日' : '取消合同结束日'),
            ),
            TextField(
              controller: monthly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '月租（用于辅助计算每期金额）'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  if (unit != 'month') throw const FormatException('请先选择按月重复');
                  final n =
                      parseAmount(monthly.text, draft['original_currency']) *
                      (int.tryParse(interval.text) ?? 0);
                  if (n <= 0) throw const FormatException('请填写有效周期');
                  if (await approve(
                    context,
                    '更新每期金额？',
                    '月租 × ${interval.text} 个月 = ${formatAmount(n, draft['original_currency'])} ${draft['original_currency']}',
                  )) {
                    setState(() {
                      draft['_amount'] = formatAmount(
                        n,
                        draft['original_currency'],
                      );
                      draft['original_amount_minor'] = n;
                    });
                  }
                } catch (e) {
                  if (context.mounted) message(context, e);
                }
              },
              child: const Text('按月租 × 周期填入每期金额'),
            ),
          ],
          ExpansionTile(
            initiallyExpanded:
                kind == 'rent' || widget.existing?['extra'] != null,
            tilePadding: EdgeInsets.zero,
            title: Text(kind == 'rent' ? '首期押金' : '一次性附加项目'),
            children: [
              TextField(
                controller: extraName,
                maxLength: 50,
                decoration: const InputDecoration(labelText: '项目名称'),
              ),
              TextField(
                controller: extra,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${draft['original_currency']} 金额（留空不添加）',
                ),
              ),
              const SizedBox(height: 12),
              number(extraPeriod, '发生在第几期'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('extra-${draft['type']}-$extraCategory'),
                isExpanded: true,
                initialValue:
                    widget.s
                        .choices('category', type: draft['type'])
                        .any((c) => c['id'] == extraCategory)
                    ? extraCategory
                    : null,
                decoration: const InputDecoration(labelText: '单独记入分类'),
                items: widget.s
                    .choices('category', type: draft['type'])
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: c['id'],
                        child: Text(
                          categoryName(widget.s.active, {
                            'category_id': c['id'],
                          }),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => extraCategory = v),
              ),
              TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    AppPageRoute(
                      builder: (_) =>
                          DictionaryPage(widget.s, initialType: draft['type']),
                    ),
                  );
                  if (mounted) setState(() {});
                },
                child: const Text('管理分类（可新建租房押金）'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('此项目已付，不再新增'),
                value: paid,
                onChanged: (v) => setState(() => paid = v!),
              ),
              hint('附加项目只在指定期发生。从较晚期次接入，不补记首期押金；未付押金可指定实际补记期。'),
            ],
          ),
          const SizedBox(height: 12),
          number(early, '提前生成天数（0–365）'),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('本地通知提醒'),
            subtitle: const Text('通知只提醒，打开应用时补生成待确认账单'),
            value: notify,
            onChanged: (v) => setState(() => notify = v),
          ),
          if (kind == 'mortgage') hint('以银行账单金额为准。本期变化可在确认时修改，不计算贷款利率或剩余本金。'),
          const SizedBox(height: 20),
          FilledButton(onPressed: preview, child: const Text('预览周期计划')),
        ],
      ),
    ),
  );
}

class RecurringPreview extends StatefulWidget {
  final LedgerStore s;
  final Json plan;
  final bool editing, readOnly;
  const RecurringPreview(
    this.s,
    this.plan, {
    super.key,
    this.editing = false,
    this.readOnly = false,
  });
  @override
  State<RecurringPreview> createState() => _RecurringPreviewState();
}

class _RecurringPreviewState extends State<RecurringPreview> {
  int shown = 12;
  bool saving = false, updatePending = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final rows = <Json>[];
    for (var i = p['start'] as int; i < (p['start'] as int) + shown; i++) {
      final o = recurringOccurrence(p, i);
      if (o == null) break;
      rows.add(o);
    }
    final pending = localItems(widget.s.active, 'recurring_occurrences')
        .where((o) => o['plan_id'] == p['id'] && o['status'] == 'pending')
        .toList();
    final last = p['total'] == null ? null : recurringOccurrence(p, p['total']);
    return Scaffold(
      appBar: AppBar(title: const Text('周期计划预览')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              p['name'],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${recurringFrequency(p)} · ${p['total'] == null ? '持续重复' : '共 ${p['total']} 期，从第 ${p['start']} 期开始'}',
            ),
            if (last != null) Text('末期 ${last['due']}'),
            const SizedBox(height: 12),
            if (p['end_date'] != null)
              hint('租期到 ${p['end_date']} 截止；覆盖期间不足整期时，确认实际金额后记账。'),
            for (final o in rows)
              Card(
                child: ListTile(
                  title: Text('第 ${o['period']} 期 · ${o['due']}'),
                  subtitle: Text(
                    '${o['fields']['original_currency']} ${formatAmount(o['fields']['original_amount_minor'] + (o['extra']?['amount'] ?? 0), o['fields']['original_currency'])}${o['extra'] != null ? '（含 ${o['extra']['name']}）' : ''}${o['coverage_start'] != null ? '\n租期 ${o['coverage_start']} 至 ${o['coverage_end']}' : ''}${o['partial'] == true ? '\n末期不足整期，请核对实际金额' : ''}',
                  ),
                ),
              ),
            if (rows.length == shown &&
                recurringOccurrence(p, (p['start'] as int) + shown) != null)
              TextButton(
                onPressed: () => setState(() => shown += 24),
                child: const Text('继续查看后续期次'),
              ),
            if (widget.editing && pending.isNotEmpty)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: updatePending,
                onChanged: (v) => setState(() => updatePending = v!),
                title: Text('同时更新 ${pending.length} 个待确认项'),
                subtitle: Text(
                  pending
                      .take(8)
                      .map((o) => '第 ${o['period']} 期 ${o['due']}')
                      .join('、'),
                ),
              ),
            const SizedBox(height: 12),
            hint('待确认账单不计入收支。确认实际收付后才写入流水。'),
            const SizedBox(height: 16),
            if (!widget.readOnly)
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setState(() => saving = true);
                        try {
                          await widget.s.saveRecurringPlan(
                            p,
                            updatePending: updatePending,
                          );
                          if (p['notify'] == true) {
                            await AppReminders.instance.requestPermission();
                          }
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (e) {
                          if (context.mounted) message(context, e);
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
                child: Text(saving ? '保存中…' : '确认保存计划'),
              ),
          ],
        ),
      ),
    );
  }
}

class RecurringDetail extends StatefulWidget {
  final LedgerStore s;
  final String id;
  const RecurringDetail(this.s, this.id, {super.key});
  @override
  State<RecurringDetail> createState() => _RecurringDetailState();
}

class _RecurringDetailState extends State<RecurringDetail> {
  LedgerStore get s => widget.s;
  @override
  void initState() {
    super.initState();
    s.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(refresh);
    super.dispose();
  }

  Future<void> status(Json p, String status) async {
    try {
      bool skip = false, cancel = false;
      if (status == 'active') {
        final choice = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('恢复周期计划'),
            content: const Text('选择暂停期间已到生成日的期次如何处理。已有待确认项保持不变。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, 'skip'),
                child: const Text('标记已跳过'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, 'fill'),
                child: const Text('补齐待确认'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        skip = choice == 'skip';
      } else if (status == 'ended') {
        final choice = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('结束计划？'),
            content: const Text('历史保留，不再生成后续期次。选择如何处理当前待确认账单。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('返回'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, 'keep'),
                child: const Text('保留待确认'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, 'cancel'),
                child: const Text('取消待确认'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        cancel = choice == 'cancel';
      }
      await s.setRecurringStatus(
        p['id'],
        status,
        skipMissed: skip,
        cancelPending: cancel,
      );
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = s.recurringPlans.firstWhere((p) => p['id'] == widget.id);
    return Scaffold(
      appBar: AppBar(title: Text(p['name'])),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlassPanel(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p['fields']['original_currency']} ${formatAmount(p['fields']['original_amount_minor'], p['fields']['original_currency'])}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(recurringFrequency(p)),
                  const SizedBox(height: 12),
                  Text(planProgress(s.active, p)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => RecurringEditor(s, existing: p)),
                ),
                child: const Text('编辑计划'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  AppPageRoute(
                    builder: (_) => RecurringPreview(s, p, readOnly: true),
                  ),
                ),
                child: const Text('查看计划'),
              ),
              if (p['status'] != 'ended')
                OutlinedButton(
                  onPressed: () =>
                      status(p, p['status'] == 'paused' ? 'active' : 'paused'),
                  child: Text(p['status'] == 'paused' ? '恢复' : '暂停'),
                ),
              if (p['status'] != 'ended')
                TextButton(
                  onPressed: () => status(p, 'ended'),
                  child: const Text('结束计划'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('发生记录', style: TextStyle(fontWeight: FontWeight.w600)),
          ...occurrenceTiles(context, s, planId: widget.id),
        ],
      ),
    );
  }
}

List<Widget> occurrenceTiles(
  BuildContext context,
  LedgerStore s, {
  String? planId,
}) {
  final rows =
      localItems(s.active, 'recurring_occurrences')
          .where(
            (o) => planId == null
                ? o['status'] == 'pending'
                : o['plan_id'] == planId,
          )
          .toList()
        ..sort((a, b) => (b['period'] as int).compareTo(a['period']));
  if (rows.isEmpty) {
    return [
      const Padding(
        padding: EdgeInsets.all(20),
        child: Text('到提前生成日后，打开应用时生成待确认项。'),
      ),
    ];
  }
  return [
    for (final o in rows)
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${o['name']} · 第 ${o['period']} 期'),
        subtitle: Text(
          '${o['due']} · ${{'pending': '待确认', 'confirmed': '已记账', 'skipped': '已跳过', 'cancelled': '已取消'}[o['status']]}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          AppPageRoute(builder: (_) => RecurringConfirmation(s, o['id'])),
        ),
      ),
  ];
}

class RecurringHistory extends StatelessWidget {
  final LedgerStore s;
  const RecurringHistory(this.s, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('待确认周期账单')),
    body: AnimatedBuilder(
      animation: s,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: occurrenceTiles(context, s),
      ),
    ),
  );
}

class RecurringConfirmation extends StatefulWidget {
  final LedgerStore s;
  final String id;
  const RecurringConfirmation(this.s, this.id, {super.key});
  @override
  State<RecurringConfirmation> createState() => _RecurringConfirmationState();
}

class _RecurringConfirmationState extends State<RecurringConfirmation> {
  LedgerStore get s => widget.s;
  Json get o => localItems(
    s.active,
    'recurring_occurrences',
  ).firstWhere((o) => o['id'] == widget.id);
  late TextEditingController amount, extra, account, rate, actual, extraActual;
  late String date, bookId;
  bool future = false, updatePending = false, saving = false;
  String? existingId, existingExtraId;
  @override
  void initState() {
    super.initState();
    bookId = s.active['id'];
    final c = o['fields']['original_currency'];
    amount = TextEditingController(
      text: formatAmount(o['fields']['original_amount_minor'], c),
    );
    extra = TextEditingController(
      text: o['extra'] == null ? '' : formatAmount(o['extra']['amount'], c),
    );
    account = TextEditingController(text: o['fields']['account']);
    rate = TextEditingController();
    actual = TextEditingController();
    extraActual = TextEditingController();
    date = today();
  }

  @override
  void dispose() {
    for (final c in [amount, extra, account, rate, actual, extraActual]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> link(bool isExtra) async {
    final field = o['fields'];
    final rows =
        s
            .records(s.active)
            .where(
              (e) =>
                  !isRefund(e['data']) &&
                  e['data']['type'] == field['type'] &&
                  e['data']['original_currency'] ==
                      field['original_currency'] &&
                  !s.hasRecurringLink(e['id']),
            )
            .toList()
          ..sort(
            (a, b) =>
                (b['data']['date'] as String).compareTo(a['data']['date']),
          );
    final selected = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .7,
          child: Column(
            children: [
              ListTile(
                title: Text(isExtra ? '选择已记附加项目' : '选择已记流水'),
                subtitle: const Text('同账本、同方向及币种，选择后带入实际金额和日期'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final e = rows[i], d = e['data'];
                    return ListTile(
                      title: Text(
                        '${formatAmount(d['original_amount_minor'], d['original_currency'])} · ${d['category']}',
                      ),
                      subtitle: Text(
                        '${d['date']} · ${d['account']} · ${d['note']}',
                      ),
                      onTap: () => Navigator.pop(c, e),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      final d = selected['data'];
      setState(() {
        if (isExtra) {
          existingExtraId = selected['id'];
          extra.text = formatAmount(
            d['original_amount_minor'],
            d['original_currency'],
          );
          extraActual.text = formatAmount(d['amount'], s.currency);
        } else {
          existingId = selected['id'];
          amount.text = formatAmount(
            d['original_amount_minor'],
            d['original_currency'],
          );
          actual.text = formatAmount(d['amount'], s.currency);
        }
        date = d['date'];
        account.text = d['account'];
      });
    }
  }

  Future<void> confirm() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      if (s.active['id'] != bookId) throw const FormatException('账本已切换，请重新打开');
      final f = {
        ...o['fields'] as Json,
        'original_amount_minor': parseAmount(
          amount.text,
          o['fields']['original_currency'],
        ),
        'account': account.text.trim(),
      };
      final p = await s.schedulePricing(
        f,
        date,
        manualRate: rate.text.trim().isEmpty ? null : rate.text.trim(),
        actual: actual.text.trim().isEmpty
            ? null
            : parseAmount(actual.text, s.currency),
      );
      Json? x;
      if (o['extra'] != null) {
        x = await s.schedulePricing(
          {
            ...f,
            'original_amount_minor': parseAmount(
              extra.text,
              f['original_currency'],
            ),
            'category_id': o['extra']['category_id'],
            'note': o['extra']['name'],
          },
          date,
          manualRate: rate.text.trim().isEmpty ? null : rate.text.trim(),
          actual: extraActual.text.trim().isEmpty
              ? null
              : parseAmount(extraActual.text, s.currency),
        );
      }
      if (!mounted) return;
      if (!await approve(
        context,
        '确认本期记账',
        '${existingId == null ? '新增' : '关联已有'} ${s.currency} ${s.display(p['amount'])}${x == null ? '' : '\n${existingExtraId == null ? '新增' : '关联已有'} ${o['extra']['name']} ${s.currency} ${s.display(x['amount'])}'}\n实际日期 $date${p['original_currency'] != s.currency ? '\n汇率 ${p['fx_rate']} · ${p['fx_rate_date']}（保存后锁定）' : ''}${future ? '\n更新以后每期默认金额${updatePending ? '，包括后续待确认项' : ''}' : ''}',
      )) {
        return;
      }
      await s.confirmRecurring(
        widget.id,
        p,
        extra: x,
        existingId: existingId,
        existingExtraId: existingExtraId,
        updateFuture: future,
        updatePending: updatePending,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = o;
    final f = row['fields'];
    final foreign = f['original_currency'] != s.currency;
    if (row['status'] != 'pending') {
      return Scaffold(
        appBar: AppBar(title: Text(row['name'])),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '第 ${row['period']} 期 · ${{'confirmed': '已记账', 'skipped': '已跳过', 'cancelled': '已取消'}[row['status']]}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            for (final id in row['entry_ids'])
              Builder(
                builder: (_) {
                  final e = ledgerIndex(s.active).byId[id];
                  if (e == null || e['deleted'] == true) {
                    return const ListTile(
                      title: Text('关联流水已移入回收站或删除'),
                      subtitle: Text('本期保留已处理状态，避免重复入账；恢复流水后关联仍保留。'),
                    );
                  }
                  final d = e['data'];
                  final refund = ledgerIndex(s.active).refunds[id] ?? 0;
                  return ListTile(
                    title: Text(
                      '${d['category']} · ${d['original_currency']} ${formatAmount(d['original_amount_minor'], d['original_currency'])}',
                    ),
                    subtitle: Text(
                      '${d['date']} · ${d['account']}${refund > 0 ? '\n已退 ${s.display(refund)} ${s.currency}${refund < d['amount'] ? '（部分退回）' : '（全部退回）'}' : ''}',
                    ),
                  );
                },
              ),
            hint('已确认记录保留实际收付快照；金额调整和退款可在流水中操作。'),
          ],
        ),
      );
    }
    final later = localItems(s.active, 'recurring_occurrences')
        .where(
          (x) =>
              x['plan_id'] == row['plan_id'] &&
              x['status'] == 'pending' &&
              x['period'] > row['period'],
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('本期账单')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${row['name']} · 第 ${row['period']} 期',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('${row['due']} 应${f['type'] == 'income' ? '收' : '付'}'),
            if (row['coverage_start'] != null)
              Text('租期 ${row['coverage_start']} 至 ${row['coverage_end']}'),
            if (row['partial'] == true) hint('末期不足完整周期，请按合同核对本期实际金额。'),
            const SizedBox(height: 20),
            TextField(
              controller: amount,
              style: TextStyle(
                fontSize: 30,
                color: expenseInk(context),
                fontWeight: FontWeight.w600,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    '本期实际${f['type'] == 'income' ? '收' : '付'}款 · ${f['original_currency']}',
              ),
            ),
            TextButton(
              onPressed: () => link(false),
              child: Text(existingId == null ? '选择已记流水' : '已关联流水 · 重新选择'),
            ),
            if (existingId != null)
              TextButton(
                onPressed: () => setState(() => existingId = null),
                child: const Text('取消关联，改为新增'),
              ),
            if (row['extra'] != null) ...[
              TextField(
                controller: extra,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      '${row['extra']['name']} · ${f['original_currency']}',
                ),
              ),
              TextButton(
                onPressed: () => link(true),
                child: Text(
                  existingExtraId == null ? '选择已记附加项目' : '已关联附加项目 · 重新选择',
                ),
              ),
              if (existingExtraId != null)
                TextButton(
                  onPressed: () => setState(() => existingExtraId = null),
                  child: const Text('取消附加项目关联'),
                ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('实际收付日'),
              subtitle: Text(date),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: calendarDate(date),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(9999, 12, 31),
                );
                if (d != null) setState(() => date = dateKey(d));
              },
            ),
            TextField(
              controller: account,
              maxLength: 50,
              decoration: const InputDecoration(labelText: '账户'),
            ),
            if (foreign) ...[
              hint('默认使用本机可用汇率。可填手动汇率或实际本币金额，实际金额优先。'),
              TextField(
                controller: rate,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      '手动汇率 · 1 ${f['original_currency']} = ? ${s.currency}',
                ),
              ),
              TextField(
                controller: actual,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '本期实际折合 ${s.currency}（可选）',
                ),
              ),
              if (row['extra'] != null)
                TextField(
                  controller: extraActual,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '附加项目实际折合 ${s.currency}（可选）',
                  ),
                ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('同时更新以后每期的默认金额'),
              subtitle: const Text('默认只改本期，已确认流水保持原金额'),
              value: future,
              onChanged: (v) => setState(() => future = v!),
            ),
            if (future && later.isNotEmpty)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('同时更新后续 ${later.length} 个待确认项'),
                subtitle: Text(
                  later.take(8).map((x) => '第 ${x['period']} 期').join('、'),
                ),
                value: updatePending,
                onChanged: (v) => setState(() => updatePending = v!),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('稍后处理'),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!await approve(
                            context,
                            '跳过本期？',
                            '本期不入账，仍占用期号，不延长总期数。',
                          )) {
                            return;
                          }
                          try {
                            await s.skipRecurring(widget.id);
                            if (mounted) setState(() {});
                          } catch (e) {
                            if (context.mounted) message(context, e);
                          }
                        },
                  child: const Text('跳过本期'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving ? null : confirm,
              child: Text(
                saving ? '保存中…' : '确认已${f['type'] == 'income' ? '收' : '付'}并记账',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
