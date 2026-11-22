import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import 'belongings_store.dart';
import 'domain.dart';
import 'recurring_domain.dart';
export 'recurring_domain.dart';
import 'display.dart';
export 'balance.dart';
import 'local_database.dart';
import 'category_templates.dart';
import 'bill_import.dart';
import 'ledger_scope.dart';
import 'merge_fx.dart';
import 'budget_domain.dart';
import 'dictionary_deletion.dart';
export 'dictionary_deletion.dart';
export 'budget_domain.dart';
export 'domain.dart';
part 'payment_store.dart';
part 'lifecycle_store.dart';
part 'dictionary_store.dart';
part 'data_store.dart';
part 'recurring_store.dart';

const uuid = Uuid();
const system = MethodChannel('com.seafy.yousu/system');
const categories = defaultCategories;
const accounts = ['微信', '支付宝', '银行卡', '现金'];
String money(num cents) => formatAmount(cents, 'CNY');
String today() => bookToday();
int parseMoney(String value, {bool zero = false}) =>
    parseAmount(value, 'CNY', zero: zero);
Json freshLedger(String name, {String currency = 'CNY', int day = 1}) {
  final l = migrateLedger({
    'id': uuid.v4(),
    'name': name,
    'shared': false,
    'role': 'owner',
    'entries': <dynamic>[],
    'pending': <dynamic>[],
    'lastSync': '',
  });
  final settings = settingsOf(l)
    ..['base_currency'] = currency
    ..['rules'] = [
      {'day': day, 'effective': '2000-01-01'},
    ];
  (l['entries'] as List).firstWhere(
    (e) => e['kind'] == 'ledger_settings',
  )['data'] = settings;
  (l['entries'] as List).addAll(recommendedCategories(l));
  return l;
}

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => message;
}

class LedgerStore extends ChangeNotifier {
  BelongingsStore? belongings;
  Future<BelongingsStore> openBelongings() async {
    final ledgerPath = database?.path;
    final root = ledgerPath == null
        ? await getDatabasesPath()
        : p.dirname(ledgerPath);
    belongings ??= BelongingsStore(
      p.join(
        root,
        '${ledgerPath == null ? 'youshu' : p.basename(ledgerPath)}.belongings.sqlite',
      ),
    );
    await belongings!.open();
    return belongings!;
  }

  void changed() => notifyListeners();
  final ValueNotifier<double?> fontPreview = ValueNotifier(null);
  double get fontScale => fontScaleOf(state);
  Future<void> setFontScale(double value) async {
    final before = state['fontScale'];
    state['fontScale'] = value.clamp(.8, 1.4);
    try {
      await persist(preferencesOnly: true);
    } catch (_) {
      state['fontScale'] = before;
      rethrow;
    } finally {
      fontPreview.value = null;
    }
  }

  Future<void> setBalanceExclusions(
    Set<String> categories,
    Set<String> tags,
  ) async {
    if (busy) throw const FormatException('请稍后再试');
    final book = active, previous = active['balance_exclusions'];
    final validCategories = dictionary(
      book,
      'category',
      archived: true,
    ).map((e) => e['id']).toSet();
    final validTags = dictionary(
      book,
      'tag',
      archived: true,
    ).map((e) => e['id']).toSet();
    if (!validCategories.containsAll(categories) ||
        !validTags.containsAll(tags)) {
      throw const FormatException('分类或标签已变更，请重新选择');
    }
    book['balance_exclusions'] = {
      'categories': categories.toList(),
      'tags': tags.toList(),
    };
    try {
      await persist();
    } catch (_) {
      book['balance_exclusions'] = previous;
      invalidateLedger(book);
      rethrow;
    }
  }

  final FlutterSecureStorage secure = const FlutterSecureStorage();
  Database? database;
  Json state = {
    'schema': 5,
    'ledgers': <dynamic>[],
    'active': '',
    'lastBackup': '',
  };
  String token = '', userId = '', endpoint = '', status = '';
  bool busy = false;
  List<Json> get allLedgers => (state['ledgers'] as List).cast<Json>();
  List<Json> get ledgers =>
      allLedgers.where((l) => l['deleted_at'] == null).toList();
  bool _batchEditing = false;
  Timer? backupTimer;
  DateTime? backupBurst;
  bool backupRunning = false;
  bool autoBackupReady = false;
  Future<void>? _maintenance;
  Json get active => ledgers.firstWhere(
    (v) => v['id'] == state['active'],
    orElse: () => ledgers.first,
  );
  List<Json> get viewLedgers {
    final ids = List<String>.from(state['viewLedgers'] ?? []);
    final result = ledgers.where((l) => ids.contains(l['id'])).toList();
    return result.isEmpty ? [active] : result;
  }

  Json? _view;
  List<Object> _viewIndexes = [];
  String _viewRule = '';
  Json get view {
    final books = viewLedgers;
    if (books.length == 1) return books.first;
    final indexes = books.map(ledgerIndex).toList(),
        rule = jsonEncode(settingsOf(active));
    if (_view == null ||
        rule != _viewRule ||
        !listEquals(indexes, _viewIndexes)) {
      _view = composeLedgers(books, settingsOf(active));
      _viewIndexes = indexes;
      _viewRule = rule;
    }
    return _view!;
  }

