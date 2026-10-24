import 'package:flutter/material.dart';

import '../data/bundles.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../screens/product_detail_screen.dart';
import '../state/app_state.dart';

/// "Buy together and save" card for the product the shopper is looking at.
class BundleOfferCard extends StatelessWidget {
  final Bundle bundle;
  final Product current;
  final Variant? currentVariant;

  const BundleOfferCard({
    super.key,
    required this.bundle,
    required this.current,
    this.currentVariant,
  });

  /// The partner's variant to add automatically, or null when the shopper has
  /// to choose (several in stock) or it cannot be bought (none in stock).
  Variant? _partnerVariant(Product partner) {
    final inStock = partner.variants.where((v) => v.stock > 0).toList();
    return inStock.length == 1 ? inStock.first : null;
  }

  Future<void> _addBoth(BuildContext context) async {
    final state = AppState.instance;
    final partner = bundle.partnerOf(current.id);
    final messenger = ScaffoldMessenger.of(context);

    final partnerVariant = _partnerVariant(partner);
    if (partnerVariant == null) {
      // Several options (or none): the partner's own page is where that is chosen.
      messenger.showSnackBar(SnackBar(
        content: Text(partner.variants.any((v) => v.stock > 0)
            ? 'Choose an option for ${partner.title} to add the bundle'
            : '${partner.title} is out of stock'),
      ));
      if (partner.variants.any((v) => v.stock > 0)) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ProductDetailScreen(productId: partner.id)));
      }
      return;
    }

    final first = state.addToCart(current, variant: currentVariant);
    final second = state.addToCart(partner, variant: partnerVariant);
    messenger.showSnackBar(SnackBar(
      content: Text(first && second
          ? 'Bundle added — you save ${formatMoney(bundle.savings)}'
          : 'Could not add the full bundle (maximum quantity reached)'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final partner = bundle.partnerOf(current.id);
    final canBuy = current.inStock && partner.inStock;

    Widget thumb(Product p) => Expanded(
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: DsRadius.cardAll,
                  child: Image.network(
                    p.image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: c.surfaceSunken),
                  ),
                ),
              ),
              const SizedBox(height: DsSpace.s2),
              Text(p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: DsText.xs,
                      fontWeight: DsWeight.semibold,
                      color: c.ink)),
            ],
          ),
        );

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_offer_outlined, size: 18, color: c.accent),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: Text('Buy together & save',
                    style: TextStyle(
                        fontSize: DsText.md,
                        fontWeight: DsWeight.black,
                        color: c.ink)),
              ),
              BxBadge('Save ${formatMoney(bundle.savings)}',
                  tone: BxTone.success),
            ],
          ),
          if (bundle.name.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(bundle.name,
                style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
          ],
          const SizedBox(height: DsSpace.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              thumb(current),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    DsSpace.s2, DsSpace.s6, DsSpace.s2, 0),
                child: Icon(Icons.add, color: c.inkSubtle),
              ),
              thumb(partner),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMoney(bundle.price),
                  style: TextStyle(
                      fontSize: DsText.xl,
                      fontWeight: DsWeight.black,
                      color: c.ink)),
              const SizedBox(width: DsSpace.s2),
              Text(formatMoney(bundle.compareAt),
                  style: TextStyle(
                      fontSize: DsText.base,
                      color: c.inkSubtle,
                      decoration: TextDecoration.lineThrough)),
              const Spacer(),
              BxButton(
                label: canBuy ? 'Add both' : 'Unavailable',
                size: BxButtonSize.sm,
                leadingIcon: Icons.shopping_bag_outlined,
                onPressed: canBuy ? () => _addBoth(context) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
