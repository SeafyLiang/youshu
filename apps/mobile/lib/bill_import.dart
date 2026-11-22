import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;

import 'domain.dart';

const maxImportBytes = 20 * 1024 * 1024;

class ImportRow {
  final String sourceId,
      sheet,
      dateTime,
      type,
      parent,
      category,
      currency,
      account,
      note;
  final int line, amount;
  final List<String> tags;
  final Json original;
  final String review;
  ImportRow({
    required this.sourceId,
    required this.sheet,
    required this.line,
    required this.dateTime,
    required this.type,
    required this.parent,
    required this.category,
    required this.currency,
    required this.account,
    required this.note,
    required this.amount,
    required this.tags,
    required this.original,
    this.review = '',
  });
  String get id => categoryId('import', 'entry', sourceId);
}

class ImportPreview {
  final String filename, digest;
  final List<ImportRow> rows;
  final List<String> errors;
  final int sourceCount;
  ImportPreview(
    this.filename,
    this.digest,
    this.rows,
    this.errors,
    this.sourceCount,
  );
  List<ImportRow> get valid => rows.where((e) => e.amount > 0).toList();
  List<ImportRow> get zeroRows => rows.where((e) => e.amount == 0).toList();
  Set<String> get currencyCodes => valid.map((e) => e.currency).toSet();
  int total(String currency, String type) => valid
      .where((e) => e.currency == currency && e.type == type)
      .fold(0, (sum, e) => sum + e.amount);
}

Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
String _attr(XmlElement e, String name) =>
    e.attributes.where((a) => a.name.local == name).firstOrNull?.value ?? '';

