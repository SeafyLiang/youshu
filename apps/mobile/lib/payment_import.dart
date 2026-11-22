import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'bill_import.dart';
import 'domain.dart';
import 'gb18030.dart';

String sourceKey(String platform, String id) =>
    '$platform:${sha256.convert(utf8.encode(id))}';
List<List<String>> readCsv(String text) {
  final rows = <List<String>>[], row = <String>[];
  var cell = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (quoted || cell.isEmpty) {
        quoted = !quoted;
      } else {
        throw const FormatException('CSV 引号不完整');
      }
    } else if (c == ',' && !quoted) {
      row.add(cell.toString());
      cell = StringBuffer();
    } else if ((c == '\n' || c == '\r') && !quoted) {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      rows.add([...row]);
      row.clear();
      cell = StringBuffer();
    } else {
      cell.write(c);
    }
    if (cell.length > 10000 || rows.length > 20100) {
      throw const FormatException('单元格过长或超过20,000笔');
    }
  }
  if (quoted) throw const FormatException('CSV 引号未闭合');
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add([...row]);
  }
  return rows;
}

List<List<String>> readWechatXlsx(Uint8List bytes) {
  final headers = ZipDirectory()
      .headers(InputMemoryStream(bytes), verify: true, files: false)
      .toList();
  if (headers.length > 300 ||
      headers.fold<int>(0, (s, h) => s + h.uncompressedSize) >
          64 * 1024 * 1024 ||
      headers.any((h) => h.uncompressedSize > 40 * 1024 * 1024) ||
      headers.map((h) => h.filename).toSet().length != headers.length) {
    throw const FormatException('工作簿展开后过大或结构无效');
  }
  final zip = ZipDecoder().decodeBytes(bytes, verify: true);
  XmlDocument doc(String name) {
    final f = zip.findFile(name);
    if (f == null) throw const FormatException('工作簿不完整');
    final s = utf8.decode(f.content);
    if (s.contains('<!DOCTYPE') || s.contains('<!ENTITY')) {
      throw const FormatException('不支持外部实体');
    }
    return XmlDocument.parse(s);
  }

  Iterable<XmlElement> els(XmlNode d, String name) =>
      d.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
  final date1904 = els(
    doc('xl/workbook.xml'),
    'workbookPr',
  ).any((e) => ['1', 'true'].contains(e.getAttribute('date1904')));
  final ss = zip.findFile('xl/sharedStrings.xml') == null
      ? <String>[]
      : els(
          doc('xl/sharedStrings.xml'),
          'si',
        ).map((e) => els(e, 't').map((t) => t.innerText).join()).toList();
  for (final f in zip.files.where(
    (f) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name),
  )) {
    final rows = <List<String>>[];
    for (final row in els(doc(f.name), 'row')) {
      final rowNumber =
          int.tryParse(row.getAttribute('r') ?? '') ?? rows.length + 1;
      if (rowNumber > 20100 || rowNumber < 1) {
        throw const FormatException('工作表行数无效');
      }
      while (rows.length < rowNumber - 1) {
        rows.add(<String>[]);
      }
      final values = <int, String>{};
      for (final c in row.childElements.where((e) => e.name.local == 'c')) {
        var ix = 0;
        for (final n
            in (RegExp(r'^[A-Z]+').stringMatch(c.getAttribute('r') ?? '') ?? '')
                .codeUnits) {
          ix = ix * 26 + n - 64;
        }
        if (ix < 1 || ix > 64) throw const FormatException('工作表列数无效');
        if (els(c, 'f').isNotEmpty) throw const FormatException('账单不能包含公式');
        var value = els(c, 'v').firstOrNull?.innerText ?? '';
        if (c.getAttribute('t') == 's') {
          final n = int.tryParse(value);
          if (n == null || n < 0 || n >= ss.length) {
            throw const FormatException('字符串损坏');
          }
          value = ss[n];
        }
        if (c.getAttribute('t') == 'inlineStr') {
          value = els(c, 't').map((e) => e.innerText).join();
        }
        if (value.length > 10000) throw const FormatException('单元格过长');
        values[ix - 1] = value;
      }
      rows.add(
        List.generate(
          values.keys.fold<int>(0, (a, b) => a > b + 1 ? a : b + 1),
          (i) => values[i] ?? '',
        ),
      );
      if (rows.length > 20100) throw const FormatException('单次最多20,000笔');
    }
    final header = rows.indexWhere(
      (r) => r.contains('交易时间') && r.contains('交易单号'),
    );
    if (header >= 0) {
      final column = rows[header].indexOf('交易时间');
      for (final row in rows.skip(header + 1)) {
        if (column >= row.length) continue;
        final serial = double.tryParse(row[column]);
        if (serial == null ||
            !serial.isFinite ||
            serial < 1 ||
            serial > 73415) {
          continue;
        }
        row[column] =
            (date1904 ? DateTime.utc(1904) : DateTime.utc(1899, 12, 30))
                .add(Duration(seconds: (serial * 86400).round()))
                .toIso8601String()
                .substring(0, 19)
                .replaceFirst('T', ' ');
      }
      return rows;
    }
  }
  return [];
}

