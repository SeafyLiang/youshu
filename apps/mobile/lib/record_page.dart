import 'display_dates.dart';

import 'dart:async';

import 'package:lpinyin/lpinyin.dart';

import 'amount_expression.dart';
import 'icon_catalog.dart';
import 'haptics.dart';
import 'dictionary_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'store.dart';
import 'ui.dart';

class RecordPage extends StatefulWidget {
  final LedgerStore store;
  final String category;
  final Json? existing;
  final Json? initialFields;
  final String? initialDate;
  final bool copy;
  const RecordPage(
    this.store, {
    super.key,
    required this.category,
    this.existing,
    this.initialFields,
    this.initialDate,
    this.copy = false,
  });
  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  LedgerStore get s => widget.store;
  late String category, type, account, toAccount, date, currency, toCurrency;
  late TextEditingController amount, note, rate, actual, toAmount;
  Set<String> tags = {};
  Json? quote;
  bool saving = false, loading = false;
  String mode = 'manual', rateMessage = '', time = '';
  bool keypad = true, nativeKeyboard = false;
  final amountFocus = FocusNode();
  double get keyHeight {
    final preferred = (s.state['keypadLayout']?['height'] as num? ?? 50)
        .toDouble()
        .clamp(48.0, 68.0);
    final available =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewPaddingOf(context).vertical;
    return preferred.clamp(44.0, ((available - 150) / 4).clamp(44.0, 68.0));
  }

