import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List fixture(List<List<String>> rows, {String sheetName = '支出'}) {
  String xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final files = {
    'xl/workbook.xml':
        '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="$sheetName" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml':
        '<worksheet><sheetData>${[
          for (var i = 0; i < rows.length; i++) '<row r="${i + 1}">${[for (var j = 0; j < rows[i].length; j++) '<c r="${String.fromCharCode(65 + j)}${i + 1}" t="inlineStr"><is><t>${xml(rows[i][j])}</t></is></c>'].join()}</row>',
        ].join()}</sheetData></worksheet>',
  };
  final archive = Archive();
  for (final f in files.entries) {
    final b = utf8.encode(f.value);
    archive.addFile(ArchiveFile(f.key, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const headings = [
  '交易类型',
  '日期',
  '一级分类',
  '二级分类',
  '支出账户',
  '账户币种',
  '金额',
  '备注',
  '来源ID',
];
List<String> entry({
  String amount = '12.34',
  String date = '2020-02-29 23:59:59',
  String currency = 'CNY',
  String id = '',
}) => ['支出', date, '餐饮', '三餐', '现金', currency, amount, '原始备注', id];
