/// Date labels share one year boundary, including yesterday on January 1.
String flowDayLabel(String value, {DateTime? now}) {
  final d = DateTime.parse(value), today = now ?? DateTime.now();
  final current = DateTime(today.year, today.month, today.day);
  final prefix = d.year != today.year
      ? '${d.year} 年 ${d.month} 月 ${d.day} 日'
      : d == current
      ? '今天'
      : d == current.subtract(const Duration(days: 1))
      ? '昨天'
      : '${d.month} 月 ${d.day} 日';
  return '$prefix · 周${['一', '二', '三', '四', '五', '六', '日'][d.weekday - 1]}';
}

String recordDateLabel(String value) {
  final d = DateTime.parse(value);
  return '${d.year}年${d.month}月${d.day}日';
}
