import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/shop.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// A shop in a list, the way food and grocery apps show a restaurant: a picture
/// on top, the name with its rating, what it sells, how long it takes and what
/// it asks of an order. A shop that is closed is greyed, with when it opens.
class ShopCard extends StatelessWidget {
  final Shop shop;
  final VoidCallback onTap;

  const ShopCard({super.key, required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final meta = shop.metaLine(formatMoney);

    return Semantics(
      button: true,
      label: '${shop.name}${shop.isOpen ? '' : ', closed'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: DsRadius.cardAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: DsRadius.cardAll,
                child: AspectRatio(
                  aspectRatio: 16 / 8,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ShopPicture(shop: shop, dimmed: !shop.isOpen),
                      if (!shop.isOpen)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: 8),
                            color: c.inverse.withValues(alpha: 0.78),
                            child: Text(
                              [
                                'Closed',
                                if (shop.closedText != null) shop.closedText!,
                              ].join(' · '),
                              style: TextStyle(
                                  fontSize: DsText.sm,
                                  fontWeight: DsWeight.semibold,
                                  color: c.inkInverse),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DsSpace.s2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DsText.md,
                        fontWeight: DsWeight.bold,
                        color: shop.isOpen ? c.ink : c.inkMuted,
                      ),
                    ),
                  ),
                  if (shop.rating > 0) ...[
                    const SizedBox(width: DsSpace.s2),
                    RatingChip(rating: shop.rating),
                  ],
                ],
              ),
              if (shop.subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    shop.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                  ),
                ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    meta,
                    style: TextStyle(fontSize: DsText.sm, color: c.inkSubtle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shop's banner, else its logo on a tinted ground, else its initial.
class ShopPicture extends StatelessWidget {
  final Shop shop;
  final bool dimmed;

  /// Whether a shop with no picture shows its initial. The shop page's header
  /// turns it off, because the shop's name is already written over that spot.
  final bool showInitial;

  const ShopPicture({super.key, required this.shop, this.dimmed = false, this.showInitial = true});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final url = shop.bannerUrl ?? shop.logoUrl;

    Widget fallback() => ColoredBox(
          color: c.accent.withValues(alpha: 0.12),
          child: !showInitial ? null : Center(
            child: Text(
              shop.name.isEmpty ? '?' : shop.name.characters.first.toUpperCase(),
              style: TextStyle(
                  fontSize: 40, fontWeight: DsWeight.black, color: c.accent),
            ),
          ),
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        url == null
            ? fallback()
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback()),
        if (dimmed) ColoredBox(color: c.surface.withValues(alpha: 0.55)),
      ],
    );
  }
}

/// "4.2 ★" on a green chip, the way stores show a rating.
class RatingChip extends StatelessWidget {
  final double rating;

  const RatingChip({super.key, required this.rating});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.success,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rating.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.inkInverse)),
          const SizedBox(width: 2),
          Icon(Icons.star_rounded, size: 12, color: c.inkInverse),
        ],
      ),
    );
  }
}

/// A smaller card for a horizontal rail of shops on the home screen.
class ShopRailCard extends StatelessWidget {
  final Shop shop;
  final VoidCallback onTap;

  const ShopRailCard({super.key, required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return SizedBox(
      width: 168,
      child: InkWell(
        onTap: onTap,
        borderRadius: DsRadius.cardAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: DsRadius.cardAll,
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: ShopPicture(shop: shop, dimmed: !shop.isOpen),
              ),
            ),
            const SizedBox(height: 6),
            Text(shop.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: DsText.base,
                    fontWeight: DsWeight.bold,
                    color: shop.isOpen ? c.ink : c.inkMuted)),
            Text(
              shop.isOpen ? (shop.subtitle.isEmpty ? 'Open' : shop.subtitle) : (shop.closedText ?? 'Closed'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
