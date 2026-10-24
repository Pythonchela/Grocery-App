import 'package:flutter/material.dart';

import '../data/product_options.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// What was chosen on a product - "Portion: Full plate", "Leave out: Onion" -
/// as small print under a cart, order or invoice line.
class OptionPicks extends StatelessWidget {
  final List<OptionPick> picks;
  final int maxLines;

  const OptionPicks({super.key, required this.picks, this.maxLines = 4});

  @override
  Widget build(BuildContext context) {
    if (picks.isEmpty) return const SizedBox.shrink();
    final c = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in picks)
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '${p.label}: ',
                  style: TextStyle(color: c.inkSubtle)),
              TextSpan(
                  text: p.removal ? 'no ${p.value}' : p.value,
                  style: TextStyle(
                      color: p.removal ? c.danger : c.inkMuted,
                      fontWeight: DsWeight.medium)),
            ]),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: DsText.xs, height: 1.4),
          ),
      ],
    );
  }
}
