import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import 'diet_mark.dart';
import 'product_add_control.dart';
import 'wishlist_heart.dart';

/// The tile every list in the food and grocery app shares: home rails, category grids, search.
///
/// Laid out the way quick-delivery apps do it. A square picture with the ADD button sitting on
/// its lower corner, so adding is one tap without leaving the list; then how soon it is ready,
/// the name, the pack size, and the price. A discount shows as a small flag on the picture.
class ProductCardTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onAddToCart;

  const ProductCardTile({
    super.key,
    required this.product,
    required this.onTap,
    this.onAddToCart,
  });

  /// Height of a card below its (square) picture, for lists that need a fixed
  /// row height. Grows with the system text size.
  static double extraHeight(BuildContext context) =>
      112 * (MediaQuery.textScalerOf(context).scale(12) / 12);

  /// "500 g", "1 L": the pack size, when the product has exactly one and it says something.
  static String? unitOf(Product p) {
    if (p.variants.length == 1) {
      final size = p.variants.first.size.trim();
      if (size.isNotEmpty && !RegExp(r'^(standard|free size)$', caseSensitive: false).hasMatch(size)) {
        return size;
      }
    } else if (p.variants.length > 1) {
      return '${p.variants.length} options';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final soldOut = !product.inStock;
    final unit = unitOf(product);

    return BxCard(
      onTap: onTap,
      padding: const EdgeInsets.all(DsSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: DsRadius.controlAll,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: c.surfaceSunken),
                      Image.network(
                        product.image,
                        fit: BoxFit.cover,
                        // A dead image URL must not paint a broken-image glyph over
                        // the card — degrade to the same sunken surface behind it.
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.image_not_supported_outlined,
                            color: c.inkSubtle,
                            size: 28),
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const BxSkeleton(height: double.infinity),
                      ),
                      if (soldOut)
                        Container(
                          color: c.surface.withValues(alpha: 0.6),
                          alignment: Alignment.center,
                          child: _Tag('Sold out', background: c.ink, color: c.surface),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (product.discount > 0 && !soldOut)
                        _Tag('${product.discount}% OFF', background: c.accent, color: c.onAccent),
                      if (product.isNew)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: BxBadge('NEW', tone: BxTone.newItem),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: WishlistHeart(product: product, overlay: true),
                ),
                // The ADD button overlaps the picture's lower corner, so it is the first thing
                // the thumb reaches. A shopper never has to open the product to buy it.
                if (!soldOut)
                  Positioned(
                    right: 4,
                    bottom: -16,
                    child: Material(
                      color: c.surface,
                      elevation: 1.5,
                      shadowColor: c.ink.withValues(alpha: 0.25),
                      borderRadius: DsRadius.controlAll,
                      child: ProductAddControl(
                        product: product,
                        pill: true,
                        onAdd: onAddToCart,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Room for the ADD button's lower half (and its "customisable" caption).
          const SizedBox(height: DsSpace.s5),
          if (product.prepMinutes > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 11, color: c.inkSubtle),
                  const SizedBox(width: 2),
                  Text('${product.prepMinutes} MIN',
                      style: TextStyle(
                          fontSize: DsText.x2xs,
                          fontWeight: DsWeight.black,
                          letterSpacing: 0.3,
                          color: c.inkSubtle)),
                ],
              ),
            ),
          SizedBox(
              height: MediaQuery.textScalerOf(context).scale(DsText.xs) * 1.35 * 2,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (DietMark.isKnown(product.diet))
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 5),
                      child: DietMark(product.diet, size: 12),
                    ),
                  Expanded(
                    child: Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DsText.xs,
                        height: 1.35,
                        fontWeight: DsWeight.semibold,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              )),
          if (unit != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle)),
            ),
          const Spacer(),
          // One line always: shrink a long price pair rather than wrap it and push the
          // card taller than its grid row.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: formatMoney(product.price),
                style: TextStyle(
                    fontSize: DsText.base,
                    fontWeight: DsWeight.black,
                    color: soldOut ? c.inkSubtle : c.ink),
              ),
              if (product.mrp > product.price)
                TextSpan(
                  text: '  ${formatMoney(product.mrp)}',
                  style: TextStyle(
                    fontSize: DsText.x2xs,
                    color: c.inkSubtle,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ])),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color background;
  final Color color;

  const _Tag(this.label, {required this.background, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(DsRadius.control),
            bottomRight: Radius.circular(DsRadius.chip),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: DsText.x2xs,
                fontWeight: DsWeight.bold,
                color: color)),
      );
}
