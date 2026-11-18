import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'diet_mark.dart';
import 'product_add_control.dart';
import 'wishlist_heart.dart';

/// The commerce composite shared by home, search, category and wishlist.
///
/// This is the mobile twin of `components/ProductCard.jsx`. It is a *composite*,
/// not a primitive — it knows about products, so it lives here rather than in
/// lib/design, exactly as the web keeps ProductCard out of packages/ui.
///
/// Compact on purpose: a picture, a two-line name, the price in the accent
/// colour and one small button. The discount sits on the picture as a square
/// tag, the way shopping apps do.
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
      106 * (MediaQuery.textScalerOf(context).scale(12) / 12);

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final soldOut = !product.inStock;

    return BxCard(
      onTap: onTap,
      padding: const EdgeInsets.all(DsSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
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
                      color: c.surface.withValues(alpha: 0.55),
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(bottom: DsSpace.s2),
                      child:
                          _Tag('Sold out', background: c.ink, color: c.surface),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: WishlistHeart(product: product, overlay: true),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product.discount > 0)
                          _Tag('-${product.discount}%',
                              background: c.accent, color: c.onAccent),
                        if (product.isNew)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: BxBadge('NEW', tone: BxTone.newItem),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DsSpace.s2),
          SizedBox(
              height:
                  MediaQuery.textScalerOf(context).scale(DsText.xs) * 1.35 * 2,
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
          const SizedBox(height: DsSpace.s1),
          // No stars until there is something to say; "★ — (0)" is noise.
          if (product.rating > 0 || product.reviewsCount > 0)
            Row(
              children: [
                Icon(Icons.star_rounded, size: 13, color: c.rating),
                const SizedBox(width: 2),
                Text(
                  product.rating > 0 ? product.rating.toStringAsFixed(1) : '—',
                  style: TextStyle(
                      fontSize: DsText.x2xs,
                      fontWeight: DsWeight.semibold,
                      color: c.ink),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    '(${product.reviewsCount})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle),
                  ),
                ),
              ],
            ),
          const SizedBox(height: DsSpace.s1),
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  // One line always: shrink a long price pair rather than wrap
                  // it and push the card taller than its grid row.
                  child: AnimatedBuilder(
                    animation: AppState.instance,
                    builder: (context, _) {
                      // With "- 2 +" beside it there is no room for the old
                      // price too; the real one stays full size instead.
                      final inCart = AppState.instance.cart
                          .any((l) => l.product.id == product.id);
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                            text: formatMoney(product.price),
                            style: TextStyle(
                                fontSize: DsText.base,
                                fontWeight: DsWeight.bold,
                                color: soldOut ? c.inkSubtle : c.accent),
                          ),
                          if (product.mrp > product.price && !inCart)
                            TextSpan(
                              text: '  ${formatMoney(product.mrp)}',
                              style: TextStyle(
                                fontSize: DsText.x2xs,
                                color: c.inkSubtle,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ])),
                      );
                    },
                  ),
                ),
                if (!soldOut)
                  Padding(
                    padding: const EdgeInsets.only(left: DsSpace.s1),
                    child: ProductAddControl(
                      product: product,
                      compact: true,
                      onAdd: onAddToCart,
                    ),
                  ),
              ],
            ),
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
          borderRadius: BorderRadius.circular(DsRadius.chip),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: DsText.x2xs,
                fontWeight: DsWeight.bold,
                color: color)),
      );
}