/// 只读取单元格缓存值；不执行公式、宏，不访问外部链接，不解压到磁盘。
ImportPreview parseBillXlsx(Uint8List bytes, String filename) {
  if (bytes.isEmpty || bytes.length > maxImportBytes) {
    throw const FormatException('请选择不超过 20 MB 的 XLSX 文件');
  }
  try {
    final headers = ZipDirectory()
        .headers(InputMemoryStream(bytes), verify: true, files: false)
        .toList();
    if (headers.length > 300 ||
        headers.fold<int>(0, (n, h) => n + h.uncompressedSize) >
            64 * 1024 * 1024 ||
        headers.any((h) => h.uncompressedSize > 40 * 1024 * 1024)) {
      throw const FormatException('工作簿展开后过大，请按年份拆分');
    }
    if (headers.map((h) => h.filename).toSet().length != headers.length) {
      throw const FormatException('工作簿存在重复文件');
    }
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    XmlDocument doc(String name) {
      final file = zip.findFile(name);
      if (file == null) throw const FormatException('工作簿结构不完整');
      final xml = utf8.decode(file.content);
      if (xml.contains('<!DOCTYPE') || xml.contains('<!ENTITY')) {
        throw const FormatException('不支持含外部实体的文件');
      }
      return XmlDocument.parse(xml);
    }

    final wb = doc('xl/workbook.xml');
    final date1904 = _elements(
      wb,
      'workbookPr',
    ).any((e) => ['1', 'true'].contains(_attr(e, 'date1904')));
    final rel = {
      for (final e in _elements(
        doc('xl/_rels/workbook.xml.rels'),
        'Relationship',
      ))
        if (_attr(e, 'TargetMode') != 'External')
          _attr(e, 'Id'): _attr(e, 'Target'),
    };
    final strings = zip.findFile('xl/sharedStrings.xml') == null
        ? <String>[]
        : _elements(doc('xl/sharedStrings.xml'), 'si')
              .map((e) => _elements(e, 't').map((t) => t.innerText).join())
              .toList();
    final digest = sha256.convert(bytes).toString();
    final rows = <ImportRow>[], errors = <String>[];
    var count = 0;
    final sheets = _elements(wb, 'sheet').toList();
    final normalized = sheets.any((s) => _attr(s, 'name') == '有数导入');
    final sourceIds = <String>{};
    for (final sheet in sheets) {
      final name = _attr(sheet, 'name');
      if (normalized ? name != '有数导入' : !['支出', '收入'].contains(name)) continue;
      final target = rel[_attr(sheet, 'id')];
      if (target == null) throw const FormatException('工作表关联缺失');
      final file = path.posix.normalize(
        target.startsWith('/') ? target.substring(1) : 'xl/$target',
      );
      if (!file.startsWith('xl/worksheets/')) {
        throw const FormatException('工作表路径不合法');
      }
      List<String>? columns;
      for (final row in _elements(doc(file), 'row')) {
        final line = int.tryParse(_attr(row, 'r')) ?? 0;
        final cells = <int, String>{};
        for (final cell in row.childElements.where(
          (e) => e.name.local == 'c',
        )) {
          final ref = _attr(cell, 'r');
          var index = 0;
          for (final c
              in RegExp(r'^[A-Z]+').stringMatch(ref)?.codeUnits ?? <int>[]) {
            index = index * 26 + c - 64;
          }
          if (index < 1 || index > 64) {
            throw const FormatException('工作表列数超出支持范围');
          }
          var value = _elements(cell, 'v').firstOrNull?.innerText ?? '';
          if (_attr(cell, 't') == 's') {
            final i = int.tryParse(value);
            if (i == null || i < 0 || i >= strings.length) {
              throw const FormatException('字符串引用损坏');
            }
            value = strings[i];
          } else if (_attr(cell, 't') == 'inlineStr') {
            value = _elements(cell, 't').map((t) => t.innerText).join();
          } else if (_attr(cell, 't') == 'd') {
            // OOXML ISO 日期也可能出现浮点导出产生的毫秒尾差；显示/记账精度为秒。
            final parsed = DateTime.tryParse(value);
            if (parsed == null) throw const FormatException('日期单元格损坏');
            value = DateTime.fromMillisecondsSinceEpoch(
              (parsed.millisecondsSinceEpoch / 1000).round() * 1000,
              isUtc: true,
            ).toIso8601String().substring(0, 19).replaceFirst('T', ' ');
          }
          if (value.length > 10000) throw const FormatException('单元格内容过长');
          cells[index - 1] = value;
        }
        if (cells.values.every((v) => v.trim().isEmpty)) continue;
        if (columns == null) {
          columns = List.generate(
            cells.keys.fold(0, (a, b) => a > b ? a : b) + 1,
            (i) => (cells[i] ?? '').trim(),
          );
          if (![
            '交易类型',
            '日期',
            '一级分类',
            '二级分类',
            '账户币种',
            '金额',
            '备注',
          ].every(columns.contains)) {
            throw FormatException('$name 表头不匹配，请使用随手记导出的原始 XLSX');
          }
          continue;
        }
        if (++count > 20000) throw const FormatException('单次最多 20,000 条，请拆分文件');
        final raw = <String, dynamic>{
          for (var i = 0; i < columns.length; i++) columns[i]: cells[i] ?? '',
        };
        String v(String key) => (raw[key] ?? '').toString().trim();
        try {
          final type = {'支出': 'expense', '收入': 'income'}[v('交易类型')];
          if (type == null) throw const FormatException('仅支持支出和收入，不能猜测转账方向');
          final currency = v('账户币种');
          if (!currencies.containsKey(currency)) {
            throw FormatException('不支持币种 $currency');
          }
          final amount = parseAmount(_decimal(v('金额')), currency, zero: true);
          var date = v('日期');
          final serial = double.tryParse(date);
          if (serial != null) {
            date =
                DateTime.utc(
                      date1904 ? 1904 : 1899,
                      date1904 ? 1 : 12,
                      date1904 ? 1 : 30,
                    )
                    .add(Duration(seconds: (serial * 86400).round()))
                    .toIso8601String()
                    .substring(0, 19)
                    .replaceFirst('T', ' ');
          }
          if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
            date = '$date 00:00:00';
          }
          if (RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}$').hasMatch(date)) {
            date = '$date:00';
          }
          date = date.replaceFirst('T', ' ');
          final parsed = DateTime.tryParse(date);
          if (parsed == null ||
              parsed
                      .toIso8601String()
                      .substring(0, 19)
                      .replaceFirst('T', ' ') !=
                  date ||
              parsed.year < 1900 ||
              parsed.year > 2100) {
            throw const FormatException('日期或时间无效');
          }
          final account = v(type == 'income' ? '收入账户' : '支出账户').isNotEmpty
              ? v(type == 'income' ? '收入账户' : '支出账户')
              : v('账户');
          final parent = v('一级分类'), child = v('二级分类');
          if (account.isEmpty ||
              account.length > 50 ||
              parent.isEmpty ||
              parent.length > 50 ||
              child.length > 50 ||
              v('备注').length > 500) {
            throw const FormatException('账户、分类或备注为空/超长，请检查');
          }
          final tags = v('标签')
              .split('|')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList();
          if (tags.length > 40 || tags.any((e) => e.length > 50)) {
            throw const FormatException('标签超过限制');
          }
          final sourceId = v('来源ID').isEmpty
              ? '$digest:$name:$line'
              : v('来源ID');
          if (sourceId.length > 300 || !sourceIds.add(sourceId)) {
            throw const FormatException('来源 ID 重复或过长');
          }
          rows.add(
            ImportRow(
              sourceId: sourceId,
              sheet: name,
              line: line,
              dateTime: date,
              type: type,
              parent: parent,
              category: child.isEmpty ? parent : child,
              currency: currency,
              account: account,
              note: (raw['备注'] ?? '').toString(),
              amount: amount,
              tags: tags,
              original: raw,
              review: v('核对说明'),
            ),
          );
        } catch (e) {
          errors.add(
            '$name 第 $line 行：${e is FormatException ? e.message : '内容无法识别'}',
          );
        }
      }
    }
    if (count == 0) throw const FormatException('未找到支出/收入或有数导入工作表');
    return ImportPreview(filename, digest, rows, errors, count);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('无法读取文件，请使用未加密、完整的 XLSX 文件（不支持 XLS）');
  }
}

// Excel 经常将 45 元保存为 45.0；不对多余的非零小数做静默四舍五入。
String _decimal(String value) {
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
    throw const FormatException('金额须为非负十进制数字');
  }
  if (!value.contains('.')) return value;
  return value
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
