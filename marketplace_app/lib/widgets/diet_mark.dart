import 'package:flutter/material.dart';

import '../design/theme.dart';

/// The small square mark food shoppers look for: a green dot for vegetarian, red
/// for non-vegetarian, amber for "contains egg". Draws nothing for an item that
/// has no mark (salt, soap, a shirt), so it is safe to put beside every title.
class DietMark extends StatelessWidget {
  final String? diet;
  final double size;

  const DietMark(this.diet, {super.key, this.size = 14});

  /// Whether [diet] is one of the three marks the API sends.
  static bool isKnown(String? diet) => diet == 'veg' || diet == 'non_veg' || diet == 'egg';

  static String labelOf(String? diet) => switch (diet) {
        'veg' => 'Vegetarian',
        'egg' => 'Contains egg',
        'non_veg' => 'Non-vegetarian',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    if (!isKnown(diet)) return const SizedBox.shrink();
    final c = context.ds;
    final color = switch (diet) {
      'veg' => c.success,
      'egg' => c.warning,
      _ => c.danger,
    };

    return Semantics(
      label: labelOf(diet),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Container(
          width: size * 0.5,
          height: size * 0.5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
