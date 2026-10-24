import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/mobile.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../screens/cart_screen.dart';
import '../state/app_state.dart';

/// "2 items · ₹300  View cart", pinned above the bottom edge while browsing,
/// like the strip in Swiggy or Blinkit. It appears once something is in the
/// cart and goes away when the cart is empty.
///
/// [onOpen] defaults to pushing the cart; the home shell passes its own so the
/// Cart tab is selected instead of stacking a second cart on top.
class CartBar extends StatelessWidget {
  final VoidCallback? onOpen;

  const CartBar({super.key, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final count = AppState.instance.cartCount;
        if (count == 0) return const SizedBox.shrink();

        final total = AppState.instance.cartSubtotal;

        return SafeArea(
          top: false,
          // The bottom nav sits under this on the home shell and already
          // covers the system inset, so only the pushed screens need it.
          bottom: onOpen == null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                DsSpace.s3, DsSpace.s2, DsSpace.s3, DsSpace.s2),
            child: Material(
              color: c.accent,
              borderRadius: DsRadius.controlAll,
              child: InkWell(
                borderRadius: DsRadius.controlAll,
                onTap: () {
                  DsHaptics.tap();
                  if (onOpen != null) {
                    onOpen!();
                  } else {
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CartScreen()));
                  }
                },
                child: Container(
                  height: DsTouch.minTarget,
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$count ${count == 1 ? 'item' : 'items'} · ${formatMoney(total)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: DsText.base,
                              fontWeight: DsWeight.bold,
                              color: c.onAccent),
                        ),
                      ),
                      Text('View cart',
                          style: TextStyle(
                              fontSize: DsText.base,
                              fontWeight: DsWeight.bold,
                              color: c.onAccent)),
                      const SizedBox(width: DsSpace.s1),
                      Icon(Icons.chevron_right, size: 20, color: c.onAccent),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