  Future<void> toggleKeyboard() async {
    setState(() {
      nativeKeyboard = !nativeKeyboard;
      keypad = true;
    });
    amountFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (nativeKeyboard) {
        amountFocus.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      } else {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
    });
  }

  Future<void> editKeyboard() async {
    final before = Map<String, dynamic>.from(
      s.state['keypadLayout'] ?? {'width': 1.0, 'height': 50.0, 'align': 0.0},
    );
    var layout = Map<String, dynamic>.from(before);
    final saved = await glassSheet<bool>(
      context,
      StatefulBuilder(
        builder: (c, set) => Column(
          children: [
            const Text(
              '键盘布局',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const Text('高度'),
            Slider(
              min: 48,
              max: 68,
              value: (layout['height'] as num).toDouble(),
              onChanged: (v) {
                set(() => layout['height'] = v);
                setState(() => s.state['keypadLayout'] = layout);
              },
            ),
            const Text('宽度'),
            Slider(
              min: .8,
              max: 1,
              value: (layout['width'] as num).toDouble(),
              onChanged: (v) {
                set(() => layout['width'] = v);
                setState(() => s.state['keypadLayout'] = layout);
              },
            ),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: -1, label: Text('靠左')),
                ButtonSegment(value: 0, label: Text('居中')),
                ButtonSegment(value: 1, label: Text('靠右')),
              ],
              selected: {(layout['align'] as num).toDouble()},
              onSelectionChanged: (v) {
                set(() => layout['align'] = v.first);
                setState(() => s.state['keypadLayout'] = layout);
              },
            ),
            const Spacer(),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    set(
                      () =>
                          layout = {'width': 1.0, 'height': 50.0, 'align': 0.0},
                    );
                    setState(() => s.state['keypadLayout'] = layout);
                  },
                  child: const Text('恢复默认'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
      height: .52,
    );
    if (saved == true) {
      await s.persist(preferencesOnly: true);
    } else {
      s.state['keypadLayout'] = before;
    }
    if (mounted) setState(() {});
  }

  bool validAmount(String text) => validAmountExpression(text, currency);

  Json get fields => Map<String, dynamic>.from(
    s.state['recordFields'] ??
        {'note': 'optional', 'account': 'hidden', 'tags': 'optional'},
  );
  bool visible(String key) => fields[key] != 'hidden';
  @override
  void initState() {
    super.initState();
    keyFeedback(s, prepare: true);
    final d = widget.existing?['data'] ?? widget.initialFields;
    type = d?['type'] ?? 'expense';
    category = d?['category_id'] ?? s.categoryKey(widget.category);
    account = d?['account'] ?? (visible('account') ? '微信' : '未指定');
    time = d?['time'] ?? DateTime.now().toIso8601String().substring(11, 16);
    toAccount = d?['to_account'] == '' ? '银行卡' : d?['to_account'] ?? '银行卡';
    date = d?['date'] ?? widget.initialDate ?? today();
    currency = d?['original_currency'] ?? s.currency;
    toCurrency = d?['to_currency'] ?? s.currency;
    amount = TextEditingController(
      text: d == null || (d['original_amount_minor'] ?? d['amount']) == null
          ? ''
          : formatAmount(d['original_amount_minor'] ?? d['amount'], currency),
    );
    note = TextEditingController(text: d?['note'] ?? '');
    rate = TextEditingController(text: d?['fx_rate'] ?? '');
    actual = TextEditingController(
      text: d?['fx_mode'] == 'actual' ? s.display(d['amount']) : '',
    );
    toAmount = TextEditingController(
      text: type == 'transfer'
          ? formatAmount(d['to_amount_minor'], toCurrency)
          : '',
    );
    tags = (d?['tag_ids'] as List? ?? []).cast<String>().toSet();
    if (widget.existing != null) {
      mode = d['fx_mode'] == 'actual'
          ? 'actual'
          : d['fx_mode'] == 'manual'
          ? 'manual'
          : 'auto';
      quote = {
        'rate': d['fx_rate'],
        'date': d['fx_rate_date'],
        'source': d['fx_source'],
        'cached': d['fx_mode'] == 'cached',
      };
    }
    if (widget.initialFields != null) {
      mode = 'auto';
      amount.selection = TextSelection(
        baseOffset: 0,
        extentOffset: amount.text.length,
      );
    }
    ensureCategory();
  }

  void ensureCategory() {
    if (type == 'transfer') return;
    final list = s.choices(
      'category',
      type: type,
      archived: widget.existing != null,
    );
    if (!list.any((e) => e['id'] == category)) {
      category = list.isEmpty ? '' : list.first['id'];
    }
  }

  @override
  void dispose() {
    amountFocus.dispose();
    for (final c in [amount, note, rate, actual, toAmount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> fetchRate({bool refresh = false}) async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final requested = '$currency/${s.currency}/$date';
      if (refresh) {
        try {
          await s.updateRates(force: true);
        } catch (_) {}
      } else {
        unawaited(s.updateRates().catchError((Object _) {}));
      }
      final q = await s.exchange(currency, s.currency, date);
      if (requested != '$currency/${s.currency}/$date') return;
      if (mounted) {
        setState(() {
          quote = q;
          rate.text = q['rate'];
          rateMessage =
              '${s.rateError.isEmpty ? '' : '${s.rateError} · '}${q['source']} · ${q['date']}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              rateMessage = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool get pricingChanged {
    final d = widget.existing?['data'];
    if (d == null) return true;
    return currency != d['original_currency'] ||
        date != d['date'] ||
        amount.text != formatAmount(d['original_amount_minor'], currency) ||
        mode !=
            (d['fx_mode'] == 'actual'
                ? 'actual'
                : d['fx_mode'] == 'manual'
                ? 'manual'
                : 'auto') ||
        (mode == 'manual' && rate.text != d['fx_rate']) ||
        (mode == 'actual' && actual.text != s.display(d['amount']));
  }

  Future<void> save({bool deleted = false}) async {
    if (saving) return;
    FocusScope.of(context).unfocus();
    setState(() => saving = true);
    try {
      final old = widget.existing?['data'] as Json?;
      if (deleted && old != null) {
        if (s.hasRecurringLink(widget.existing!['id']) &&
            !await approve(
              context,
              '删除周期关联流水？',
              '本期保留已处理状态以避免重复入账；恢复流水后关联仍保留。',
            )) {
          return;
        }
        await s.trashEntry(widget.existing!);
        notifyApp('已移入回收站');
        if (mounted) Navigator.pop(context);
        return;
      }
      final n = evaluateAmount(amount.text, currency);
      if (n <= 0 || n > 999999999999) {
        throw const FormatException('计算结果须大于0，且不超过金额上限');
      }
      if (fields['note'] == 'required' && note.text.trim().isEmpty) {
        throw const FormatException('请填写备注');
      }
      if (fields['account'] == 'required' && account == '未指定') {
        throw const FormatException('请选择账户');
      }
      if (fields['tags'] == 'required' && tags.isEmpty) {
        throw const FormatException('请添加标签');
      }
      if (date.compareTo(today()) > 0 &&
          mounted &&
          !await approve(context, '记录未来日期？', '将记入 $date，请确认日期。')) {
        return;
      }
      if (type != 'transfer' && category.isEmpty) {
        throw const FormatException('请先创建一个可用分类');
      }
      Json pricing;
      if (old != null && !pricingChanged) {
        pricing = {
          for (final k in [
            'amount',
            'original_currency',
            'original_amount_minor',
            'currency_scale',
            'base_currency',
            'base_amount_minor',
            'fx_rate',
            'fx_rate_date',
            'fx_source',
            'fx_mode',
          ])
            k: old[k],
        };
      } else {
        var r = '1', source = 'identity', effective = date, fxMode = 'identity';
        int converted = n;
        if (currency != s.currency) {
          if (mode == 'auto') {
            if (quote == null) await fetchRate();
            if (quote == null) throw const FormatException('请获取汇率，或改用手动方式');
            r = quote!['rate'];
            effective = quote!['date'];
            source = quote!['source'];
            fxMode = quote!['cached'] == true ? 'cached' : 'auto';
          } else {
            r = mode == 'actual' ? '1' : rate.text.trim();
            source = 'user';
            fxMode = mode;
          }
          converted = mode == 'actual'
              ? parseAmount(actual.text, s.currency)
              : convertAmount(n, currency, s.currency, r);
          if (!mounted) return;
          final stale =
              DateTime.parse(date)
                  .difference(DateTime.parse(effective))
                  .inDays >
              7;
          if (!await approve(
            context,
            '确认折合金额',
            '${formatAmount(n, currency)} $currency → ${s.display(converted)} ${s.currency}\n${mode == 'actual' ? '使用实际扣款金额' : '汇率 $r · $effective'}${fxMode == 'cached' ? '\n正在使用离线缓存估算' : ''}${stale && mode == 'auto' ? '\n报价距记账日超过 7 天' : ''}\n保存后锁定，不会自动重算。',
          )) {
            return;
          }
        }
        pricing = {
          'amount': converted,
          'original_currency': currency,
          'original_amount_minor': n,
          'currency_scale': currencies[currency],
          'base_currency': s.currency,
          'base_amount_minor': converted,
          'fx_rate': r,
          'fx_rate_date': effective,
          'fx_source': source,
          'fx_mode': fxMode,
        };
      }
      if (type == 'transfer' && account == toAccount) {
        throw const FormatException('转入与转出账户不能相同');
      }
      final categoryData = s
          .choices('category', archived: true)
          .where((e) => e['id'] == category);
      await s.saveEntry({
        ...pricing,
        'type': type,
        'date': date,
        'time': time,
        'refund_of': widget.copy ? '' : old?['refund_of'] ?? '',
        'category': type == 'transfer'
            ? '转账'
            : categoryData.first['data']['name'],
        'category_id': type == 'transfer' ? '' : category,
        'tag_ids': tags.toList(),
        'account': account,
        'to_account': type == 'transfer' ? toAccount : '',
        'to_currency': toCurrency,
        'to_amount_minor': type == 'transfer'
            ? parseAmount(toAmount.text, toCurrency)
            : 0,
        'note': note.text.trim(),
        for (final k in ['member', 'merchant', 'project'])
          if ((old ?? widget.initialFields)?[k] != null)
            k: (old ?? widget.initialFields)![k],
      }, existing: widget.copy ? null : widget.existing);
      successFeedback(s);
      notifyApp('已保存');
      if (mounted) Navigator.pop(context, 'saved');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget currencyPicker(
    String value,
    ValueChanged<String> change, {
    String title = '记账币种',
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$title$value'),
    initialValue: value,
    decoration: InputDecoration(
      labelText: title,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    items: currencies.keys
        .map(
          (c) => DropdownMenuItem(
            value: c,
            child: Text(c == 'CNY' ? 'CNY · 人民币' : c),
          ),
        )
        .toList(),
    onChanged: (v) => change(v!),
  );
  String preview() {
    try {
      final n = evaluateAmount(amount.text, currency);
      final converted = mode == 'actual'
          ? parseAmount(actual.text, s.currency)
          : convertAmount(n, currency, s.currency, rate.text);
      return '折合 ${s.currency} ${s.display(converted)}';
    } catch (_) {
      return '输入金额后显示折合金额';
    }
  }

  Future<void> configureFields() async {
    final draft = fields;
    final result = await glassSheet<Json>(
      context,
      StatefulBuilder(
        builder: (c, update) => Scaffold(
          appBar: AppBar(
            title: const Text('记账字段'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, draft),
                child: const Text('保存'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              hint('金额与分类必填'),
              const SizedBox(height: 20),
              for (final field in {
                'note': '备注',
                'account': '账户',
                'tags': '标签',
              }.entries)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: hairline(c), width: .5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          field.value,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Theme.of(c).colorScheme.primaryContainer
                              .withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final option in {
                              'hidden': '隐藏',
                              'optional': '选填',
                              'required': '必填',
                            }.entries)
                              InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () =>
                                    update(() => draft[field.key] = option.key),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (draft[field.key] ?? 'optional') ==
                                            option.key
                                        ? softSurface(c)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    option.value,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          (draft[field.key] ?? 'optional') ==
                                              option.key
                                          ? expenseInk(c)
                                          : secondaryInk(c),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              hint('常用项放在手边，其他项按需展开。'),
            ],
          ),
        ),
      ),
      height: .65,
    );
    if (result != null) {
      s.state['recordFields'] = result;
      await s.persist();
      if (mounted) setState(() {});
    }
  }

  Future<void> chooseTime() async {
    var value = DateTime.parse('$date ${time.isEmpty ? '12:00' : time}:00');
    final selected = await glassSheet<DateTime>(
      context,
      Scaffold(
        appBar: AppBar(
          title: const Text('选择时间'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, value),
              child: const Text('确定'),
            ),
          ],
        ),
        body: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          use24hFormat: true,
          initialDateTime: value,
          onDateTimeChanged: (v) => value = v,
        ),
      ),
      height: .45,
    );
    if (selected != null) {
      setState(() => time = selected.toIso8601String().substring(11, 16));
    }
  }

  Future<void> chooseCategory() async {
    var list = s.choices('category', type: type);
    String parent = 'recent', query = '';
    final history =
        s.records(s.active).where((e) => e['data']['type'] == type).toList()
          ..sort(
            (a, b) => ('${b['data']['date']} ${b['data']['time'] ?? ''}')
                .compareTo('${a['data']['date']} ${a['data']['time'] ?? ''}'),
          );
    final recentIds = history
        .map((e) => e['data']['category_id'])
        .toSet()
        .toList();
    bool matches(Json e) {
      final name = e['data']['name'] as String;
      final q = query.toLowerCase().replaceAll(' ', '');
      return name.toLowerCase().contains(q) ||
          PinyinHelper.getPinyinE(
            name,
            separator: '',
            format: PinyinFormat.WITHOUT_TONE,
          ).toLowerCase().contains(q) ||
          PinyinHelper.getShortPinyin(name).toLowerCase().contains(q);
    }

    void sortRecent() => list.sort((a, b) {
      final ai = recentIds.indexOf(a['id']), bi = recentIds.indexOf(b['id']);
      return (ai < 0 ? 999999 : ai).compareTo(bi < 0 ? 999999 : bi);
    });
    sortRecent();
    final recent = s
        .records(s.active)
        .where((e) => e['data']['type'] == type)
        .map((e) => e['data']['category_id'])
        .toSet();
    final suggested = <String>{
      '三餐',
      '水果零食',
      '买菜食材',
      '咖啡饮品',
      '公交地铁',
      '生活用品',
      '工资收入',
      '奖金津贴',
      '兼职收入',
      '报销到账',
      '礼金红包',
      '闲置出售',
    };
    final value = await glassSheet<String>(
      context,
      StatefulBuilder(
        builder: (c, update) => Scaffold(
          appBar: AppBar(
            title: const Text('选择分类'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(58),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索分类、拼音或首字母',
                  ),
                  onChanged: (v) => update(() => query = v.trim()),
                ),
              ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                tooltip: '管理分类',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await Navigator.of(c).push(
                    AppPageRoute(
                      builder: (_) => DictionaryPage(s, initialType: type),
                    ),
                  );
                  if (!c.mounted) return;
                  update(() {
                    list = s.choices('category', type: type);
                    sortRecent();
                    if (!list.any((e) => e['id'] == parent)) parent = 'recent';
                  });
                  if (mounted) setState(ensureCategory);
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('收起'),
              ),
            ],
          ),
          body: query.isNotEmpty && !list.any(matches)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('没有找到“$query”'),
                      const SizedBox(height: 12),
                      if (s.active['role'] == 'owner')
                        FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text('创建“$query”'),
                          onPressed: () async {
                            if (query.length > 50) {
                              message(c, '分类名称不能超过50字');
                              return;
                            }
                            try {
                              final id = uuid.v4();
                              await s.saveEntry(
                                {
                                  'name': query,
                                  'type': type,
                                  'parent_id': '',
                                  'icon': 'category',
                                  'color': '#20836A',
                                  'order': list.length,
                                  'archived': false,
                                },
                                kind: 'category',
                                id: id,
                              );
                              if (c.mounted) Navigator.pop(c, id);
                            } catch (e) {
                              if (c.mounted) message(c, e);
                            }
                          },
                        ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: ListView(
                        children: [
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            title: const Text(
                              '最近使用',
                              style: TextStyle(fontSize: 11),
                            ),
                            selected: parent == 'recent',
                            onTap: () => update(() => parent = 'recent'),
                          ),
                          for (final e in list.where(
                            (e) => e['data']['parent_id'] == '',
                          ))
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              title: Text(
                                e['data']['name'],
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: parent == e['id'],
                              onTap: () => update(() => parent = e['id']),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 3,
                        childAspectRatio: .95,
                        padding: const EdgeInsets.all(8),
                        children: [
                          for (final e in list.where(
                            (e) => query.isNotEmpty
                                ? matches(e)
                                : parent == 'recent'
                                ? (recent.isEmpty
                                      ? suggested.contains(e['data']['name']) ||
                                            !list.any(
                                              (c) =>
                                                  c['data']['parent_id'] != '',
                                            )
                                      : recent.contains(e['id']))
                                : (e['id'] == parent ||
                                      e['data']['parent_id'] == parent),
                          ))
                            InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.pop(c, e['id']),
                              child: Container(
                                margin: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: category == e['id']
                                      ? Theme.of(c).colorScheme.primaryContainer
                                      : null,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CategoryBadge(
                                      icon: visualIcon(s.active, e),
                                      color: e['data']['color'],
                                      name: e['data']['name'],
                                      size: 35,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      e['data']['name'],
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
      height: .59,
    );
    if (value != null) setState(() => category = value);
  }

  Future<void> chooseTags() async {
    final draft = {...tags};
    final name = TextEditingController();
    final result = await glassSheet<Set<String>>(
      context,
      StatefulBuilder(
        builder: (c, update) => Scaffold(
          appBar: AppBar(
            title: const Text('添加标签'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, draft),
                child: const Text('完成'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final t in s.choices('tag'))
                    FilterChip(
                      label: Text(t['data']['name']),
                      selected: draft.contains(t['id']),
                      onSelected: (v) => update(
                        () => v ? draft.add(t['id']) : draft.remove(t['id']),
                      ),
                    ),
                ],
              ),
              if (s.active['role'] == 'owner')
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: name,
                        maxLength: 50,
                        decoration: const InputDecoration(labelText: '新标签名称'),
                      ),
                    ),
                    IconButton(
                      tooltip: '创建标签',
                      onPressed: () async {
                        if (name.text.trim().isEmpty) return;
                        try {
                          final id = uuid.v4();
                          await s.saveEntry(
                            {
                              'name': name.text.trim(),
                              'color': '#126C62',
                              'order': s.choices('tag', archived: true).length,
                              'archived': false,
                            },
                            kind: 'tag',
                            id: id,
                          );
                          draft.add(id);
                          name.clear();
                          update(() {});
                        } catch (e) {
                          if (c.mounted) message(c, e);
                        }
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      height: .6,
    );
    if (result != null) setState(() => tags = result);
  }

  void keyPress(String key) {
    keyFeedback(s);
    if (key == '保存') {
      save();
      return;
    }
    setState(() {
      var start = amount.selection.isValid
          ? amount.selection.start
          : amount.text.length;
      final end = amount.selection.isValid
          ? amount.selection.end
          : amount.text.length;
      var insert = key;
      if (key == '清空') {
        amount.clear();
        return;
      }
      if (key == '⌫') {
        insert = '';
        if (start == end && start > 0) start--;
      }
      final next = amount.text.replaceRange(start, end, insert);
      if (validAmount(next)) {
        amount.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: start + insert.length),
        );
      }
    });
  }

  Widget keyboard(Color accent) {
    final p = AppPalette.of(context);
    final saveGrad = type == 'income' ? p.incomeGradient : p.saveGradient;
    final saveFg = type == 'income' ? Colors.white : p.saveInk;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        child: GlassPanel(
          color: p.keypadBg,
          radius: 24,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, right: 4, bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.square_grid_2x2,
                      size: 12,
                      color: p.ink3,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        s
                                .choices('category', archived: true)
                                .where((e) => e['id'] == category)
                                .firstOrNull?['data']['name'] ??
                            '快捷金额',
                        style: TextStyle(fontSize: 10.5, color: p.ink3),
                      ),
                    ),
                    IconButton(
                      tooltip: '使用手机键盘',
                      visualDensity: VisualDensity.compact,
                      onPressed: toggleKeyboard,
                      icon: Icon(
                        Icons.keyboard_outlined,
                        size: 19,
                        color: p.ink2,
                      ),
                    ),
                    IconButton(
                      tooltip: '编辑键盘布局',
                      visualDensity: VisualDensity.compact,
                      onPressed: editKeyboard,
                      icon: Icon(Icons.tune_rounded, size: 19, color: p.ink2),
                    ),
                    SizedBox(
                      width: 28,
                      height: 26,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: '收起键盘',
                        onPressed: () => setState(() => keypad = false),
                        icon: Icon(
                          CupertinoIcons.chevron_down,
                          size: 13,
                          color: p.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        for (final row in [
                          ['1', '2', '3'],
                          ['4', '5', '6'],
                          ['7', '8', '9'],
                          ['.', '0', '-'],
                        ])
                          Row(
                            children: [
                              for (final key in row)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(2.5),
                                    child: keyButton(key, accent),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(2.5),
                          child: keyButton('⌫', accent),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(2.5),
                          child: keyButton('+', accent),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(2.5),
                          child: InkWell(
                            onTap: saving ? null : () => save(),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              height: keyHeight * 2 + 5,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: saveGrad,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.25),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (p.style.isCute)
                                    ThemeMotifIcon(
                                      style: p.style,
                                      size: 19,
                                      color: saveFg,
                                    )
                                  else
                                    Icon(
                                      CupertinoIcons.check_mark,
                                      size: 21,
                                      color: saveFg,
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '保存',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: saveFg,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget keyButton(String key, Color accent) {
    final p = AppPalette.of(context);
    final fn = key == '⌫' || key == '清空' || key == '+' || key == '-';
    return InkWell(
      onTap: saving ? null : () => keyPress(key),
      onLongPress: key == '⌫' && !saving ? () => keyPress('清空') : null,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: keyHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fn ? p.keyFn : p.keyBg,
          borderRadius: BorderRadius.circular(13),
          border: fn ? null : Border.all(color: p.border, width: 0.7),
        ),
        child: key == '⌫'
            ? Icon(CupertinoIcons.delete_left, size: 19, color: p.ink2)
            : Text(
                key,
                style: TextStyle(
                  fontSize: key == '清空' ? 11.5 : 22,
                  fontWeight: FontWeight.w500,
                  fontFeatures: tabularFigures,
                  color: fn ? p.ink2 : p.ink,
                ),
              ),
      ),
    );
  }

  Future<void> chooseCurrency() async {
    final picked = await glassSheet<String>(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('选择币种')),
        body: ListView(
          children: [
            for (final c in currencies.keys)
              ListTile(
                title: Text(c == 'CNY' ? '人民币 · CNY' : c),
                trailing: c == currency
                    ? Icon(
                        CupertinoIcons.check_mark,
                        color: expenseInk(context),
                      )
                    : null,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
      height: 0.65,
    );
    if (picked != null) {
      setState(() {
        currency = picked;
        quote = null;
        rate.clear();
        actual.clear();
      });
      if (currency != s.currency) fetchRate();
    }
  }

  Future<void> chooseDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(date),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        date = dateKey(d);
        quote = null;
      });
      if (currency != s.currency && mode == 'auto') fetchRate();
    }
  }

  Widget fieldLine(
    IconData icon,
    String title,
    Widget content, {
    Key? key,
    VoidCallback? onTap,
    Widget? trailing,
  }) => InkWell(
    key: key,
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 53),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: hairline(context).withValues(alpha: 0.65),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: secondaryInk(context)),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: secondaryInk(context)),
          ),
          const SizedBox(width: 12),
          Expanded(child: content),
          ?trailing,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = s
        .choices('category', type: type, archived: true)
        .where((e) => e['id'] == category)
        .firstOrNull;
    final accent = type == 'income' ? incomeInk(context) : expenseInk(context);
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: accent,
          primaryContainer: accent.withValues(alpha: 0.14),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          leading: CircleAction(
            icon: CupertinoIcons.xmark,
            onTap: () => Navigator.pop(context),
            tooltip: '返回',
          ),
          title: Text(
            widget.copy
                ? '复制记账'
                : widget.existing == null
                ? '记一笔'
                : '编辑账目',
          ),
          actions: [
            if (widget.existing != null && !widget.copy)
              CircleAction(
                icon: CupertinoIcons.trash,
                onTap: () async {
                  if (await approve(context, '删除这笔账目？', '将移入回收站，可在 30 天内恢复。')) {
                    save(deleted: true);
                  }
                },
                tooltip: '删除账目',
              ),
            CircleAction(
              icon: CupertinoIcons.check_mark,
              onTap: saving ? null : () => save(),
              tooltip: '保存账目',
              color: accent,
            ),
            const SizedBox(width: 14),
          ],
        ),
        bottomNavigationBar:
            keypad &&
                !nativeKeyboard &&
                MediaQuery.viewInsetsOf(context).bottom == 0
            ? Align(
                heightFactor: 1,
                alignment: Alignment(
                  (s.state['keypadLayout']?['align'] as num? ?? 0).toDouble(),
                  0,
                ),
                child: SizedBox(
                  width:
                      (MediaQuery.sizeOf(context).width *
                              (s.state['keypadLayout']?['width'] as num? ?? 1))
                          .clamp(
                            MediaQuery.sizeOf(context).width < 280
                                ? MediaQuery.sizeOf(context).width
                                : 280,
                            MediaQuery.sizeOf(context).width,
                          ),
                  child: keyboard(accent),
                ),
              )
            : nativeKeyboard
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: toggleKeyboard,
                        child: const Text('自带键盘'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: saving ? null : () => save(),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: SafeArea(
          top: false,
          child: ListView(
            key: const Key('record-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppSegmentControl<String>(
                      expand: true,
                      value: type,
                      items: const [
                        ('expense', '支出'),
                        ('income', '收入'),
                        ('transfer', '转账'),
                      ],
                      itemPadding: const EdgeInsets.symmetric(vertical: 6.5),
                      onChanged: (v) => setState(() {
                        type = v;
                        category = '';
                        ensureCategory();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(44, 34),
                    ),
                    onPressed: configureFields,
                    icon: Icon(
                      CupertinoIcons.slider_horizontal_3,
                      size: 12,
                      color: secondaryInk(context),
                    ),
                    label: Text(
                      '自定义',
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryInk(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                key: const Key('record-type-swipe'),
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() < 120) return;
                  final types = ['expense', 'income', 'transfer'];
                  final next = (types.indexOf(type) + (v < 0 ? 1 : -1)).clamp(
                    0,
                    2,
                  );
                  setState(() {
                    type = types[next];
                    category = '';
                    ensureCategory();
                  });
                },
                child: GlassPanel(
                  radius: isAndroidPlatform ? 22 : 20,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: chooseCurrency,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppPalette.of(context).surface2,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppPalette.of(context).borderStrong,
                                  width: 0.7,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currency == 'CNY'
                                        ? '人民币 · CNY'
                                        : currency,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: secondaryInk(context),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    CupertinoIcons.chevron_down,
                                    size: 10,
                                    color: secondaryInk(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (AppPalette.of(context).style.isCute) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppPalette.of(context).brandSoft,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    type == 'income'
                                        ? AppPalette.of(
                                            context,
                                          ).style.recordHintInc
                                        : AppPalette.of(
                                            context,
                                          ).style.recordHintExp,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.of(context).brandDeep,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ThemeMascot(
                              style: AppPalette.of(context).style,
                              size: 30,
                              mood: type == 'income'
                                  ? MascotMood.happy
                                  : MascotMood.curious,
                            ),
                          ],
                        ],
                      ),
                      if (amount.text.contains('+') ||
                          amount.text.contains('-'))
                        Builder(
                          builder: (c) {
                            try {
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '= ${formatAmount(evaluateAmount(amount.text, currency), currency)}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              );
                            } catch (_) {
                              return const SizedBox(height: 24);
                            }
                          },
                        ),
                      const SizedBox(height: 6),
                      TextField(
                        key: const Key('record-amount'),
                        controller: amount,
                        focusNode: amountFocus,
                        onTap: () => setState(() => keypad = true),
                        showCursor: true,
                        keyboardType: nativeKeyboard
                            ? TextInputType.numberWithOptions(
                                decimal: currencies[currency] != 0,
                              )
                            : TextInputType.none,
                        inputFormatters: [
                          TextInputFormatter.withFunction(
                            (old, next) => validAmount(next.text) ? next : old,
                          ),
                        ],
                        onChanged: (_) => setState(() {}),
                        cursorColor: accent,
                        cursorHeight: 38,
                        style: TextStyle(
                          color: accent,
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.6,
                          fontFeatures: tabularFigures,
                          height: 1.15,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: currencies[currency] == 0 ? '0' : '0.00',
                          hintStyle: TextStyle(
                            color: accent.withValues(alpha: 0.45),
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.6,
                            fontFeatures: tabularFigures,
                          ),
                          prefixText: '${moneySymbol(currency)} ',
                          prefixStyle: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: accent,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: hairline(context)),
                      const SizedBox(height: 7),
                      Text(
                        '${s.active['name']} · 本币记账',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: mutedInk(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GlassPanel(
                radius: isAndroidPlatform ? 20 : 18,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    if (visible('note'))
                      fieldLine(
                        CupertinoIcons.bookmark,
                        fields['note'] == 'required' ? '备注 *' : '备注',
                        TextField(
                          key: const Key('record-note'),
                          controller: note,
                          maxLength: 500,
                          onTap: () => setState(() => keypad = false),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '写点备注，记住这笔生活',
                            counterText: '',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: mutedInk(context),
                            ),
                          ),
                        ),
                      ),
                    if (type != 'transfer')
                      fieldLine(
                        CupertinoIcons.square_grid_2x2,
                        '分类 *',
                        Row(
                          children: [
                            CategoryBadge(
                              icon: visualIcon(s.active, selected),
                              color: selected?['data']['color'],
                              name: selected?['data']['name'],
                              size: 26,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selected?['data']['name'] ?? '选择分类',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        key: const Key('record-category'),
                        onTap: chooseCategory,
                        trailing: Icon(
                          CupertinoIcons.chevron_right,
                          size: 13,
                          color: mutedInk(context),
                        ),
                      ),
                    fieldLine(
                      CupertinoIcons.clock,
                      '时间',
                      Tooltip(
                        message: '选择日期',
                        child: InkWell(
                          onTap: chooseDate,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  recordDateLabel(date),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                CupertinoIcons.calendar,
                                size: 13,
                                color: secondaryInk(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                      onTap: chooseTime,
                      trailing: Tooltip(
                        message: '选择时间',
                        child: InkWell(
                          onTap: chooseTime,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.11),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: tabularFigures,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  CupertinoIcons.chevron_down,
                                  size: 9,
                                  color: accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (visible('tags'))
                      fieldLine(
                        CupertinoIcons.tag,
                        '标签',
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            for (final t
                                in s
                                    .choices('tag', archived: true)
                                    .where((e) => tags.contains(e['id'])))
                              ActionChip(
                                label: Text(t['data']['name']),
                                onPressed: chooseTags,
                                visualDensity: VisualDensity.compact,
                              ),
                            ActionChip(
                              avatar: const Icon(CupertinoIcons.plus, size: 11),
                              label: Text(
                                fields['tags'] == 'required'
                                    ? '添加标签 *'
                                    : '添加标签',
                              ),
                              onPressed: chooseTags,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    if (type == 'transfer' || visible('account'))
                      fieldLine(
                        CupertinoIcons.creditcard,
                        type == 'transfer' ? '转出' : '账户',
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            isDense: true,
                            value: account,
                            items: {...accounts, account}
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      v,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => account = v!),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (currency != s.currency) ...[
                space,
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: '换算方式'),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('本机参考汇率')),
                    DropdownMenuItem(value: 'manual', child: Text('手动汇率')),
                    DropdownMenuItem(value: 'actual', child: Text('实际扣款金额')),
                  ],
                  onChanged: (v) => setState(() => mode = v!),
                ),
                space,
                if (mode == 'auto') ...[
                  TextButton.icon(
                    onPressed: loading ? null : () => fetchRate(refresh: true),
                    icon: const Icon(Icons.refresh),
                    label: Text(loading ? '正在获取' : '更新最新汇率'),
                  ),
                  hint(
                    rateMessage.isEmpty && quote != null
                        ? '${quote!['source']} · ${quote!['date']}'
                        : rateMessage,
                  ),
                  if (quote != null)
                    Text('1 $currency = ${rate.text} ${s.currency}'),
                ] else
                  TextField(
                    controller: mode == 'actual' ? actual : rate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: mode == 'actual'
                          ? '实际扣款（${s.currency}）'
                          : '1 $currency 对应 ${s.currency}',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                space,
                Text(
                  preview(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                hint('参考报价不等于银行成交价；可填写实际扣款。'),
              ],
              if (type == 'transfer') ...[
                DropdownButtonFormField<String>(
                  initialValue: toAccount,
                  decoration: const InputDecoration(labelText: '转入账户'),
                  items: {...accounts, toAccount}
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => toAccount = v!),
                ),
                space,
                currencyPicker(
                  toCurrency,
                  (v) => setState(() => toCurrency = v),
                  title: '转入币种',
                ),
                space,
                TextField(
                  controller: toAmount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '实际到账金额'),
                ),
                hint('两端都不计入收支；手续费请单独记为支出。'),
                space,
              ],

              if (!keypad) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: saving ? null : () => save(),
                  icon: const Icon(CupertinoIcons.check_mark, size: 17),
                  label: Text(saving ? '正在保存' : '保存账目'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
