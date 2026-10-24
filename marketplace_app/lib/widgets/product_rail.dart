import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/tokens.g.dart';
import 'product_card.dart';

/// A horizontally scrolling row of product cards.
class ProductRail extends StatelessWidget {
  static const _cardWidth = 150.0;

  /// The row's height, which grows with the system text size.
  static double heightFor(BuildContext context) =>
      _cardWidth + ProductCardTile.extraHeight(context);

  final List<Product> products;
  final void Function(Product) onTap;

  const ProductRail({super.key, required this.products, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: heightFor(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: DsSpace.s3),
        itemBuilder: (context, i) => SizedBox(
          width: _cardWidth,
          child: ProductCardTile(
              product: products[i], onTap: () => onTap(products[i])),
        ),
      ),
    );
  }
}