  Future<void> setViewLedgers(Set<String> ids) async {
    if (busy) throw const FormatException('请稍后再试');
    final books = ledgers.where((l) => ids.contains(l['id'])).toList();
    if (books.isEmpty || books.length != ids.length) {
      throw const FormatException('请选择有效账本');
    }
    final target = books.firstWhere(
      (l) => l['id'] == state['active'],
      orElse: () => books.first,
    );
    final before = {...state};
    busy = true;
    notifyListeners();
    try {
      if (books.length > 1) {
        final settings = settingsOf(target);
        _view = await compute(_viewInBackground, (books, settings));
        _viewIndexes = books.map(ledgerIndex).toList();
        _viewRule = jsonEncode(settings);
      }
      state['viewLedgers'] = ids.toList();
      state['active'] = target['id'];
      await persist(preferencesOnly: true);
    } catch (_) {
      state = before;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Map<String, Json>> mergeRates(Json ledger) async {
    final needed = <String, Set<String>>{};
    for (final e in records(ledger)) {
      final d = e['data'] as Json;
      if (d['base_currency'] != 'CNY' &&
          !isRefund(d) &&
          fxCurrency(d) != 'CNY') {
        (needed[fxCurrency(d)] ??= {}).add(d['date']);
      }
    }
    return historicalQuotes(needed, 'CNY');
  }

  Map<String, Json> historicalQuotes(
    Map<String, Set<String>> needed,
    String to,
  ) {
    final quotes = <String, Json>{};
    for (final group in needed.entries) {
      for (final day in group.value) {
        final quote = cachedQuote(group.key, to, day);
        if (quote != null) quotes['${group.key}/$day'] = quote;
      }
    }
    return quotes;
  }

  Json? cachedQuote(String from, String to, String date) {
    Iterable<Json> localQuotes() sync* {
      for (final item in (state['fxCache'] as Map? ?? {}).entries) {
        if (item.key.toString().startsWith('$from/$to/') &&
            item.value is Json) {
          yield item.value as Json;
        }
      }
      for (final item in (state['fxHistory'] as Map? ?? {}).entries) {
        if (item.key.toString().startsWith('$from/$to/') &&
            item.value is List) {
          yield* (item.value as List).whereType<Json>();
        }
      }
    }

    final requested = DateTime.tryParse(date);
    if (requested == null) return null;
    Json? best;
    for (final quote in localQuotes()) {
      final day = DateTime.tryParse(quote['date']?.toString() ?? '');
      if (day != null &&
          !day.isAfter(requested) &&
          requested.difference(day).inDays <= 10 &&
          (best == null || quote['date'].compareTo(best['date']) > 0)) {
        best = quote;
      }
    }
    return best == null ? null : {...best, 'cached': true};
  }

  Future<Json> mergeLedgers(
    Set<String> ids,
    String name, {
    Map<String, Json>? rates,
  }) async {
    if (busy || name.trim().isEmpty || ids.length < 2) {
      throw const FormatException('选择两个账本并填写名称');
    }
    final sources = ledgers.where((l) => ids.contains(l['id'])).toList();
    if (sources.length != ids.length) throw const FormatException('账本已变化，请重选');
    busy = true;
    notifyListeners();
    try {
      var combined = await compute(_mergeInBackground, (
        sources,
        settingsOf(sources.first),
      ));
      final quotes = rates ?? await mergeRates(combined);
      combined = await compute(convertMergedCny, (combined, quotes));
      final id = uuid.v4();
      combined.addAll({
        'id': id,
        'name': name.trim(),
        'shared': false,
        'role': 'owner',
        'pending': <dynamic>[],
        'lastSync': '',
      });
      for (final e in combined['entries']) {
        e.remove('source_ledger_id');
        e.remove('source_entry_id');
        e.remove('source_ledger_name');
        e['revision'] = 0;
      }
      final before = state;
      state = {
        ...state,
        'ledgers': [...allLedgers, combined],
        'active': id,
        'viewLedgers': [id],
      };
      try {
        await persist();
        return combined;
      } catch (_) {
        state = before;
        rethrow;
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  List<Json> records(Json ledger) => ledgerIndex(ledger).records;
  String get currency => settingsOf(active)['base_currency'];
  String display(num amount) => formatAmount(amount, currency);
  BookPeriod period(String key, {Json? ledger}) =>
      ledgerIndex(ledger ?? active).bookPeriods
          .putIfAbsent(key, () => _period(key, ledger: ledger));

  BookPeriod _period(String key, {Json? ledger}) {
    final rules = (settingsOf(ledger ?? active)['rules'] as List)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    if (key.length == 7) {
      final d = DateTime.parse('$key-01');
      final rule = rules.lastWhere(
        (r) => (r['effective'] as String).compareTo('$key-31') <= 0,
        orElse: () => rules.first,
      );
      return periodAt(dateKey(boundary(d.year, d.month, rule['day'])), rules);
    }
    return periodAt(key, rules);
  }

  List<Json> monthRecords(String key, {Json? ledger}) {
    final l = ledger ?? active,
        p = period(key, ledger: l),
        index = ledgerIndex(l);
    return index.periods.putIfAbsent(
      p.id,
      () => records(l).where((e) => p.contains(e['data']['date'])).toList(),
    );
  }

  String categoryKey(String name, {Json? ledger}) {
    if (name == '全部') return '';
    final list = dictionary(
      ledger ?? active,
      'category',
    ).where((e) => e['id'] == name || e['data']['name'] == name);
    return list.isEmpty ? name : list.first['id'];
  }

  int total(String month, String type, {Json? ledger, String? category}) {
    final l = ledger ?? active,
        index = ledgerIndex(l),
        p = period(month, ledger: l);
    final totals = index.totals.putIfAbsent(p.id, () {
      final sums = <String, int>{};
      for (final e in monthRecords(month, ledger: l)) {
        final d = e['data'] as Json,
            t = cashFlowType(d),
            n = cashFlowAmount(d),
            cid = d['category_id'] ?? '';
        void add(String k) => sums[k] = (sums[k] ?? 0) + n;
        add(t);
        add('$t:$cid');
        final parent = index.byId[cid]?['data']['parent_id'];
        if (parent != null && parent != '') add('$t:$parent');
      }
      return sums;
    });
    return totals[category == null
            ? type
            : '$type:${categoryKey(category, ledger: l)}'] ??
        0;
  }

  int budget(String key, String category, {Json? ledger}) {
    final l = ledger ?? active,
        p = period(key, ledger: l),
        id = categoryKey(category, ledger: l);
    final values = (ledgerIndex(l).byKind['budget'] ?? []).where(
      (e) =>
          e['data']['start_date'] == p.start &&
          e['data']['end_date'] == p.end &&
          e['data']['category_id'] == id,
    );
    if (id.isEmpty && settingsOf(l)['monthly_budget'] != null) {
      final generation = settingsOf(l)['budget_generation'] ?? 0;
      final current = values.where(
        (e) => e['data']['template_generation'] == generation,
      );
      return current.isEmpty
          ? settingsOf(l)['monthly_budget']
          : current.last['data']['amount'];
    }
    return values.isEmpty ? 0 : values.last['data']['amount'];
  }

  List<Json> choices(String kind, {String? type, bool archived = false}) {
    final rows = dictionary(active, kind, type: type, archived: archived);
    if (kind != 'category' || archived) return rows;
    final hidden = dictionary(
      active,
      'category',
    ).where((e) => e['data']['archived'] == true).map((e) => e['id']).toSet();
    return rows.where((e) => !hidden.contains(e['data']['parent_id'])).toList();
  }

  bool get canEdit => active['role'] != 'viewer';

  Future<void> initialize({void Function(Json)? onPreferencesLoaded}) async {
    database ??= await openLedgerDatabase(
      p.join(await getDatabasesPath(), 'yousu.db'),
    );
    final loaded = await readState(
      database!,
      seedWriter: _writer,
      onPreferencesLoaded: onPreferencesLoaded,
    );
    state = loaded ?? state;
    var needsSave = loaded == null || state['schema'] != 5;
    for (final book in allLedgers.where((l) => l['shared'] == true)) {
      // The current entries already include all locally committed changes.
      // Preserve the retired queue as local history without replaying it.
      book['retired_sharing'] = {
        'role': book['role'],
        'last_sync': book['lastSync'] ?? '',
        'operations': book['pending'] ?? <dynamic>[],
      };
      book
        ..['shared'] = false
        ..['role'] = 'owner'
        ..['pending'] = <dynamic>[]
        ..['lastSync'] = '';
      needsSave = true;
    }
    if (ledgers.isEmpty) {
      final ledger = freshLedger('日常账本');
      state['ledgers'] = [...allLedgers, ledger];
      state['active'] = ledger['id'];
      needsSave = true;
    }
    final drafts = state['importDrafts'] as List?;
    if (drafts != null &&
        drafts.isNotEmpty &&
        (_writer.last?['drafts'] as Map? ?? {}).isEmpty) {
      needsSave = true;
    }
    state['schema'] = 5;
    if (needsSave) {
      await persist();
    } else {
      _persistedDrafts = drafts;
    }
  }

  final StateWriter _writer = StateWriter();
  Future<void> _writeTail = Future.value();
  Object? _persistedDrafts;
  Timer? _viewSaveTimer, _widgetTimer;
  bool _viewDirty = false;
  Future<void>? _viewSave, _widgetWork;
  String _lastWidgetKey = '';

  Future<void> _enqueueWrite(Future<void> Function() work) {
    final task = _writeTail.then((_) => work());
    _writeTail = task.catchError((Object _) {});
    return task;
  }

  void queueViewPreferences({void Function(Object)? onError}) {
    _viewDirty = true;
    _viewSaveTimer?.cancel();
    _viewSaveTimer = Timer(const Duration(milliseconds: 300), () {
      flushViewPreferences().catchError((Object e) {
        onError?.call(e);
      });
    });
  }

  Future<void> flushViewPreferences() {
    _viewSaveTimer?.cancel();
    _viewSaveTimer = null;
    return _viewSave ??= _flushViewPreferences().whenComplete(
      () => _viewSave = null,
    );
  }

  Future<void> _flushViewPreferences() async {
    while (_viewDirty && database != null && database!.isOpen) {
      _viewDirty = false;
      // Only these view fields are merged into the last committed preferences.
      // A draft or financial mutation awaiting its transaction stays atomic.
      final patch = jsonEncode({
        for (final key in [
          'transactionViews',
          'transactionFilters',
          'budgetViews',
          'statisticsViews',
          'statisticsFilters',
          'lastTab',
          'navLayout',
          'analysisMode',
          'lastTransactionPeriod',
        ])
          if (state.containsKey(key)) key: state[key],
      });
      try {
        await _enqueueWrite(() async {
          var body = _writer.last?['preferences'] as String?;
          if (body == null) {
            final rows = await database!.query('preferences', where: 'id=1');
            body = rows.isEmpty ? '{}' : rows.first['body'] as String;
          }
          final preferences = await compute(_mergeViewPreferences, (
            body,
            patch,
          ));
          if (!database!.isOpen) return;
          await _writer.write(database!, {
            'preferences': preferences,
          }, preferencesOnly: true);
        });
      } catch (_) {
        _viewDirty = true;
        rethrow;
      }
    }
  }

  Future<void> persist({
    bool preferencesOnly = false,
    bool notify = true,
  }) async {
    if (_batchEditing) return;
    final includesViewPreferences = !preferencesOnly && _viewDirty;
    if (!preferencesOnly) {
      // The financial transaction already includes the latest view fields.
      // Reuse it instead of performing a second preferences transaction.
      _viewSaveTimer?.cancel();
      _viewSaveTimer = null;
      _viewDirty = false;
      for (final l in ledgers) {
        invalidateLedger(l);
      }
    }
    final draftList = state['importDrafts'];
    final data = Map<String, dynamic>.from(state);
    if (preferencesOnly) data.remove('ledgers');
    if (identical(_persistedDrafts, draftList)) data.remove('importDrafts');
    if (!preferencesOnly) {
      state['dataRevision'] = (state['dataRevision'] as int? ?? 0) + 1;
      data['dataRevision'] = state['dataRevision'];
      data['backupDirty'] = true;
    }
    final prepared = compute(encodePersistence, (data, preferencesOnly));
    try {
      await _enqueueWrite(() async {
        final encoded = await prepared;
        await _writer.write(
          database!,
          encoded,
          preferencesOnly: preferencesOnly,
        );
      });
    } catch (_) {
      if (includesViewPreferences) _viewDirty = true;
      rethrow;
    }
    _persistedDrafts = draftList;
    if (!preferencesOnly) {
      state['backupDirty'] = true;
      scheduleBackup();
    }
    if (notify) notifyListeners();
    queueWidgetRefresh();
  }

  String get _widgetKey => '${_writer.last?['widgetScope']}/${today()}';

  void queueWidgetRefresh() {
    if (_writer.last?['widgetScope'] == null || _widgetKey == _lastWidgetKey) {
      return;
    }
    _widgetTimer?.cancel();
    _widgetTimer = Timer(const Duration(milliseconds: 250), flushWidgetRefresh);
  }

  Future<void> flushWidgetRefresh() {
    _widgetTimer?.cancel();
    _widgetTimer = null;
    return _widgetWork ??= _refreshWidget().whenComplete(
      () => _widgetWork = null,
    );
  }

  Future<void> _refreshWidget() async {
    while (_writer.last?['widgetScope'] != null &&
        _widgetKey != _lastWidgetKey) {
      final key = _widgetKey;
      try {
        final committed = _writer.last!;
        final books = (committed['ledgers'] as List? ?? []).cast<Json>();
        if (books.isEmpty) return;
        final book = books.firstWhere(
          (book) => book['id'] == committed['widgetScope']['active'],
          orElse: () => books.first,
        );
        final payload = await compute(_committedWidgetPayload, (book, today()));
        if (key != _widgetKey) continue;
        await system.invokeMethod('updateWidget', payload);
        _lastWidgetKey = key;
      } on MissingPluginException {
        _lastWidgetKey = key;
      } on PlatformException {
        return; // Retry the latest snapshot on the next foreground refresh.
      } on FormatException {
        return;
      }
    }
  }

  @override
  void dispose() {
    _viewSaveTimer?.cancel();
    _widgetTimer?.cancel();
    backupTimer?.cancel();
    fontPreview.dispose();
    super.dispose();
  }

  Future<void> select(String id, {bool preserveView = false}) async {
    await flushViewPreferences();
    state['active'] = id;
    if (!preserveView) state['viewLedgers'] = [id];
    await persist(preferencesOnly: true);
  }

  Set<String> get importedIds => {
    for (final l in ledgers)
      for (final e in (l['entries'] as List))
        if (e['kind'] == 'entry') e['id'] as String,
    for (final l in ledgers)
      for (final row in ((l['import_manifest']?['rows'] as Map?)?.values ?? []))
        categoryId('import', 'entry', row['source_id']),
    for (final batch in (state['importHistory'] as List? ?? []))
      ...List<String>.from(batch['ids'] ?? []),
  };

  Future<int> importBills(
    ImportPreview preview, {
    required bool skipZero,
    required String name,
  }) async {
    if (busy) throw const FormatException('正在同步，请稍后导入');
    if (preview.errors.isNotEmpty ||
        (!skipZero && preview.zeroRows.isNotEmpty)) {
      throw const FormatException('请先处理错误并确认零金额记录');
    }
    if (name.trim().isEmpty || name.trim().length > 40) {
      throw const FormatException('账本名称需为 1–40 字');
    }
    final known = importedIds;
    final rows = preview.valid.where((e) => !known.contains(e.id)).toList();
    if (rows.isEmpty) throw const FormatException('这些有效记录已导入，无需重复导入');
    final before = jsonDecode(jsonEncode(state)) as Json;
    final now = DateTime.now().toUtc().toIso8601String();
    final created = <Json>[];
    for (final currency in rows.map((e) => e.currency).toSet()) {
      final ledger = freshLedger(
        '${name.trim()} · $currency',
        currency: currency,
      );
      final entries = ledger['entries'] as List;
      final audit = <String, dynamic>{};
      final categoryIndex = <(String, String, String), String>{
        for (final e in dictionary(ledger, 'category'))
          (e['data']['type'], e['data']['parent_id'], e['data']['name']):
              e['id'],
      };
      final tagIndex = <String, Json>{};
      String category(String type, String parent, String child) {
        String ensure(String label, String parentId) {
          final key = (type, parentId, label);
          final found = categoryIndex[key];
          if (found != null) return found;
          final id = uuid.v4();
          entries.add(
            entity(id, 'category', {
              'name': label,
              'type': type,
              'parent_id': parentId,
              'icon': defaultIcons[parent] ?? 'category',
              'color': type == 'income' ? '#BD672D' : '#126C62',
              'order': categoryIndex.length.clamp(0, 10000),
              'archived': false,
            }),
          );
          categoryIndex[key] = id;
          return id;
        }

        final root = ensure(parent, '');
        return child == parent ? root : ensure(child, root);
      }

      for (final r in rows.where((e) => e.currency == currency)) {
        final tagIds = <String>[];
        for (final name in r.tags) {
          var tag = tagIndex[name];
          if (tag == null) {
            tag = entity(uuid.v4(), 'tag', {
              'name': name,
              'color': '#4265A8',
              'order': tagIndex.length.clamp(0, 10000),
              'archived': false,
            });
            entries.add(tag);
            tagIndex[name] = tag;
          }
          tagIds.add(tag['id']);
        }
        final cid = category(r.type, r.parent, r.category);
        entries.add(
          entity(r.id, 'entry', {
            'type': r.type,
            'date': r.dateTime.substring(0, 10),
            'time': r.dateTime.substring(11, 16),
            'category': r.category,
            'category_id': cid,
            'account': r.account,
            'note': r.note,
            'tag_ids': tagIds,
            'amount': r.amount,
            'base_amount_minor': r.amount,
            'original_amount_minor': r.amount,
            'original_currency': currency,
            'currency_scale': currencies[currency],
            'base_currency': currency,
            'fx_rate': '1',
            'fx_rate_date': r.dateTime.substring(0, 10),
            'fx_mode': 'identity',
            'fx_source': 'identity',
            'created_at': now,
            'updated_at': now,
            'to_currency': currency,
            'to_amount_minor': 0,
            'to_account': '',
          }),
        );
        audit[r.id] = {
          'source_id': r.sourceId,
          'date_time': r.dateTime,
          'sheet': r.sheet,
          'line': r.line,
          'original': r.original,
          'review': r.review,
        };
      }
      ledger['import_manifest'] = {
        'file': preview.filename,
        'sha256': preview.digest,
        'at': now,
        'rows': audit,
      };
      created.add(ledger);
    }
    created.first['import_manifest']['zero_rows'] = preview.zeroRows
        .map((r) => {'source_id': r.sourceId, 'original': r.original})
        .toList();
    busy = true;
    notifyListeners();
    try {
      (state['ledgers'] as List).addAll(created);
      state['active'] = created.first['id'];
      (state.putIfAbsent('importHistory', () => <dynamic>[]) as List).add({
        ..._batchRecord(
          file: preview.filename,
          source: 'suishouji',
          books: created,
          ids: rows.map((r) => r.id).toSet(),
        ),
        'sha256': preview.digest,
        'zero': preview.zeroRows
            .map((r) => {'source_id': r.sourceId, 'original': r.original})
            .toList(),
      });
      await persist();
      return rows.length;
    } catch (_) {
      state = before;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> saveDictionaryBatch(List<Json> values) async {
    if (busy || active['role'] != 'owner') {
      throw const FormatException('仅账本所有者可在非同步状态下管理分类');
    }
    final before = {
      ...state,
      'ledgers': [
        for (final l in allLedgers)
          l == active
              ? {
                  ...l,
                  'entries': List<dynamic>.from(l['entries']),
                  'pending': List<dynamic>.from(l['pending']),
                }
              : l,
      ],
    };
    try {
      for (final value in values) {
        final rows = active['entries'] as List;
        final old = rows.where((e) => e['id'] == value['id']).firstOrNull;
        if (old?['deleted'] == true && value['deleted'] != true) {
          throw const FormatException('已删除的分类或标签需重新创建');
        }
        final revision = old?['revision'] ?? 0;
        final next = {
          ...value,
          'revision': active['shared'] == true ? revision + 1 : 0,
        };
        rows.removeWhere((e) => e['id'] == value['id']);
        rows.add(next);
        if (active['shared'] == true) {
          (active['pending'] as List).add({
            'operation_id': uuid.v4(),
            'id': next['id'],
            'kind': next['kind'],
            'data': next['data'],
            'base_revision': revision,
            'deleted': next['deleted'] ?? false,
          });
        }
      }
      await persist();
    } catch (_) {
      state = before;
      rethrow;
    }
  }

  Future<void> addLedger(
    String name, {
    String currency = 'CNY',
    int day = 1,
  }) async {
    final ledger = freshLedger(name, currency: currency, day: day);
    (state['ledgers'] as List).add(ledger);
    state['active'] = ledger['id'];
    state['viewLedgers'] = [ledger['id']];
    await persist();
  }

  Future<void> saveStyledDictionary(
    Json input, {
    required String kind,
    Json? existing,
  }) async {
    final data = Map<String, dynamic>.from(input),
        visual = data.remove('_visualIcon'),
        image = data.remove('_customImage');
    final String id = existing?['id'] ?? uuid.v4();
    final oldIcons = active['icon_overrides'],
        oldImages = active['custom_icons'];
    try {
      active['icon_overrides'] = <String, dynamic>{
        ...Map<String, dynamic>.from(oldIcons as Map? ?? {}),
        id: visual,
      };
      if (image != null) {
        active['custom_icons'] = <String, dynamic>{
          ...Map<String, dynamic>.from(oldImages as Map? ?? {}),
          visual: image,
        };
      }
      await saveEntry(data, kind: kind, existing: existing, id: id);
    } catch (_) {
      active['icon_overrides'] = oldIcons;
      active['custom_icons'] = oldImages;
      rethrow;
    }
  }

  Future<void> saveEntry(
    Json data, {
    Json? existing,
    bool deleted = false,
    String kind = 'entry',
    String? id,
  }) async {
    if (busy && !_batchEditing) throw const FormatException('正在同步，请稍后编辑');
    if (!canEdit || (kind != 'entry' && active['role'] != 'owner')) {
      throw ApiError(403, '当前成员没有此操作权限');
    }
    if (active['shared'] == true &&
        existing != null &&
        existing['author'] != userId &&
        active['role'] != 'owner') {
      throw ApiError(403, '只能编辑自己记录的账目');
    }
    data = Map<String, dynamic>.from(data);
    if (kind == 'entry' && existing != null) {
      for (final field in [
        'source_key',
        'source_fingerprint',
        'source_status',
      ]) {
        if (existing['data'][field] != null) {
          data[field] = existing['data'][field];
        }
      }
    }
    if (kind == 'entry' && !data.containsKey('original_currency')) {
      data.addAll({
        'original_currency': currency,
        'original_amount_minor': data['amount'],
        'currency_scale': currencies[currency],
        'base_currency': currency,
        'base_amount_minor': data['amount'],
        'fx_rate': '1',
        'fx_rate_date': data['date'],
        'fx_source': 'identity',
        'fx_mode': 'identity',
        'category_id': data['type'] == 'transfer'
            ? ''
            : categoryKey(data['category']),
        'tag_ids': <String>[],
        'to_currency': currency,
        'to_amount_minor': data['type'] == 'transfer' ? data['amount'] : 0,
      });
    }
    if (kind == 'entry') {
      final refunds = records(active).where(
        (e) =>
            e['id'] != existing?['id'] &&
            e['data']['refund_of'] == existing?['id'] &&
            isRefund(e['data']),
      );
      if (existing != null &&
          refunds.isNotEmpty &&
          (deleted ||
              data['amount'] != existing['data']['amount'] ||
              data['category_id'] != existing['data']['category_id'] ||
              data['type'] != 'expense' ||
              data['original_currency'] !=
                  existing['data']['original_currency'] ||
              refunds.any(
                (e) => data['date'].compareTo(e['data']['date']) > 0,
              ))) {
        throw const FormatException('请先删除关联退款，再修改原支出的金额、分类或删除原记录');
      }
      if (isRefund(data) && !deleted) {
        final sources = records(active)
            .where((e) => e['id'] == data['refund_of']);
        if (sources.isEmpty) throw const FormatException('原支出不存在');
        final source = sources.single['data'];
        final used = records(active)
            .where(
              (e) =>
                  e['id'] != existing?['id'] &&
                  e['data']['refund_of'] == data['refund_of'],
            )
            .fold<int>(0, (v, e) => v + (e['data']['amount'] as int));
        if (source['type'] != 'expense' ||
            isRefund(source) ||
            data['type'] != 'expense' ||
            data['category_id'] != source['category_id'] ||
            data['date'].compareTo(source['date']) < 0 ||
            data['amount'] + used > source['amount']) {
          throw const FormatException('退款需关联原支出，日期不早于原记录，金额不超过剩余可退金额');
        }
      }
      if (existing?['data']['purged'] == true) {
        throw const FormatException('该记录已永久删除');
      }
      data['deleted_at'] = deleted
          ? (existing?['data']['deleted_at'] ??
                DateTime.now().toUtc().toIso8601String())
          : null;
      data['trash_group'] = deleted
          ? (data['trash_group'] ?? existing?['id'] ?? id ?? '')
          : '';
      data['created_at'] = existing == null
          ? DateTime.now().toUtc().toIso8601String()
          : existing['data']['created_at'];
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();
    }
    final before = {
      ...active,
      'entries': List<dynamic>.from(active['entries']),
      'pending': List<dynamic>.from(active['pending']),
    };
    final entryId = existing?['id'] ?? id ?? uuid.v4();
    if (['category', 'tag'].contains(kind) &&
        !deleted &&
        (active['entries'] as List).any(
          (row) => row['id'] == entryId && row['deleted'] == true,
        )) {
      throw const FormatException('已删除的分类或标签需重新创建');
    }
    final revision = (existing?['revision'] as int? ?? 0);
    final entry = {
      'id': entryId,
      'kind': kind,
      'data': data,
      'revision': active['shared'] == true ? revision + 1 : 0,
      'deleted': deleted,
      'author': existing?['author'] ?? userId,
      'author_name': existing?['author_name'] ?? '我',
    };
    (active['entries'] as List).removeWhere((e) => e['id'] == entryId);
    (active['entries'] as List).add(entry);
    if (active['shared'] == true) {
      (active['pending'] as List).add({
        'operation_id': uuid.v4(),
        'id': entryId,
        'kind': kind,
        'data': data,
        'base_revision': revision,
        'deleted': deleted,
      });
    }
    try {
      await persist();
    } catch (_) {
      final index = allLedgers.indexWhere((e) => e['id'] == before['id']);
      state['ledgers'][index] = before;
      rethrow;
    }
  }

  int refundable(Json entry) =>
      (entry['data']['amount'] as int) -
      records(active)
          .where((e) => e['data']['refund_of'] == entry['id'])
          .fold<int>(0, (v, e) => v + (e['data']['amount'] as int));
  Future<void> refund(Json entry, int amount) async {
    final d = entry['data'] as Json;
    if (amount <= 0 || amount > refundable(entry)) {
      throw const FormatException('退款金额超出可退范围');
    }
    await saveEntry({
      ...d,
      'source_key': '',
      'refund_of': entry['id'],
      'type': 'expense',
      'date': today(),
      'time': DateTime.now().toIso8601String().substring(11, 16),
      'amount': amount,
      'base_amount_minor': amount,
      'original_amount_minor': amount,
      'original_currency': currency,
      'currency_scale': currencies[currency],
      'fx_rate': '1',
      'fx_source': 'identity',
      'fx_mode': 'identity',
      'fx_rate_date': today(),
      'note': '退款 · ${d['note'] ?? categoryName(active, d)}',
    });
  }

  Future<void> setBudget(
    String key,
    String category,
    int amount, {
    Map<String, int>? daily,
    Map<String, int>? allocations,
    bool resetDays = false,
  }) async {
    final p = period(key), cid = categoryKey(category);
    final old = (ledgerIndex(active).byKind['budget'] ?? <Json>[]).where(
      (e) => e['data']['period_id'] == p.id && e['data']['category_id'] == cid,
    );
    final overrides =
        daily ??
        (resetDays
            ? <String, int>{}
            : Map<String, int>.from(
                (cid.isNotEmpty ||
                        settingsOf(active)['monthly_budget'] == null ||
                        old.firstOrNull?['data']['template_generation'] ==
                            settingsOf(active)['budget_generation'])
                    ? (old.firstOrNull?['data']['daily_overrides'] ?? {})
                    : {},
              ));
    if (cid.isEmpty) allocateDays(p, amount, overrides);
    await saveEntry(
      {
        'template_generation': settingsOf(active)['budget_generation'] ?? 0,
        'daily_overrides': overrides,
        'daily_allocations': cid.isEmpty
            ? (allocations ?? allocateDays(p, amount, overrides))
            : <String, int>{},
        'month': p.start.substring(0, 7),
        'category': category,
        'category_id': cid,
        'amount': amount,
        'base_currency': currency,
        'period_id': p.id,
        'start_date': p.start,
        'end_date': p.end,
      },
      kind: 'budget',
      id: 'budget:${p.id}:$cid',
      existing: old.isEmpty ? null : old.first,
    );
  }

  Json? budgetEntry(String key) =>
      (ledgerIndex(active).byKind['budget'] ?? <Json>[])
          .where(
            (e) =>
                e['data']['period_id'] == period(key).id &&
                e['data']['category_id'] == '' &&
                (settingsOf(active)['monthly_budget'] == null ||
                    e['data']['template_generation'] ==
                        (settingsOf(active)['budget_generation'] ?? 0)),
          )
          .lastOrNull;
  Map<String, int> dailyBudgets(String key) {
    final saved = budgetEntry(key)?['data']['daily_allocations'] as Map?;
    return saved != null && saved.isNotEmpty
        ? Map<String, int>.from(saved)
        : allocateDays(
            period(key),
            budget(key, '全部'),
            Map.from(budgetEntry(key)?['data']['daily_overrides'] ?? {}),
          );
  }

  int budgetSpent(String key, {String? category}) {
    final q = budgetQuery(active, period(key));
    return category == null
        ? q.spent
        : q.categories[categoryKey(category)] ?? 0;
  }

  Future<void> setDailyBudget(String date, int amount) async {
    final allocation = dailyBudgets(date), old = allocation[date]!;
    final overrides = Map<String, int>.from(
      budgetEntry(date)?['data']['daily_overrides'] ?? {},
    );
    final next = {...allocation, date: amount};
    overrides[date] = amount;
    await setBudget(
      date,
      '全部',
      budget(date, '全部') + amount - old,
      daily: overrides,
      allocations: next,
    );
  }

  Future<void> setBudgetExclusions(
    Set<String> categories,
    Set<String> tags,
  ) async {
    final row = ledgerIndex(active).byId['settings']!;
    await saveEntry(
      {
        ...row['data'] as Json,
        'budget_excluded_categories': categories.toList(),
        'budget_excluded_tags': tags.toList(),
      },
      kind: 'ledger_settings',
      existing: row,
    );
  }

  Future<List<Json>> setCycle(int day, {bool preview = false}) async {
    if (day < 1 || day > 31) throw const FormatException('起始日需为 1–31');
    final old = ledgerIndex(active).byKind['ledger_settings']!.first;
    final rules = [
      {'day': day, 'effective': '2000-01-01'},
    ];
    final changes = <Json>[
      {
        ...old,
        'data': {...old['data'] as Json, 'rules': rules},
      },
    ];
    final migrated = <String, Json>{};
    final generation = settingsOf(active)['budget_generation'] ?? 0;
    bool validBudget(Json b) =>
        b['data']['category_id'] != '' ||
        (b['data']['template_generation'] ?? 0) == generation;
    final daily = <String, int>{
      for (final b in ledgerIndex(active).byKind['budget'] ?? <Json>[])
        if (validBudget(b))
          ...Map<String, int>.from(b['data']['daily_overrides'] ?? {}),
    };
    final previousBudgets =
        List<Json>.from(ledgerIndex(active).byKind['budget'] ?? [])..sort(
          (a, b) => (a['data']['start_date'] as String).compareTo(
            b['data']['start_date'],
          ),
        );
    for (final e in previousBudgets) {
      if (!validBudget(e)) continue;
      final d = e['data'] as Json;
      final m = DateTime.parse(
        '${(d['start_date'] as String).substring(0, 7)}-01',
      );
      final p = periodAt(dateKey(boundary(m.year, m.month, day)), rules);
      final next = {
        ...e,
        'data': {
          ...d,
          'month': p.start.substring(0, 7),
          'period_id': p.id,
          'start_date': p.start,
          'end_date': p.end,
          'daily_overrides': {
            for (final e in daily.entries)
              if (d['category_id'] == '' && p.contains(e.key)) e.key: e.value,
          },
        },
      };
      (next['data'] as Json)['daily_allocations'] = d['category_id'] == ''
          ? allocateDays(
              p,
              d['amount'],
              (next['data'] as Json)['daily_overrides'],
            )
          : <String, int>{};
      final key = '${p.id}:${d['category_id']}';
      final previous = migrated[key];
      if (previous != null) changes.add({...previous, 'deleted': true});
      migrated[key] = next;
    }
    // A manual date can move into a neighbouring period with no prior budget.
    for (final e in daily.entries) {
      final p = periodAt(e.key, rules), key = '${periodAt(e.key, rules).id}:';
      if (migrated.containsKey(key)) continue;
      final overrides = {
        for (final d in daily.entries)
          if (p.contains(d.key)) d.key: d.value,
      };
      final amount = overrides.values.fold<int>(0, (a, b) => a + b);
      migrated[key] = entity('budget:${p.id}:', 'budget', {
        'month': p.start.substring(0, 7),
        'category': '全部',
        'category_id': '',
        'amount': amount,
        'base_currency': currency,
        'period_id': p.id,
        'start_date': p.start,
        'end_date': p.end,
        'template_generation': settingsOf(active)['budget_generation'] ?? 0,
        'daily_overrides': overrides,
        'daily_allocations': allocateDays(p, amount, overrides),
      });
    }
    changes.addAll(migrated.values);
    if (preview) return migrated.values.toList();
    final history = active['cycle_history'];
    active['cycle_history'] = [
      ...history as List? ?? [],
      {
        'at': DateTime.now().toUtc().toIso8601String(),
        'settings': old['data'],
        'budgets': ledgerIndex(active).byKind['budget'] ?? [],
      },
    ];
    try {
      await saveDictionaryBatch(changes);
    } catch (_) {
      active['cycle_history'] = history;
      rethrow;
    }
    return migrated.values.toList();
  }

  Future<void> setTheme(String theme) async {
    state['theme'] = theme;
    await persist(preferencesOnly: true);
  }

  Future<void> setThemeStyle(String style) async {
    state['themeStyle'] = style;
    if (database == null) {
      notifyListeners();
      return;
    }
    await persist(preferencesOnly: true);
  }

  Future<void>? _rateUpdate;
  String rateError = '';
  bool get updatingRates => _rateUpdate != null;
  Json get referenceRates =>
      state['referenceRates'] as Json? ??
      {
        'date': '2026-11-19',
        'source': 'Frankfurter · 内置参考',
        'rates': {
          'USD': 1.0,
          'CNY': 6.6667,
          'EUR': 0.90975,
          'HKD': 7.8456,
          'JPY': 159.97,
          'GBP': 0.76038,
          'SGD': 1.2897,
          'AUD': 1.49,
          'CAD': 1.43,
        },
      };

  Future<void> updateRates({bool force = false}) {
    if (_rateUpdate != null) return _rateUpdate!;
    if (!force &&
        (state['autoRates'] == false || state['ratesCheckedDay'] == today())) {
      return Future.value();
    }
    final task = _downloadRates();
    _rateUpdate = task.whenComplete(() {
      _rateUpdate = null;
      notifyListeners();
    });
    notifyListeners();
    return _rateUpdate!;
  }

  Future<void> _downloadRates() async {
    http.Client? client;
    try {
      client = http.Client();
      final response = await client
          .get(Uri.parse('https://api.frankfurter.dev/v1/latest?base=USD'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw const FormatException('汇率服务暂不可用');
      final data = jsonDecode(response.body) as Json;
      final rates = Map<String, dynamic>.from(data['rates'] as Map)
        ..['USD'] = 1.0;
      if (data['base'] != 'USD' ||
          DateTime.tryParse(data['date']?.toString() ?? '') == null ||
          currencies.keys.any(
            (c) =>
                rates[c] is! num ||
                !(rates[c] as num).isFinite ||
                rates[c] <= 0,
          )) {
        throw const FormatException('汇率数据无效');
      }
      final previous = state['referenceRates'],
          checked = state['ratesCheckedDay'];
      state['referenceRates'] = {
        'date': data['date'],
        'source': 'Frankfurter',
        'rates': rates,
      };
      state['ratesCheckedDay'] = today();
      try {
        await persist(preferencesOnly: true);
      } catch (_) {
        state['referenceRates'] = previous;
        state['ratesCheckedDay'] = checked;
        rethrow;
      }
      rateError = '';
    } catch (_) {
      rateError = '更新失败，继续使用本机参考汇率';
      rethrow;
    } finally {
      client?.close();
    }
  }

  Future<Json> exchange(String from, String to, String date) async {
    final historical = cachedQuote(from, to, date);
    if (date != today() && historical != null) return historical;
    final reference = referenceRates;
    final rates = reference['rates'] as Map;
    if (!currencies.containsKey(from) || !currencies.containsKey(to)) {
      throw const FormatException('不支持的币种');
    }
    return {
      'rate': ((rates[to] as num) / (rates[from] as num)).toStringAsFixed(12),
      'date': reference['date'],
      'source': reference['source'],
      'cached': true,
    };
  }

  Uri baseUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入 HTTPS 地址，不要包含用户名、密码或查询参数');
    }
    return uri;
  }

  Future<dynamic> api(String path, {Json? body, String method = 'GET'}) async {
    if (endpoint.isEmpty) throw const FormatException('请先连接共享服务');
    final request = http.Request(method, Uri.parse('$endpoint$path'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-Youshu-Schema': '5',
        'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 20)),
    );
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw ApiError(response.statusCode, '服务返回异常，请检查地址');
    }
    if (response.statusCode >= 400) {
      final detail = decoded['detail'];
      throw ApiError(
        response.statusCode,
        detail is String
            ? detail
            : response.statusCode == 409
            ? '账目发生冲突，请先保留本地副本再拉取云端'
            : '操作失败，请检查权限和数据',
      );
    }
    return decoded;
  }

  Future<void> checkProtocol() async {
    final caps = await api('/api/capabilities');
    if (caps['schema'] != 5) {
      throw const FormatException('共享服务版本不兼容，请先升级后台到 0.6.1');
    }
    if (caps['dictionary_deletions'] == true) {
      state['dictionaryDeletionServer'] = endpoint;
    }
  }

  Future<void> login(
    String server,
    String name,
    String password, {
    String code = '',
  }) async {
    final next = baseUri(server).toString().replaceAll(RegExp(r'/$'), '');
    if (endpoint.isNotEmpty &&
        next != endpoint &&
        ledgers.any((l) => l['shared'] == true)) {
      throw const FormatException('已有共享账本，请先使用当前服务，避免跨服务混合');
    }
    final old = endpoint;
    endpoint = next;
    try {
      await checkProtocol();
      final result = await api(
        code.isEmpty ? '/api/login' : '/api/join',
        method: 'POST',
        body: {
          'name': name,
          'password': password,
          if (code.isNotEmpty) 'code': code,
        },
      );
      if (userId.isNotEmpty &&
          userId != result['user_id'] &&
          ledgers.any((l) => l['shared'] == true)) {
        throw const FormatException('此设备已关联其他成员，请使用原账号');
      }
      token = result['token'];
      userId = result['user_id'];
      await secure.write(key: 'server', value: endpoint);
      await secure.write(key: 'token', value: token);
      await secure.write(key: 'userId', value: userId);
      await refreshLedgers();
    } catch (_) {
      if (token.isEmpty) endpoint = old;
      rethrow;
    }
  }

  Future<void> refreshLedgers() async {
    final remote = await api('/api/ledgers') as List;
    for (final r in remote) {
      if ((state['hiddenSharedBooks'] as List? ?? []).contains(r['id'])) {
        continue;
      }
      final found = allLedgers.where((l) => l['id'] == r['id']);
      if (found.isEmpty) {
        final l = freshLedger(r['name'] as String)
          ..['id'] = r['id']
          ..['shared'] = true
          ..['role'] = r['role'];
        final snapshot = await api('/api/ledgers/${r['id']}/snapshot');
        l['entries'] = snapshot['entries'];
        (state['ledgers'] as List).add(l);
      } else {
        found.first['role'] = r['role'];
        found.first['name'] = r['name'];
      }
    }
    await persist();
  }

  Future<void> publish() async {
    if (busy) return;
    await api(
      '/api/ledgers',
      method: 'POST',
      body: {'id': active['id'], 'name': active['name']},
    );
    if (active['shared'] != true) {
      active['shared'] = true;
      active['role'] = 'owner';
      final ordered = (active['entries'] as List).cast<Json>().toList()
        ..sort((a, b) => entityOrder(a).compareTo(entityOrder(b)));
      for (final e in ordered) {
        if (e['data']['purged'] == true) continue;
        e['revision'] = 1;
        e['author'] = userId;
        (active['pending'] as List).add({
          'operation_id': uuid.v4(),
          'id': e['id'],
          'kind': e['kind'],
          'data': e['data'],
          'base_revision': 0,
          'deleted': e['deleted'],
        });
      }
      await persist();
    }
    await sync();
  }

  Future<void> sync() async {
    if (busy || active['shared'] != true) return;
    busy = true;
    status = '正在同步';
    notifyListeners();
    final ledger = active;
    try {
      await checkProtocol();
      final pending = ledger['pending'] as List;
      while (pending.isNotEmpty) {
        final operation = pending.first as Json;
        final deletion = operation['_action'] == 'dictionary_delete';
        await api(
          '/api/ledgers/${ledger['id']}/${deletion ? 'dictionary-deletions' : 'operations'}',
          method: 'POST',
          body: deletion
              ? (Map<String, dynamic>.from(operation)..remove('_action'))
              : operation,
        );
        pending.removeAt(0);
        await persist();
      }
      for (final e in (ledger['entries'] as List).where(
        (e) => e['purge_pending'] == true,
      )) {
        await api(
          '/api/ledgers/${ledger['id']}/trash/${e['id']}',
          method: 'DELETE',
        );
      }
      final snapshot = await api('/api/ledgers/${ledger['id']}/snapshot');
      // 同步期间 UI 禁止编辑，避免快照替换未发送的新记录。
      ledger['entries'] = snapshot['entries'];
      ledger['lastSync'] = DateTime.now().toIso8601String();
      status = '已同步';
      await persist();
    } catch (e) {
      status = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> resolveWithCopy() async {
    final copy = jsonDecode(jsonEncode(active)) as Json;
    copy['id'] = uuid.v4();
    copy['name'] = '${copy['name']} · 冲突副本';
    copy['shared'] = false;
    copy['role'] = 'owner';
    copy['pending'] = [];
    (state['ledgers'] as List).add(copy);
    active['pending'] = [];
    await persist();
    await sync();
  }

  Future<Json> davSettings() async =>
      jsonDecode(await secure.read(key: 'dav') ?? '{}') as Json;
  Future<void> saveDav(String url, String name, String password) async {
    await configureDav(
      url,
      name,
      password,
      automatic: state['autoBackup'] == true,
      keep: state['backupKeep'] as int? ?? 7,
    );
  }

  Future<void> configureDav(
    String url,
    String name,
    String password, {
    required bool automatic,
    required int keep,
  }) async {
    if (backupRunning) throw const FormatException('备份进行中，请稍后编辑');
    if (keep < 1 || keep > 365) {
      throw const FormatException('每台设备保留数量须为 1–365');
    }
    final address = url.isEmpty
        ? null
        : baseUri(url).toString().replaceFirst(RegExp(r'/$'), '');
    final previous = await davSettings();
    if (backupRunning) throw const FormatException('备份进行中，请稍后编辑');
    final directoryChanged =
        previous['url'] != address || previous['name'] != name;
    final preferences = {
      'autoBackup': address != null && automatic,
      'backupKeep': keep,
      if (directoryChanged) ...{
        'lastBackup': null,
        'backupDay': null,
        'backupError': null,
        'backupDirty': true,
      },
    };
    final old = {for (final key in preferences.keys) key: state[key]};
    final ready = autoBackupReady;
    autoBackupReady = false;
    backupTimer?.cancel();
    backupBurst = null;
    var wroteCredentials = false;
    try {
      if (address == null) {
        await secure.delete(key: 'dav');
      } else {
        await secure.write(
          key: 'dav',
          value: jsonEncode({
            'url': address,
            'name': name,
            'password': password,
          }),
        );
      }
      wroteCredentials = true;
      state.addAll(preferences);
      await persist(preferencesOnly: true, notify: false);
      autoBackupReady = address != null;
    } catch (_) {
      state.addAll(old);
      if (wroteCredentials) {
        if (previous.isEmpty) {
          await secure.delete(key: 'dav');
        } else {
          await secure.write(key: 'dav', value: jsonEncode(previous));
        }
      }
      autoBackupReady = ready;
      rethrow;
    } finally {
      scheduleBackup();
      changed();
    }
  }

  Future<http.Response> dav(
    String method,
    String path, {
    String? body,
    Map<String, String>? extra,
  }) async {
    final settings = await davSettings();
    if (settings['url'] == null) throw const FormatException('请先设置 WebDAV');
    final req = http.Request(method, Uri.parse('${settings['url']}$path'));
    req.followRedirects = false; // 不将认证数据发送到重定向地址。
    req.headers.addAll({
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${settings['name']}:${settings['password']}'))}',
      ...?extra,
    });
    if (body != null) req.body = body;
    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 45)),
    );
    if (res.statusCode >= 300 &&
        !(method == 'MKCOL' && res.statusCode == 405)) {
      throw ApiError(
        res.statusCode,
        'WebDAV $method 失败（${res.statusCode}），请检查目录、权限和密码',
      );
    }
    if (res.bodyBytes.length > 30 * 1024 * 1024) {
      throw const FormatException('备份超过 30 MB，请使用桌面工具处理');
    }
    return res;
  }

  Future<void> backup({bool automatic = false}) async {
    if (backupRunning) {
      state['backupDirty'] = true;
      return;
    }
    backupRunning = true;
    changed();
    backupTimer?.cancel();
    backupBurst = null;
    var revision = state['dataRevision'] ?? 0;
    final device = state['backupDevice'] ??= uuid.v4();
    final now = DateTime.now().toUtc();
    final id =
        '${now.toIso8601String().replaceAll(':', '-')}-$device-${uuid.v4()}';
    Directory? temp;
    try {
      await dav('MKCOL', '/yousu');
      temp = await Directory.systemTemp.createTemp('youshu-backup-');
      final file = File(p.join(temp.path, 'snapshot.json'));
      revision = state['dataRevision'] ?? 0;
      final draftList = state['importDrafts'];
      final details = await compute(_writeBackupFile, (
        await _committedBackup(now),
        file.path,
      ));
      await davFile('PUT', '/yousu/$id.json', file);
      final manifest = {
        'schema': 5,
        'file': '$id.json',
        'sha256': details['sha256'],
        'bytes': details['bytes'],
        'createdAt': now.toIso8601String(),
        'device': device,
        'platform': Platform.operatingSystem,
        'trigger': automatic ? 'auto' : 'manual',
      };
      final downloaded = File(p.join(temp.path, 'verify.json'));
      await davFile('GET', '/yousu/$id.json', downloaded);
      if (await _hashFile(downloaded) != details['sha256']) {
        throw const FormatException('备份校验失败');
      }
      await dav(
        'PUT',
        '/yousu/$id.manifest.json',
        body: jsonEncode(manifest),
        extra: {'Content-Type': 'application/json', 'If-None-Match': '*'},
      );
      state['lastBackup'] = DateTime.now().toIso8601String();
      state['backupDay'] = today();
      state['backupDirty'] =
          (state['dataRevision'] ?? 0) != revision ||
          !identical(state['importDrafts'], draftList);
      state['backupError'] = '';
      await persist(preferencesOnly: true);
      // This version is already verified and published. Retention errors
      // should leave old versions in place without marking this write failed.
      try {
        await pruneBackups();
      } catch (_) {
        /* Retry retention after the next successful backup. */
      }
    } catch (e) {
      state['backupDirty'] = true;
      state['backupError'] = e.toString();
      await persist(preferencesOnly: true);
      rethrow;
    } finally {
      backupRunning = false;
      if (temp != null) await temp.delete(recursive: true);
      notifyListeners();
    }
  }

  Future<void> davFile(
    String method,
    String path,
    File file, {
    int maxBytes = 30 * 1024 * 1024,
  }) async {
    final settings = await davSettings();
    if (settings['url'] == null) throw const FormatException('请先设置 WebDAV');
    final client = http.Client();
    try {
      final request = http.StreamedRequest(
        method,
        Uri.parse('${settings['url']}$path'),
      )..followRedirects = false;
      request.headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${settings['name']}:${settings['password']}'))}';
      Future<void>? feed;
      if (method == 'PUT') {
        request.contentLength = await file.length();
        if (request.contentLength! > maxBytes) {
          throw FormatException('备份超过 ${maxBytes ~/ (1024 * 1024)} MB 上限');
        }
        request.headers.addAll({
          'Content-Type': 'application/json',
          'If-None-Match': '*',
        });
        feed = request.sink
            .addStream(file.openRead())
            .then((_) => request.sink.close());
      } else {
        request.sink.close();
      }
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode >= 300) {
        throw ApiError(response.statusCode, '备份传输失败');
      }
      if (method == 'GET') {
        var size = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 60),
          )) {
            size += chunk.length;
            if (size > maxBytes) {
              throw FormatException('备份超过 ${maxBytes ~/ (1024 * 1024)} MB');
            }
            sink.add(chunk);
          }
        } finally {
          await sink.close();
        }
      } else {
        await response.stream.drain<void>();
        await feed;
      }
    } finally {
      client.close();
    }
  }

  Future<List<String>> backups() async {
    final res = await dav(
      'PROPFIND',
      '/yousu/',
      body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>',
      extra: {'Depth': '1', 'Content-Type': 'application/xml'},
    );
    final xml = XmlDocument.parse(res.body);
    final files =
        xml.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'href')
            .map((e) => Uri.decodeComponent(e.innerText.split('/').last))
            .where((s) => RegExp(r'^[\w.\-]+\.manifest\.json$').hasMatch(s))
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return files;
  }

