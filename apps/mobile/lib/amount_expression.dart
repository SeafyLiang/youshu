import 'domain.dart';

/// Evaluate addition/subtraction in minor units, without floating point rounding.
int evaluateAmount(String expression, String currency) {
  final source = expression.replaceAll('−', '-').replaceAll(',', '').trim();
  if (!RegExp(r'^\d+(?:\.\d*)?(?:[+-]\d+(?:\.\d*)?)*$').hasMatch(source)) {
    throw const FormatException('请填写完整的加减金额');
  }
  var total = 0;
  for (final match in RegExp(r'([+-]?)(\d+(?:\.\d*)?)').allMatches(source)) {
    final value = parseAmount(
      match[2]!.endsWith('.') ? '${match[2]}0' : match[2]!,
      currency,
      zero: true,
    );
    total += match[1] == '-' ? -value : value;
  }
  return total;
}

bool validAmountExpression(String value, String currency) {
  if (value.length > 100) return false;
  final precision = currencies[currency] ?? 2;
  final number = precision == 0 ? r'\d*' : '\\d*(?:\\.\\d{0,$precision})?';
  return RegExp('^$number(?:[+-]$number)*\$').hasMatch(value) &&
      !RegExp(r'^[+-]|[+-]{2}').hasMatch(value);
}
