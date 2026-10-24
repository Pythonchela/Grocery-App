import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/product_options.dart';
import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/mobile_components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import '../widgets/bundle_offer.dart';
import '../widgets/option_picker.dart';
import '../widgets/product_delivery_card.dart';
import '../widgets/product_details_tabs.dart';
import '../widgets/product_gallery.dart';
import '../widgets/shop_switch.dart';
import '../widgets/product_questions.dart';
import '../widgets/product_rail.dart';
import 'cart_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? _product;
  Variant? _variant;
  OptionSelection _selection = OptionSelection.empty;
  List<Map<String, dynamic>> _reviews = [];
  List<Product> _related = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.request('/products/${widget.productId}');
      final product = Product.fromJson(data as Map<String, dynamic>);

      // Reviews are supplementary — a failure there must not blank the page.
      List<Map<String, dynamic>> reviews = [];
      try {
        final r =
            await ApiClient.request('/products/${widget.productId}/reviews');
        final list = r is Map ? r['reviews'] : r;
        if (list is List) reviews = list.cast<Map<String, dynamic>>();
      } catch (_) {}

      List<Product> related = [];
      try {
        final r = await ApiClient.request('/products/${widget.productId}/related');
        related = (r as List)
            .map((p) => Product.fromJson(p as Map<String, dynamic>))
            .toList();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _related = related;
        _product = product;
        _variant = product.variants.where((v) => v.stock > 0).firstOrNull ??
            product.variants.firstOrNull;
        _selection = OptionSelection.defaults(product.optionGroups);
        _reviews = reviews;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addToCart({bool thenCheckout = false}) async {
    final p = _product;
    if (p == null) return;

    final problem = ProductOptionMath.problem(p.optionGroups, _selection);
    if (problem != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    // A different shop's item: ask whether to start a new basket first.
    if (!await confirmShopSwitch(context, p)) return;
    if (!mounted) return;

    final added = AppState.instance
        .addToCart(p, variant: _variant, selection: _selection);
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Maximum available quantity reached'),
      ));
      return;
    }

    if (thenCheckout) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const CartScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.title} added to cart'),
          action: SnackBarAction(
            label: 'View cart',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CartScreen()),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading')),
        body: const Padding(
          padding: EdgeInsets.all(DsSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BxSkeleton(height: 280, radius: DsRadius.cardAll),
              SizedBox(height: DsSpace.s4),
              BxSkeleton(width: 220, height: 22),
              SizedBox(height: DsSpace.s2),
              BxSkeleton(width: 140, height: 18),
            ],
          ),
        ),
      );
    }

    if (_error != null || _product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Product')),
        body: BxEmptyState(
          icon: Icons.error_outline,
          title: 'Could not load this product',
          description: _error,
          action: BxButton(
              label: 'Go back', onPressed: () => Navigator.of(context).pop()),
        ),
      );
    }

    final p = _product!;
    final basePrice = _variant?.price ?? p.price;
    // The price with the shopper's picks on it (portion, add-ons, weight...).
    final price =
        ProductOptionMath.unitPrice(basePrice, p.optionGroups, _selection);
    // A dearer option carries the discount with it, as the server does.
    final mrp = price == basePrice || basePrice <= 0
        ? p.mrp
        : (p.mrp * (price / basePrice)).clamp(price, double.infinity);
    final hasOptions = p.optionGroups.isNotEmpty;
    final inStock = _variant == null ? p.inStock : _variant!.stock > 0;

    // The colour the shopper picked can have pictures of its own.
    final images = (_variant?.images.isNotEmpty ?? false) ? _variant!.images : p.images;
    const gutter = EdgeInsets.symmetric(horizontal: DsSpace.s4);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.brand.isEmpty ? DsBrand.name : p.brand),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_bag_outlined),
            tooltip: 'Cart',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CartScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: DsSpace.s16),
        children: [
          ProductGallery(product: p, variant: _variant, images: images),
          Padding(
            padding: gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: DsSpace.s3),
                if (p.variants.length > 1)
                  VariantPicker(
                    variants: p.variants,
                    selected: _variant,
                    onChanged: (v) => setState(() => _variant = v),
                  ),
                if (hasOptions)
                  OptionPicker(
                    groups: p.optionGroups,
                    selection: _selection,
                    onChanged: (next) => setState(() => _selection = next),
                  ),
                const SizedBox(height: DsSpace.s5),
                if (p.brand.isNotEmpty)
                  Text(p.brand,
                      style: TextStyle(
                          fontSize: DsText.base,
                          fontWeight: DsWeight.bold,
                          color: c.ink)),
                const SizedBox(height: 2),
                Text(
                  p.title,
                  style: TextStyle(
                    fontSize: DsText.md,
                    height: DsText.mdHeight,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: DsSpace.s3),
                Wrap(
                  spacing: DsSpace.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (mrp > price && p.discount > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_downward_rounded, size: 18, color: c.success),
                          Text(
                            '${p.discount}%',
                            style: TextStyle(
                              fontSize: DsText.lg,
                              fontWeight: DsWeight.bold,
                              color: c.success,
                            ),
                          ),
                        ],
                      ),
                    if (mrp > price)
                      Text(
                        formatMoney(mrp),
                        style: TextStyle(
                          fontSize: DsText.md,
                          color: c.inkSubtle,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    Text(
                      formatMoney(price),
                      style: TextStyle(
                          fontSize: DsText.x2xl,
                          fontWeight: DsWeight.black,
                          color: c.ink),
                    ),
                  ],
                ),
                Text('Inclusive of all taxes',
                    style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                if (p.isNew || p.badges.isNotEmpty) ...[
                  const SizedBox(height: DsSpace.s3),
                  Wrap(
                    spacing: DsSpace.s2,
                    runSpacing: DsSpace.s2,
                    children: [
                      if (p.isNew) const BxBadge('NEW', tone: BxTone.newItem),
                      ...p.badges.take(3).map((b) => BxBadge(b)),
                    ],
                  ),
                ],
                const SizedBox(height: DsSpace.s4),
                ProductAssurances(product: p),
                const SizedBox(height: DsSpace.s6),
                ProductDeliveryCard(product: p),
                // Live bundles featuring this product. Re-reads app state so a
                // bundle an admin adds appears without reopening the page.
                AnimatedBuilder(
                  animation: AppState.instance,
                  builder: (context, _) {
                    final bundles = AppState.instance.bundlesFor(p.id);
                    if (bundles.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: DsSpace.s5),
                      child: Column(
                        children: [
                          for (final bundle in bundles)
                            Padding(
                              padding: const EdgeInsets.only(bottom: DsSpace.s3),
                              child: BundleOfferCard(
                                  bundle: bundle, current: p, currentVariant: _variant),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_related.isNotEmpty) ...[
            const SizedBox(height: DsSpace.s6),
            Padding(
              padding: gutter,
              child: Text('Similar products',
                  style: TextStyle(
                      fontSize: DsText.lg,
                      fontWeight: DsWeight.black,
                      color: c.ink)),
            ),
            const SizedBox(height: DsSpace.s3),
            SizedBox(
              height: ProductRail.heightFor(context),
              child: ProductRail(
                products: _related,
                onTap: (rp) => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(productId: rp.id)),
                ),
              ),
            ),
          ],
          Padding(
            padding: gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.features.isNotEmpty) ...[
                  const SizedBox(height: DsSpace.s6),
                  Text('Product highlights',
                      style: TextStyle(
                          fontSize: DsText.lg,
                          fontWeight: DsWeight.black,
                          color: c.ink)),
                  const SizedBox(height: DsSpace.s2),
                  ...p.features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: DsSpace.s2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 16, color: c.success),
                          const SizedBox(width: DsSpace.s2),
                          Expanded(
                            child: Text(f,
                                style: TextStyle(
                                    fontSize: DsText.base, color: c.inkMuted)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: DsSpace.s6),
                ProductDetailsTabs(product: p),
                const SizedBox(height: DsSpace.s6),
                _RatingsHeader(product: p),
                const SizedBox(height: DsSpace.s3),
                if (_reviews.isEmpty)
                  BxCard(
                    child: Text(
                      'No reviews yet. Only customers with a delivered order can review this product.',
                      style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
                    ),
                  )
                else
                  ..._reviews.take(4).map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: DsSpace.s3),
                        child: _ReviewTile(review: r),
                      )),
                const SizedBox(height: DsSpace.s6),
                ProductQuestions(productId: p.id),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BxBottomBar(
        child: Row(
          children: [
            Expanded(
              child: BxButton(
                label: inStock ? 'Add to cart' : 'Out of stock',
                variant: BxButtonVariant.secondary,
                size: BxButtonSize.lg,
                fullWidth: true,
                onPressed: inStock ? () => _addToCart() : null,
              ),
            ),
            const SizedBox(width: DsSpace.s3),
            Expanded(
              child: BxButton(
                label: 'Buy at ${formatMoney(price)}',
                variant: BxButtonVariant.highlight,
                size: BxButtonSize.lg,
                fullWidth: true,
                onPressed:
                    inStock ? () => _addToCart(thenCheckout: true) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Ratings and reviews" with the average, the way marketplace pages open it.
class _RatingsHeader extends StatelessWidget {
  final Product product;

  const _RatingsHeader({required this.product});

  static String _word(double r) => r >= 4.5
      ? 'Excellent'
      : r >= 4
          ? 'Very good'
          : r >= 3
              ? 'Good'
              : r >= 2
                  ? 'Fair'
                  : 'Poor';

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final p = product;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ratings and reviews',
            style: TextStyle(
                fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
        if (p.rating > 0) ...[
          const SizedBox(height: DsSpace.s2),
          Row(
            children: [
              Text(p.rating.toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: DsText.x2xl,
                      fontWeight: DsWeight.black,
                      color: c.ink)),
              const SizedBox(width: 4),
              Icon(Icons.star_rounded, size: 22, color: c.success),
              const SizedBox(width: DsSpace.s2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_word(p.rating),
                    style: TextStyle(
                        fontSize: DsText.xs,
                        fontWeight: DsWeight.bold,
                        color: c.success)),
              ),
            ],
          ),
          Text('based on ${p.reviewsCount} ${p.reviewsCount == 1 ? 'rating' : 'ratings'} by verified buyers',
              style: TextStyle(fontSize: DsText.sm, color: c.inkSubtle)),
        ],
      ],
    );
  }
}

class _ReviewTile extends StatefulWidget {
  final Map<String, dynamic> review;

  const _ReviewTile({required this.review});

  @override
  State<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  late int _helpful = (widget.review['helpful_count'] as num?)?.toInt() ?? 0;
  bool _voted = false;

  Future<void> _vote() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!AppState.instance.isSignedIn) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Sign in from the Account tab to vote')));
      return;
    }
    try {
      final data = await ApiClient.request(
        '/reviews/${widget.review['id']}/vote',
        method: 'POST',
        token: AppState.instance.token,
        body: {'is_helpful': true},
      ) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _voted = true;
        _helpful = (data['helpful_count'] as num?)?.toInt() ?? _helpful + 1;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final c = context.ds;
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final verified = review['is_verified_purchase'] == true;

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ...List.generate(
                5,
                (i) => Icon(
                  i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 15,
                  color: i < rating ? c.rating : c.inkSubtle,
                ),
              ),
              const SizedBox(width: DsSpace.s2),
              if (verified)
                const BxBadge('Verified purchase', tone: BxTone.success),
            ],
          ),
          if ((review['title'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: DsSpace.s2),
            Text(
              review['title'] as String,
              style: TextStyle(
                  fontSize: DsText.base,
                  fontWeight: DsWeight.bold,
                  color: c.ink),
            ),
          ],
          if ((review['body'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: DsSpace.s1),
            Text(
              review['body'] as String,
              style: TextStyle(
                  fontSize: DsText.base,
                  height: DsText.baseHeight,
                  color: c.inkMuted),
            ),
          ],
          const SizedBox(height: DsSpace.s2),
          Align(
            alignment: Alignment.centerLeft,
            child: BxButton(
              label: _voted ? 'Thanks — $_helpful found this helpful' : 'Helpful ($_helpful)',
              variant: BxButtonVariant.link,
              size: BxButtonSize.sm,
              leadingIcon: Icons.thumb_up_alt_outlined,
              onPressed: _voted ? null : _vote,
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