  Future<void> restore(String manifestFile) async =>
      restorePreview(await inspectWebDavBackup(manifestFile));
}

String _mergeViewPreferences((String, String) values) {
  final preferences = jsonDecode(values.$1) as Json;
  preferences.addAll(jsonDecode(values.$2) as Json);
  return jsonEncode(preferences);
}

Json _committedWidgetPayload((Json, String) input) {
  final book = jsonDecode(input.$1['body'] as String) as Json;
  book['entries'] = (input.$1['entries'] as Map).values
      .map((row) => jsonDecode(row['body'] as String))
      .toList();
  book['pending'] = <dynamic>[];
  final store = LedgerStore()
    ..state = {
      'ledgers': [book],
      'active': book['id'],
    };
  final date = input.$2;
  final limit = store.budget(date, '全部');
  final result = <String, dynamic>{
    'ledger': book['name'],
    'expense':
        '${store.currency} ${store.display(store.total(date, 'expense'))}',
    'period': store.period(date).label,
    'remaining': limit > 0
        ? '${store.currency} ${store.display(limit - store.budgetSpent(date))}'
        : '未设预算',
    'updated': DateTime.now().toIso8601String(),
  };
  store.dispose();
  return result;
}

Json restoreBundle(Json data) {
  final copies = validateBackup(data);
  final bookIds = <String, String>{},
      entryIds = <String, Map<String, String>>{};
  for (var i = 0; i < copies.length; i++) {
    final source = data['ledgers'][i] as Json, copy = copies[i];
    bookIds[source['id']] = copy['id'];
    final map = <String, String>{};
    for (var n = 0; n < (source['entries'] as List).length; n++) {
      map[source['entries'][n]['id']] = copy['entries'][n]['id'];
    }
    entryIds[source['id']] = map;
  }
  final drafts = <Json>[];
  for (final raw in data['importDrafts'] as List? ?? []) {
    final draft = Map<String, dynamic>.from(raw as Map);
    if (draft['rows'] is! List || draft['errors'] is! List) {
      throw const FormatException('导入草稿格式无效');
    }
    final ids = entryIds[draft['target']] ?? <String, String>{};
    draft['id'] = uuid.v4();
    draft['target'] = bookIds[draft['target']] ?? '';
    draft['rows'] = [
      for (final rawRow in draft['rows'])
        {
          ...Map<String, dynamic>.from(rawRow),
          for (final key in ['id', 'refund_of', 'existing_id'])
            if (rawRow[key] != null) key: ids[rawRow[key]] ?? rawRow[key],
          if (rawRow['candidates'] is List)
            'candidates': [
              for (final id in rawRow['candidates']) ids[id] ?? id,
            ],
        },
    ];
    drafts.add(draft);
  }
  final history = <Json>[];
  final sourceBooks = {
    for (final raw in (data['ledgers'] as List).cast<Json>()) raw['id']: raw,
  };
  final restoredBooks = {for (final copy in copies) copy['id']: copy};
  for (final raw in (data['importHistory'] as List? ?? []).cast<Json>()) {
    final refs = <String, Json>{};
    for (final source in (raw['refs'] as Map? ?? {}).entries) {
      final old = sourceBooks[source.key],
          copy = restoredBooks[bookIds[source.key]];
      if (old == null || copy == null || source.value is! Map) continue;
      final previous = {
        for (final row in (old['entries'] as List).cast<Json>()) row['id']: row,
      };
      final current = {
        for (final row in (copy['entries'] as List).cast<Json>())
          row['id']: row,
      };
      final remapped = <String, dynamic>{};
      for (final ref in (source.value as Map).entries) {
        final row = previous[ref.key];
        final next = current[entryIds[source.key]?[ref.key]];
        if (row != null &&
            next != null &&
            _batchFingerprint(row) == ref.value) {
          remapped[next['id']] = _batchFingerprint(next);
        }
      }
      refs[copy['id']] = remapped;
    }
    final memberBooks = {
      ...raw['ledger_ids'] as List? ?? const [],
      ...?(raw['members'] as Map?)?.keys,
      ...?(raw['refs'] as Map?)?.keys,
    };
    final members = <String, List<String>>{};
    for (final id in memberBooks) {
      final book = sourceBooks[id], mappedIds = entryIds[id];
      if (book == null || mappedIds == null) continue;
      members[bookIds[id]!] = [
        for (final member in importBatchMemberIds(raw, book))
          if (mappedIds[member] case final String mapped) mapped,
      ];
    }
    history.add({
      ...raw,
      'batch_id': uuid.v4(),
      'ledger_ids': [
        for (final id in raw['ledger_ids'] as List? ?? [])
          if (bookIds[id] != null) bookIds[id],
      ],
      'members': members,
      if (raw['refs'] is Map) 'refs': refs,
    });
  }
  return {'ledgers': copies, 'drafts': drafts, 'history': history};
}

