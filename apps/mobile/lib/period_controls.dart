import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui.dart';

Future<String?> chooseMonth(BuildContext context, String selected) async {
  final initial =
      DateTime.tryParse(selected.length == 7 ? '$selected-01' : selected) ??
      DateTime.now();
  var year = initial.year;
  bool years = false;
  return glassSheet<String>(
    context,
    StatefulBuilder(
      builder: (c, set) => Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => set(() => year--),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => set(() => years = !years),
                  child: Text('$year 年', style: const TextStyle(fontSize: 20)),
                ),
              ),
              IconButton(
                onPressed: () => set(() => year++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Expanded(
            child: years
                ? YearPicker(
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                    selectedDate: DateTime(year),
                    onChanged: (v) => set(() {
                      year = v.year;
                      years = false;
                    }),
                  )
                : GridView.count(
                    crossAxisCount: 3,
                    childAspectRatio: 1.65,
                    padding: const EdgeInsets.all(16),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: [
                      for (var m = 1; m <= 12; m++)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                initial.year == year && initial.month == m
                                ? Theme.of(c).colorScheme.primaryContainer
                                : null,
                          ),
                          onPressed: () => Navigator.pop(
                            c,
                            '$year-${m.toString().padLeft(2, '0')}',
                          ),
                          child: Text('$m 月'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
    height: .58,
  );
}

Color balanceHeat(BuildContext c, int value, int maxAbs) {
  if (value == 0 || maxAbs == 0) {
    return Theme.of(c).colorScheme.surfaceContainerLow;
  }
  final ratio = (math.log(1 + value.abs()) / math.log(1 + maxAbs)).clamp(
    0.0,
    1.0,
  );
  final ink = value > 0 ? const Color(0xFFE57954) : const Color(0xFF508DCF);
  return Color.alphaBlend(
    ink.withValues(alpha: .12 + .48 * ratio),
    Theme.of(c).colorScheme.surface,
  );
}

class PeriodSwipe extends StatelessWidget {
  final Widget child;
  final ValueChanged<int> onChange;
  const PeriodSwipe({super.key, required this.child, required this.onChange});
  @override
  Widget build(BuildContext c) {
    double distance = 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => distance = 0,
      onHorizontalDragUpdate: (d) => distance += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final velocity = d.primaryVelocity ?? 0;
        if (distance.abs() > 40 || velocity.abs() > 180) {
          onChange((distance.abs() > 40 ? distance : velocity) < 0 ? 1 : -1);
        }
      },
      child: child,
    );
  }
}