(String, String) suggestCategory(
  String type,
  String platformCategory,
  String text,
) {
  if (type == 'income') return ('其他收入', '其他待分类');
  final exact = {
    '餐饮美食': ('餐饮', '三餐'),
    '爱车养车': ('交通', '车辆养护'),
    '医疗健康': ('健康', '门诊检查'),
    '数码电器': ('购物', '手机电脑'),
    '运动户外': ('娱乐', '运动健身'),
    '充值缴费': ('居住', '物业宽带'),
    '服饰装扮': ('购物', '服饰鞋包'),
    '日用百货': ('日用', '生活用品'),
  };
  if (exact.containsKey(platformCategory)) return exact[platformCategory]!;
  final rules = {
    '停车': ('交通', '停车路桥'),
    '加油': ('交通', '加油充电'),
    '地铁': ('交通', '公交地铁'),
    '打车': ('交通', '打车租车'),
    '药房': ('健康', '药品'),
    '咖啡': ('餐饮', '咖啡饮品'),
    '水果': ('餐饮', '水果零食'),
    '水费': ('居住', '水电燃气'),
    '电费': ('居住', '水电燃气'),
  };
  final hits = rules.entries
      .where((e) => text.contains(e.key))
      .map((e) => e.value)
      .toSet();
  return hits.length == 1 ? hits.single : ('其他', '待分类');
}

