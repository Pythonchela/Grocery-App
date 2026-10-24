import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import 'wishlist_heart.dart';

/// The big picture at the top of a product page: edge to edge, swipeable, with
/// the rating on the picture, share and save buttons in the corner, and a thin
/// segmented bar under it showing which picture you are on.
///
/// When [images] change (the shopper picks another colour) it returns to the
/// first picture of the new set.
class ProductGallery extends StatefulWidget {
  final Product product;
  final Variant? variant;
  final List<String> images;

  const ProductGallery({
    super.key,
    required this.product,
    required this.images,
    this.variant,
  });

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(ProductGallery old) {
    super.didUpdateWidget(old);
    if (!_sameImages(old.images, widget.images)) {
      _index = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  static bool _sameImages(List<String> a, List<String> b) =>
      a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _share() {
    final p = widget.product;
    SharePlus.instance.share(ShareParams(text: '${p.title} - ${formatMoney(p.price)}'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final p = widget.product;
    final images = widget.images;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 4.6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: c.surfaceSunken,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => Image.network(
                    images[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.image_not_supported_outlined, color: c.inkSubtle),
                  ),
                ),
              ),
              Positioned(
                top: DsSpace.s3,
                right: DsSpace.s3,
                child: Column(
                  children: [
                    WishlistHeart(product: p, variant: widget.variant, overlay: true),
                    const SizedBox(height: DsSpace.s2),
                    _RoundButton(icon: Icons.ios_share_outlined, tooltip: 'Share', onTap: _share),
                  ],
                ),
              ),
              if (p.rating > 0)
                Positioned(
                  left: DsSpace.s3,
                  bottom: DsSpace.s3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.rating.toStringAsFixed(p.rating % 1 == 0 ? 0 : 1),
                            style: TextStyle(
                                fontSize: DsText.sm, fontWeight: DsWeight.bold, color: c.ink)),
                        const SizedBox(width: 3),
                        Icon(Icons.star_rounded, size: 15, color: c.success),
                        if (p.reviewsCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(width: 1, height: 12, color: c.lineStrong),
                          const SizedBox(width: 6),
                          Text('${p.reviewsCount}',
                              style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (images.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
            child: Row(
              children: [
                for (var i = 0; i < images.length; i++)
                  Expanded(
                    child: Container(
                      height: 2.5,
                      color: i == _index ? c.ink : c.line,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.surface.withValues(alpha: 0.94),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 21, color: c.ink),
          ),
        ),
      ),
    );
  }
}