int entityOrder(Json e) => switch (e['kind']) {
  'ledger_settings' => 0,
  'category' => e['data']['parent_id'] == '' ? 1 : 2,
  'tag' => 3,
  'entry' => isRefund(e['data']) ? 5 : 4,
  _ => 4,
};
List<Json> validateBackup(Json data) {
  if (![1, 2, 3, 4, 5, 6].contains(data['schema']) ||
      data['ledgers'] is! List) {
    throw const FormatException('不支持的备份版本');
  }
  final result = <Json>[];
  for (final raw in data['ledgers']) {
    final source = jsonDecode(jsonEncode(raw)) as Json;
    source['pending'] = <dynamic>[];
    final l = data['schema'] == 1
        ? migrateLedger(source)
        : jsonDecode(jsonEncode(raw)) as Json;
    final settings = settingsOf(l);
    if (!currencies.containsKey(settings['base_currency'])) {
      throw const FormatException('无效基准币');
    }
    final ids = <String>{}, sourceKeys = <String>{};
    final categories = dictionary(l, 'category').map((e) => e['id']).toSet(),
        tags = dictionary(l, 'tag').map((e) => e['id']).toSet();
    if ((settings['budget_excluded_categories'] as List? ?? []).any(
          (id) => !categories.contains(id),
        ) ||
        (settings['budget_excluded_tags'] as List? ?? []).any(
          (id) => !tags.contains(id),
        )) {
      throw const FormatException('预算排除引用缺失');
    }
    final balance = l['balance_exclusions'];
    if (balance != null &&
        (balance is! Map ||
            balance['categories'] is! List ||
            balance['tags'] is! List ||
            (balance['categories'] as List).any(
              (id) => !categories.contains(id),
            ) ||
            (balance['tags'] as List).any((id) => !tags.contains(id)))) {
      throw const FormatException('结余排除引用无效');
    }
    validateLocalSchedules(l);
    final entryIds = <String, String>{
      for (final e in l['entries'])
        if (e['kind'] == 'entry') e['id']: uuid.v4(),
    };
    for (final e in l['entries']) {
      if (!ids.add(e['id'])) throw const FormatException('重复记录');
      final d = e['data'] as Json;
      if (e['deleted'] == true && d['purged'] == true) {
        e['id'] = entryIds[e['id']] ?? e['id'];
        e['revision'] = 0;
        continue;
      }
      if (e['kind'] == 'entry') {
        final sourceKey = d['source_key'] ?? '';
        if (sourceKey is! String ||
            sourceKey.length > 100 ||
            (sourceKey.isNotEmpty && !sourceKeys.add(sourceKey))) {
          throw const FormatException('来源键无效或重复');
        }
        final date = d['date'] as String;
        if (DateTime.tryParse(date) == null ||
            dateKey(DateTime.parse(date)) != date ||
            !['expense', 'income', 'transfer'].contains(d['type']) ||
            d['account'] is! String) {
          throw const FormatException('无效账目日期或类型');
        }
        if (d['amount'] is! int ||
            d['amount'] <= 0 ||
            d['amount'] > 999999999999 ||
            d['amount'] != d['base_amount_minor'] ||
            d['base_currency'] != settings['base_currency'] ||
            !currencies.containsKey(d['original_currency']) ||
            d['original_amount_minor'] is! int ||
            d['original_amount_minor'] <= 0) {
          throw const FormatException('无效金额');
        }
        if (d['fx_mode'] != 'actual' &&
            convertAmount(
                  d['original_amount_minor'],
                  d['original_currency'],
                  d['base_currency'],
                  d['fx_rate'],
                ) !=
                d['amount']) {
          throw const FormatException('汇率快照不一致');
        }
        if (d['type'] != 'transfer' && !categories.contains(d['category_id'])) {
          throw const FormatException('分类引用缺失');
        }
        if ((d['tag_ids'] as List).any((id) => !tags.contains(id))) {
          throw const FormatException('标签引用缺失');
        }
        if (d['type'] == 'transfer' &&
            (d['account'] == d['to_account'] ||
                !currencies.containsKey(d['to_currency']) ||
                d['to_amount_minor'] <= 0)) {
          throw const FormatException('转账信息不完整');
        }
      } else if (e['kind'] == 'budget') {
        if (d['amount'] is! int ||
            d['amount'] < 0 ||
            d['amount'] > 999999999999 ||
            d['base_currency'] != settings['base_currency'] ||
            d['start_date'].compareTo(d['end_date']) >= 0) {
          throw const FormatException('无效预算');
        }
        if (d['category_id'] != '' && !categories.contains(d['category_id'])) {
          throw const FormatException('预算分类缺失');
        }
        final p = BookPeriod(d['start_date'], d['end_date']);
        final overrides = Map<String, int>.from(d['daily_overrides'] ?? {}),
            allocations = Map<String, int>.from(d['daily_allocations'] ?? {});
        if (d['category_id'] != '' &&
            (overrides.isNotEmpty || allocations.isNotEmpty)) {
          throw const FormatException('分类预算不能设置每日额度');
        }
        if (d['category_id'] == '') {
          allocateDays(p, d['amount'], overrides);
          if (allocations.isNotEmpty &&
              (allocations.length != periodDays(p).length ||
                  allocations.keys.any((day) => !p.contains(day)) ||
                  allocations.values.any((n) => n < 0) ||
                  allocations.values.fold<int>(0, (a, b) => a + b) !=
                      d['amount'] ||
                  overrides.entries.any(
                    (e) => allocations[e.key] != e.value,
                  ))) {
            throw const FormatException('每日分配不一致');
          }
        }
      } else if (!['category', 'tag', 'ledger_settings'].contains(e['kind'])) {
        throw const FormatException('不支持的记录类型');
      }
      e['revision'] = 0;
      if (e['kind'] == 'entry') {
        if (isRefund(d)) {
          if (!entryIds.containsKey(d['refund_of'])) {
            throw const FormatException('退款引用缺失');
          }
          d['refund_of'] = entryIds[d['refund_of']];
        }
        e['id'] = entryIds[e['id']];
      }
    }
    for (final plan in localItems(l, 'recurring_plans')) {
      if (plan['status'] == 'active') plan['status'] = 'paused';
    }
    for (final occurrence in localItems(l, 'recurring_occurrences')) {
      occurrence['entry_ids'] = [
        for (final id in occurrence['entry_ids']) entryIds[id] ?? id,
      ];
    }
    invalidateLedger(l);
    final restoredIndex = ledgerIndex(l);
    for (final e in restoredIndex.records.where((e) => isRefund(e['data']))) {
      final d = e['data'], original = restoredIndex.byId[d['refund_of']];
      if (original == null ||
          original['kind'] != 'entry' ||
          original['data']['type'] != 'expense' ||
          isRefund(original['data']) ||
          d['type'] != 'expense' ||
          d['date'].compareTo(original['data']['date']) < 0 ||
          d['category_id'] != original['data']['category_id'] ||
          (restoredIndex.refunds[original['id']] ?? 0) >
              original['data']['amount']) {
        throw const FormatException('退款引用或累计金额无效');
      }
    }
    final origins = l['merge_sources'] as Map? ?? {};
    l['merge_sources'] = {
      for (final e in entryIds.entries)
        e.value: origins[e.key] ?? {'ledger': raw['id'], 'entry': e.key},
    };
    if (l['import_manifest']?['rows'] is Map) {
      l['import_manifest']['rows'] = {
        for (final e in (l['import_manifest']['rows'] as Map).entries)
          (entryIds[e.key] ?? e.key): e.value,
      };
    }
    invalidateLedger(l);
    l['id'] = uuid.v4();
    l['name'] = '${l['name']} · 恢复副本';
    l['shared'] = false;
    l['role'] = 'owner';
    l['pending'] = <dynamic>[];
    l['lastSync'] = '';
    result.add(l);
  }
  if (result.isEmpty) throw const FormatException('备份中没有账本');
  return result;
}

Json _mergeInBackground((List<Json>, Json) input) =>
    composeLedgers(input.$1, input.$2, deduplicate: true);

Json _viewInBackground((List<Json>, Json) input) =>
    composeLedgers(input.$1, input.$2);