Json parseImportFile((Uint8List, String) input) {
  final bytes = input.$1, name = input.$2;
  if (bytes.isEmpty || bytes.length > maxImportBytes) {
    throw const FormatException('文件不能超过20MB');
  }
  final digest = sha256.convert(bytes).toString();
  List<List<String>> table;
  String platform;
  if (name.toLowerCase().endsWith('.csv')) {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = decodeGb18030(bytes);
    }
    table = readCsv(text.replaceFirst('\ufeff', ''));
    platform = 'alipay';
  } else {
    table = readWechatXlsx(bytes);
    platform = 'wechat';
    if (table.isEmpty) {
      final p = parseBillXlsx(bytes, name);
      return {
        'id': digest,
        'file': name,
        'platform': 'suishouji',
        'errors': p.errors,
        'rows': [
          for (final r in p.rows)
            {
              'key': r.sourceId,
              'id': r.id,
              'dateTime': r.dateTime,
              'type': r.type,
              'parent': r.parent,
              'category': r.category,
              'currency': r.currency,
              'amount': r.amount,
              'account': r.account,
              'note': r.note,
              'tags': r.tags,
              'original': r.original,
              'line': r.line,
              'status': r.amount == 0 ? 'skipped' : 'ready',
              'reason': r.amount == 0 ? '零金额' : r.review,
              'source_status': '',
              'fingerprint': '',
              'refund': false,
              'reviewed': false,
            },
        ],
      };
    }
  }
  final header = table.indexWhere(
    (r) => r.map((c) => c.trim()).contains('交易时间'),
  );
  if (header < 0) throw const FormatException('未识别账单表头');
  final columns = table[header].map((c) => c.trim()).toList();
  final orderKey = platform == 'alipay' ? '交易订单号' : '交易单号',
      amountKey = platform == 'alipay' ? '金额' : '金额(元)',
      stateKey = platform == 'alipay' ? '交易状态' : '当前状态';
  if (!['交易时间', '收/支', orderKey, amountKey, stateKey].every(columns.contains)) {
    throw const FormatException('账单表头不完整');
  }
  final rows = <Json>[], errors = <String>[];
  for (var i = header + 1; i < table.length; i++) {
    final values = table[i];
    if (values.every((v) => v.trim().isEmpty) ||
        values.first.startsWith('---')) {
      continue;
    }
    final raw = <String, dynamic>{
      for (var j = 0; j < columns.length; j++)
        if (columns[j].isNotEmpty)
          columns[j]: j < values.length ? values[j].trim() : '',
    };
    String v(String k) => (raw[k] ?? '').toString();
    try {
      if (v('交易时间').isEmpty) continue;
      final id = v(orderKey),
          date = v('交易时间').replaceFirst('T', ' '),
          parsed = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 19).replaceFirst('T', ' ') !=
              date ||
          parsed.year < 1900 ||
          parsed.year > 2100) {
        throw const FormatException('日期无效');
      }
      if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
        throw const FormatException('订单号缺失或过长');
      }
      final amount = parseAmount(
            v(amountKey).replaceAll(RegExp(r'[¥￥,\s]'), ''),
            'CNY',
            zero: true,
          ),
          state = v(stateKey),
          direction = v('收/支');
      final text = '${v('交易对方')} ${v('商品说明')}${v('商品')}',
          refund =
              direction == '收入' &&
              (v('交易类型').contains('退款') ||
                  state.contains('退款') ||
                  v('交易分类').contains('退款'));
      final type = direction == '收入' ? 'income' : 'expense',
          category = suggestCategory(type, v('交易分类'), text);
      final skip =
          amount == 0 ||
          direction == '不计收支' ||
          direction == '/' ||
          state.contains('关闭') ||
          state.contains('失败') ||
          state.contains('撤销');
      final paid =
          [
            '交易成功',
            '支付成功',
            '等待确认收货',
            '已转账',
            '已存入零钱',
            '对方已收钱',
          ].any(state.contains) ||
          state.contains('退款');
      final key = sourceKey(platform, id),
          fingerprint = sha256
              .convert(utf8.encode('$date|$direction|$amount|CNY'))
              .toString();
      final note = [
        v('商品说明').isEmpty ? v('商品') : v('商品说明'),
        v('交易对方'),
        v('备注'),
      ].where((x) => x.isNotEmpty && x != '/').toSet().join(' · ');
      if (note.length > 500) throw const FormatException('备注超过500字，请拆分核对');
      rows.add({
        'key': key,
        'id': categoryId('import', 'entry', key),
        'dateTime': date,
        'type': type,
        'parent': category.$1,
        'category': category.$2,
        'currency': 'CNY',
        'amount': amount,
        'account': v(platform == 'alipay' ? '收/付款方式' : '支付方式').isEmpty
            ? (platform == 'alipay' ? '支付宝' : '微信')
            : v(platform == 'alipay' ? '收/付款方式' : '支付方式'),
        'note': note,
        'tags': [platform == 'alipay' ? '支付宝' : '微信支付'],
        'merchant': v('交易对方'),
        'original': raw,
        'line': i + 1,
        'source_status': state,
        'fingerprint': fingerprint,
        'refund': refund,
        'refund_of': '',
        'status': skip
            ? 'skipped'
            : refund || !paid
            ? 'review'
            : 'ready',
        'reason': skip
            ? (amount == 0
                  ? '零金额'
                  : direction == '不计收支'
                  ? '不计收支'
                  : '未完成交易')
            : refund
            ? '关联原消费'
            : !paid
            ? '核对交易状态'
            : '',
        'reviewed': false,
      });
    } catch (e) {
      errors.add('第${i + 1}行：${e is FormatException ? e.message : '内容无效'}');
    }
  }
  if (rows.isEmpty && errors.isEmpty) throw const FormatException('没有找到交易记录');
  if (rows.length > 20000) throw const FormatException('单次最多20,000笔');
  return {
    'id': digest,
    'file': name,
    'platform': platform,
    'rows': rows,
    'errors': errors,
  };
}

