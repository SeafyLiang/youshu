import 'dart:convert';
import 'dart:typed_data';

import 'gb18030_table.dart';

final _double = ByteData.sublistView(base64Decode(gbDoubleTable));
String decodeGb18030(List<int> bytes) {
  final out = StringBuffer();
  for (var i = 0; i < bytes.length;) {
    final a = bytes[i++];
    if (a < 128) {
      out.writeCharCode(a);
      continue;
    }
    if (a < 0x81 || a > 0xfe || i >= bytes.length) {
      throw const FormatException('GB18030 编码损坏');
    }
    final b = bytes[i++];
    int value = 0;
    if (b >= 0x30 && b <= 0x39) {
      if (i + 1 >= bytes.length) throw const FormatException('GB18030 字符不完整');
      final c = bytes[i++], d = bytes[i++];
      if (c < 0x81 || c > 0xfe || d < 0x30 || d > 0x39) {
        throw const FormatException('GB18030 字符无效');
      }
      final pointer =
          (((a - 0x81) * 10 + b - 0x30) * 126 + c - 0x81) * 10 + d - 0x30;
      var lo = 0, hi = gbRanges.length - 1;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2, r = gbRanges[mid];
        if (pointer < r[0]) {
          hi = mid - 1;
        } else if (pointer > r[1]) {
          lo = mid + 1;
        } else {
          value = r[2] + pointer - r[0];
          break;
        }
      }
    } else if (b >= 0x40 && b <= 0xfe && b != 0x7f) {
      value = _double.getUint32(
        ((a - 0x81) * 191 + b - 0x40) * 4,
        Endian.little,
      );
    }
    if (value == 0) throw const FormatException('GB18030 字符无效');
    out.writeCharCode(value);
  }
  return out.toString();
}
