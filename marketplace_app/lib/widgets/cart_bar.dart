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
        final lines = AppState.instance.cart;

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
              borderRadius: DsRadius.pillAll,
              elevation: 4,
              shadowColor: Colors.black38,
              child: InkWell(
                borderRadius: DsRadius.pillAll,
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
                  height: 56,
                  padding: const EdgeInsets.only(left: DsSpace.s2, right: DsSpace.s2),
                  child: Row(
                    children: [
                      // Up to three pictures of what is in the cart, overlapping.
                      SizedBox(
                        width: 28.0 + 20 * (lines.take(3).length - 1).clamp(0, 2),
                        height: 40,
                        child: Stack(
                          children: [
                            for (var i = 0; i < lines.take(3).length; i++)
                              Positioned(
                                left: i * 20.0,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: c.accent, width: 2),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.network(lines[i].product.image,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: DsSpace.s3),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('View cart',
                                maxLines: 1,
                                style: TextStyle(
                                    fontSize: DsText.base, fontWeight: DsWeight.black, color: c.onAccent)),
                            Text(
                              '$count ${count == 1 ? 'item' : 'items'} · ${formatMoney(total)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: DsText.xs, color: c.onAccent.withValues(alpha: 0.9)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: c.onAccent.withValues(alpha: 0.2), shape: BoxShape.circle),
                        child: Icon(Icons.chevron_right, size: 22, color: c.onAccent),
                      ),
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
