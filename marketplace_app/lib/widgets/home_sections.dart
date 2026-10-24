import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/storefront.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'product_rail.dart';

/// Section titles, in the voice the rest of the home screen uses.
class SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const SectionTitle({super.key, required this.title, this.subtitle = ''});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          DsSpace.s4, DsSpace.s5, DsSpace.s4, DsSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: DsFont.display,
              fontSize: DsText.xl,
              fontWeight: DsWeight.black,
              color: c.ink,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
          ],
        ],
      ),
    );
  }
}

/// A full-bleed picture card with a headline over a scrim — used for the hero
/// and for promo banners. Without an image it falls back to the brand gradient,
/// so a section the admin has not finished still looks intentional.
class PictureCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String subtitle;
  final double aspectRatio;
  final VoidCallback? onTap;
  final bool large;

  const PictureCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.subtitle = '',
    this.aspectRatio = 16 / 9,
    this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final hasImage = imageUrl != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, 0),
      child: Semantics(
        button: onTap != null,
        label: title,
        child: ClipRRect(
          borderRadius: DsRadius.panelAll,
          child: Material(
            color: c.inverse,
            child: InkWell(
              onTap: onTap,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasImage)
                      Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [c.accent, c.inverse],
                          ),
                        ),
                      ),
                    // The scrim keeps the headline readable on any photograph and
                    // in either theme; it is not themed because a picture is not.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xCC000000)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(DsSpace.s5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title.isNotEmpty)
                            Text(
                              title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: DsFont.display,
                                fontSize: large ? DsText.x2xl : DsText.xl,
                                height: 1.15,
                                fontWeight: DsWeight.black,
                                color: Colors.white,
                              ),
                            ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: DsSpace.s1),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: DsText.base, color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of products chosen by the admin's `source`.
class ProductRowSection extends StatefulWidget {
  final HomeSection section;
  final List<Category> categories;
  final void Function(Product) onTap;

  const ProductRowSection({
    super.key,
    required this.section,
    required this.categories,
    required this.onTap,
  });

  @override
  State<ProductRowSection> createState() => _ProductRowSectionState();
}

class _ProductRowSectionState extends State<ProductRowSection> {
  List<Product>? _products;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _fallbackTitle => switch (widget.section.source) {
        'new' => 'New arrivals',
        'personalized' => 'Picked for you',
        'deals' => 'Deals',
        'category' => widget.categories
                .where((c) => c.id == widget.section.categoryId)
                .map((c) => c.name)
                .firstOrNull ??
            'Shop now',
        _ => 'Trending now',
      };

  Future<void> _load() async {
    try {
      final token = AppState.instance.token;
      final dynamic data;

      switch (widget.section.source) {
        case 'new':
          data = await ApiClient.request('/products',
              query: {'sort': 'newest', 'per_page': '10'});
        case 'personalized' when token != null:
          data = await ApiClient.request('/recommendations/personalized',
              token: token);
        case 'deals':
          // The API has no "discounted" filter; take a page and keep the
          // products that are actually reduced, biggest saving first.
          final all = await ApiClient.request('/products',
              query: {'per_page': '40'}) as List;
          final products = all
              .map((p) => Product.fromJson(p as Map<String, dynamic>))
              .where((p) => p.discount > 0)
              .toList()
            ..sort((a, b) => b.discount.compareTo(a.discount));
          if (mounted) setState(() => _products = products.take(10).toList());
          return;
        case 'category':
          final slug = widget.categories
              .where((c) => c.id == widget.section.categoryId)
              .map((c) => c.slug)
              .firstOrNull;
          data = slug == null
              ? const []
              : await ApiClient.request('/products',
                  query: {'category': slug, 'per_page': '10'});
        default:
          data = await ApiClient.request('/recommendations/trending');
      }

      if (!mounted) return;
      setState(() => _products = (data as List)
          .map((p) => Product.fromJson(p as Map<String, dynamic>))
          .toList());
    } catch (_) {
      // One failing row must not take the rest of the home page with it.
      if (mounted) setState(() => _products = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    if (products != null && products.isEmpty) return const SizedBox.shrink();

    final title = widget.section.title.isNotEmpty
        ? widget.section.title
        : _fallbackTitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: title, subtitle: widget.section.subtitle),
        if (products == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: DsSpace.s4),
            child: BxSkeleton(height: 220, radius: DsRadius.cardAll),
          )
        else
          ProductRail(products: products, onTap: widget.onTap),
      ],
    );
  }
}

/// Reassurance strip. The admin controls the headline; the points are the
/// marketplace's standing promises.
class TrustStrip extends StatelessWidget {
  final HomeSection section;
  const TrustStrip({super.key, required this.section});

  static const _points = [
    (Icons.verified_outlined, 'Verified reviews', 'Only from delivered orders'),
    (Icons.assignment_return_outlined, 'Easy returns', '7-day return window'),
    (Icons.lock_outline, 'Secure payments', 'UPI, cards and COD'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title.isNotEmpty)
          SectionTitle(title: section.title, subtitle: section.subtitle)
        else
          const SizedBox(height: DsSpace.s4),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
            itemCount: _points.length,
            separatorBuilder: (_, __) => const SizedBox(width: DsSpace.s3),
            itemBuilder: (_, i) => Container(
              width: 200,
              padding: const EdgeInsets.all(DsSpace.s4),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: DsRadius.cardAll,
              ),
              child: Row(
                children: [
                  Icon(_points[i].$1, color: c.accent),
                  const SizedBox(width: DsSpace.s3),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_points[i].$2,
                            style: TextStyle(
                                fontSize: DsText.base,
                                fontWeight: DsWeight.bold,
                                color: c.ink)),
                        Text(_points[i].$3,
                            style: TextStyle(
                                fontSize: DsText.xs, color: c.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Invitation into the reels feed.
class ReelsPromo extends StatelessWidget {
  final HomeSection section;
  final VoidCallback onOpen;

  const ReelsPromo({super.key, required this.section, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s5, DsSpace.s4, 0),
      child: BxCard(
        onTap: onOpen,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration:
                  BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.play_arrow_rounded, color: c.accent, size: 30),
            ),
            const SizedBox(width: DsSpace.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title.isNotEmpty ? section.title : 'Shop by video',
                    style: TextStyle(
                        fontSize: DsText.md,
                        fontWeight: DsWeight.black,
                        color: c.ink),
                  ),
                  Text(
                    section.subtitle.isNotEmpty
                        ? section.subtitle
                        : 'Watch short clips and buy what you see',
                    style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.inkSubtle),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
