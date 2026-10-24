import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import 'product_add_control.dart';

/// A product as a row, the way restaurant and grocery apps list them: picture
/// on the left; name, what it is, rating and a line of description in the
/// middle; price and an ADD button at the bottom. Denser and easier to scan than
/// a grid when there are many items.
class ProductListRow extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  /// False when the shop is closed, so the row cannot be added to a basket.
  final bool canAdd;

  const ProductListRow(
      {super.key, required this.product, required this.onTap, this.canAdd = true});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final soldOut = !product.inStock;
    final meta = [
      if (product.brand.isNotEmpty) product.brand,
      if (product.categoryName != null && product.categoryName!.isNotEmpty)
        product.categoryName!,
    ].join(' · ');
    final hasRating = product.rating > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: DsSpace.s4, vertical: DsSpace.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: DsRadius.controlAll,
              child: SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: c.surfaceSunken),
                    Image.network(
                      product.image,
                      fit: BoxFit.cover,
                      color: soldOut ? c.surface.withValues(alpha: 0.55) : null,
                      colorBlendMode: soldOut ? BlendMode.srcATop : null,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.image_not_supported_outlined,
                          color: c.inkSubtle),
                    ),
                    if (product.discount > 0 && !soldOut)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(DsRadius.chip),
                            ),
                          ),
                          child: Text('-${product.discount}%',
                              style: TextStyle(
                                  fontSize: DsText.x2xs,
                                  fontWeight: DsWeight.bold,
                                  color: c.onAccent)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: DsSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DsText.base,
                      height: 1.3,
                      fontWeight: DsWeight.bold,
                      color: c.ink,
                    ),
                  ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: DsText.xs, color: c.inkSubtle)),
                    ),
                  if (hasRating || product.isNew)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (hasRating) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.success,
                                borderRadius:
                                    BorderRadius.circular(DsRadius.chip),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(product.rating.toStringAsFixed(1),
                                      style: TextStyle(
                                          fontSize: DsText.x2xs,
                                          fontWeight: DsWeight.bold,
                                          color: c.onPrimary)),
                                  Icon(Icons.star_rounded,
                                      size: 11, color: c.onPrimary),
                                ],
                              ),
                            ),
                            if (product.reviewsCount > 0)
                              Text('(${product.reviewsCount})',
                                  style: TextStyle(
                                      fontSize: DsText.xs, color: c.inkSubtle)),
                          ],
                          if (product.isNew)
                            const BxBadge('NEW', tone: BxTone.newItem),
                        ],
                      ),
                    ),
                  if (product.description.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        product.description.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: DsText.xs,
                            height: 1.35,
                            color: c.inkMuted),
                      ),
                    ),
                  const SizedBox(height: DsSpace.s2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              formatMoney(product.price),
                              style: TextStyle(
                                fontSize: DsText.md,
                                fontWeight: DsWeight.bold,
                                color: soldOut ? c.inkSubtle : c.ink,
                              ),
                            ),
                            if (product.mrp > product.price)
                              Text(
                                formatMoney(product.mrp),
                                style: TextStyle(
                                  fontSize: DsText.xs,
                                  color: c.inkSubtle,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: DsSpace.s2),
                      ProductAddControl(product: product, pill: true, enabled: canAdd),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
