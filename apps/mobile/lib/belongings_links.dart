import 'package:flutter/services.dart';

bool validPurchaseUrl(String value) {
  final uri = Uri.tryParse(value);
  return value.length <= 4096 &&
      !RegExp(r'\s').hasMatch(value) &&
      uri != null &&
      ['https', 'http'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

/// Keeps the original URL, including tracking parameters and order identifiers.
List<String> extractPurchaseUrls(String text) {
  return RegExp(r'''https?://[^\s<>"“”‘’「」【】。，、；！]+''', caseSensitive: false)
      .allMatches(text)
      .map((m) => m.group(0)!.replaceFirst(RegExp(r'[。，、；;！!？?）)\]》]+$'), ''))
      .where(validPurchaseUrl)
      .toSet()
      .toList();
}

Future<void> openPurchaseLink(String value) async {
  if (!validPurchaseUrl(value)) throw const FormatException('购买链接无效');
  final opened = await const MethodChannel('com.seafy.yousu/system')
      .invokeMethod<bool>('openPurchaseLink', value);
  if (opened != true) throw const FormatException('暂时无法打开，请复制链接后重试');
}
