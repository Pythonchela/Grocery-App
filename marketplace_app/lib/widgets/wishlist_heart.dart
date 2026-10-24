import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/theme.dart';
import '../state/app_state.dart';

/// Save / unsave a product. Reads membership from [AppState] so every heart in
/// the app agrees without each one making its own request.
class WishlistHeart extends StatefulWidget {
  final Product product;
  final Variant? variant;

  /// A round chip suited to sitting on top of a product image.
  final bool overlay;

  const WishlistHeart({
    super.key,
    required this.product,
    this.variant,
    this.overlay = false,
  });

  @override
  State<WishlistHeart> createState() => _WishlistHeartState();
}

class _WishlistHeartState extends State<WishlistHeart> {
  bool _busy = false;

  Future<void> _toggle() async {
    final state = AppState.instance;
    final messenger = ScaffoldMessenger.of(context);
    if (!state.isSignedIn) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Sign in from the Account tab to save items')));
      return;
    }
    setState(() => _busy = true);
    try {
      final saved =
          await state.toggleWishlist(widget.product, variant: widget.variant);
      messenger.showSnackBar(SnackBar(
          content: Text(saved ? 'Saved to your wishlist' : 'Removed from your wishlist')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final saved = AppState.instance.isWishlisted(widget.product.id);
        final icon = Icon(
          saved ? Icons.favorite : Icons.favorite_border,
          size: widget.overlay ? 18 : 24,
          color: saved ? c.danger : c.ink,
        );
        final button = IconButton(
          tooltip: saved ? 'Remove from wishlist' : 'Save to wishlist',
          onPressed: _busy ? null : _toggle,
          visualDensity: widget.overlay ? VisualDensity.compact : null,
          icon: icon,
        );
        if (!widget.overlay) return button;
        return Container(
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: button,
        );
      },
    );
  }
}
