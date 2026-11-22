import 'package:flutter/material.dart';

import 'ui.dart';

Color budgetColor(BuildContext context, int spent, int limit) {
  final p = AppPalette.of(context);
  if (limit > 0 && spent > limit) return p.danger;
  if (limit > 0 && spent >= limit * .8) return p.warn;
  return p.brandColor;
}

/// Shared calm reservoir: no stroke on the water surface, flat when full.
class BudgetPool extends StatelessWidget {
  final int spent, limit;
  final Widget child;
  final bool selected;
  const BudgetPool({
    super.key,
    required this.spent,
    required this.limit,
    required this.child,
    this.selected = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final overflow = limit > 0 && spent > limit;
    final warning = limit > 0 && !overflow && spent >= limit * .8;
    final fillColor = overflow
        ? p.waterOver
        : warning
        ? p.waterWarn
        : p.waterOk;
    return Semantics(
      label: limit <= 0
          ? '未设置预算'
          : '${overflow ? '超出预算' : '预算已用'} ${(spent / limit * 100).round()}%',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? p.brandColor : p.border,
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(selected ? 12.5 : 13.2),
          child: CustomPaint(
            painter: _WaterPainter(
              limit <= 0 ? 0 : (spent / limit).clamp(0, 1).toDouble(),
              p.card,
              fillColor,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _WaterPainter extends CustomPainter {
  final double level;
  final Color base;
  final Color fill;
  _WaterPainter(this.level, this.base, this.fill);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    if (level <= 0) return;
    final paint = Paint()..color = fill;
    if (level >= 1) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    final y = size.height * (1 - level);
    final bend = (size.height * .014).clamp(0.0, 1.4);
    final path = Path()
      ..moveTo(0, y)
      ..cubicTo(
        size.width * .33,
        y - bend,
        size.width * .67,
        y + bend,
        size.width,
        y,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaterPainter old) =>
      old.level != level || old.base != base || old.fill != fill;
}
