import 'package:flutter/material.dart';

import 'models.dart';

const _seed = Color(0xFF5B5BD6);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
  );
}

class PriorityChip extends StatelessWidget {
  const PriorityChip(this.priority, {super.key, this.dense = false});
  final Priority priority;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = priority.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(priority.icon, size: dense ? 12 : 14, color: c),
        const SizedBox(width: 3),
        Text(priority.label,
            style: TextStyle(
                color: c, fontWeight: FontWeight.w600, fontSize: dense ? 11 : 12)),
      ]),
    );
  }
}

/// Segmented priority picker used on both platforms.
class PriorityPicker extends StatelessWidget {
  const PriorityPicker({super.key, required this.value, required this.onChanged});
  final Priority value;
  final ValueChanged<Priority> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final p in Priority.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == p ? p.color : p.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.color.withValues(alpha: 0.7)),
                  ),
                  child: Column(children: [
                    Icon(p.icon, size: 18, color: value == p ? Colors.white : p.color),
                    Text(p.label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: value == p ? Colors.white : p.color)),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