/// Compact indexed matching runs outside the UI isolate.
Json reviewImport((Json, List<Json>) input) {
  final draft = input.$1,
      existing = input.$2,
      known = <String, Json>{},
      buckets = <String, List<Json>>{};
  for (final e in existing) {
    if ((e['key'] as String? ?? '').isNotEmpty) known[e['key']] = e;
    (buckets['${e['dateTime'].substring(0, 10)}|${e['currency']}|${e['amount']}'] ??=
            [])
        .add(e);
  }
  final all = [...existing, ...(draft['rows'] as List).cast<Json>()];
  final expenses = <String, List<Json>>{}, orders = <String, List<Json>>{};
  for (final e in all) {
    if (e['type'] != 'expense' || e['refund'] == true || e['deleted'] == true) {
      continue;
    }
    (expenses[e['currency']] ??= []).add(e);
    final raw = e['original'] as Map? ?? {},
        order = (raw['交易单号'] ?? raw['交易订单号'] ?? '').toString();
    if (order.isNotEmpty) (orders[order] ??= []).add(e);
  }
  for (final rows in expenses.values) {
    rows.sort((a, b) => b['dateTime'].compareTo(a['dateTime']) as int);
  }
  final batch = <String, Json>{};
  for (final r in (draft['rows'] as List).cast<Json>()) {
    if (r['status'] == 'imported' || r['reviewed'] == true) continue;
    final old = known[r['key']] ?? batch[r['key']];
    batch[r['key']] = r;
    if (old != null) {
      final same =
          (r['fingerprint'] == old['fingerprint'] &&
              r['source_status'] == old['source_status']) ||
          draft['platform'] == 'suishouji';
      r['status'] = same ? 'duplicate' : 'review';
      r['reason'] = same ? '已导入' : '同订单内容或状态变化';
      r['existing_id'] = old['id'];
      continue;
    }
    if (r['status'] == 'skipped') continue;
    if (r['refund'] != true &&
        (r['source_status'] as String? ?? '').contains('退款') &&
        !(draft['rows'] as List).any(
          (x) => x['refund'] == true && x['merchant'] == r['merchant'],
        )) {
      r['status'] = 'review';
      r['reason'] = '消费含退款状态，请补齐退款账单后核对';
    }
    final same =
        buckets['${r['dateTime'].substring(0, 10)}|${r['currency']}|${r['amount']}'] ??
        [];
    final weak = same
        .where((e) => e['type'] == r['type'] && (e['key'] ?? '') != r['key'])
        .toList();
    if (weak.isNotEmpty && !r['refund']) {
      r['status'] = 'review';
      r['reason'] = '疑似已有账目';
      r['candidates'] = weak.map((e) => e['id']).toList();
    }
    if (r['refund'] == true) {
      r['status'] = 'review';
      r['reason'] = '关联原消费';
      final candidates = expenses[r['currency']] ?? <Json>[];
      var lo = 0, hi = candidates.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (candidates[mid]['dateTime'].compareTo(r['dateTime']) > 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      r['candidates'] = candidates
          .skip(lo)
          .take(1000)
          .where(
            (e) =>
                e['type'] == 'expense' &&
                e['deleted'] != true &&
                e['refund'] != true &&
                e['currency'] == r['currency'] &&
                e['amount'] >= r['amount'] &&
                e['dateTime'].compareTo(r['dateTime']) <= 0,
          )
          .map((e) => e['id'])
          .take(100)
          .toList();
      // Only an explicit reference to an original full order number is strong evidence.
      final original = r['original'] as Map,
          references = original.values.join(' ');
      final strong = <String, Json>{};
      for (final token in RegExp(
        r'[A-Za-z0-9_-]{4,100}',
      ).allMatches(references)) {
        for (final e in orders[token.group(0)] ?? <Json>[]) {
          if (e['currency'] == r['currency'] &&
              e['amount'] >= r['amount'] &&
              e['dateTime'].compareTo(r['dateTime']) <= 0) {
            strong[e['id']] = e;
          }
        }
      }
      if (strong.length == 1) {
        r['refund_of'] = strong.values.single['id'];
        r['status'] = 'ready';
        r['reason'] = '已关联原消费';
      }
    }
  }
  return draft;
}
