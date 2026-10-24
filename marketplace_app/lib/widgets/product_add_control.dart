import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/mobile.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'customise_sheet.dart';

/// The add-to-cart control you meet on every product in a shopping app: a small
/// "ADD" that turns into "- 2 +" once the item is in the cart.
///
/// Products that need a choice first (several variants, or a required option
/// like Half / Full plate) open a "customise" sheet right where the shopper is,
/// because adding "something" would be a guess. Everything else adds in place.
/// It reads the cart itself, so every card and row agrees.
class ProductAddControl extends StatelessWidget {
  final Product product;

  /// "ADD" text pill (lists, restaurant style) or a square "+" (grid cards).
  final bool pill;

  /// Replaces the customise sheet (tests, or a screen that wants the page).
  final VoidCallback? onOpen;

  /// Replaces the default add (tests, or a screen that wants its own message).
  final VoidCallback? onAdd;

  /// A narrower stepper, for grid cards where the price shares the row.
  final bool compact;

  /// False when the shop is closed: shows "Closed" instead of an ADD button.
  final bool enabled;

  const ProductAddControl({
    super.key,
    required this.product,
    this.pill = false,
    this.onOpen,
    this.onAdd,
    this.compact = false,
    this.enabled = true,
  });

  bool get _needsChoice =>
      product.variants.length > 1 ||
      product.optionGroups.any((g) => g.required || g.min > 0);

  Future<void> _add(BuildContext context) async {
    DsHaptics.tap();
    if (onAdd != null) return onAdd!();

    // The control turning into "- 1 +" is the confirmation; only a refusal
    // needs saying.
    if (!AppState.instance.addToCart(product)) _maxReached(context);
  }

  void _maxReached(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Maximum available quantity reached')));
  }

  /// Ask what they want, in a sheet over the current list. With [last], the
  /// sheet opens on what was added before so repeating it is one tap.
  void _choose(BuildContext context, {CartLine? last}) {
    DsHaptics.tap();
    if (onOpen != null) return onOpen!();
    showCustomiseSheet(context, product,
        initialVariant: last?.variant, initialSelection: last?.selection);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    if (!enabled) {
      return Text('Closed',
          style: TextStyle(
              fontSize: DsText.xs,
              fontWeight: DsWeight.semibold,
              color: c.inkSubtle));
    }

    if (!product.inStock) {
      return Text('Sold out',
          style: TextStyle(
              fontSize: DsText.xs,
              fontWeight: DsWeight.semibold,
              color: c.inkSubtle));
    }

    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final lines = AppState.instance.cart
            .where((l) => l.product.id == product.id)
            .toList();
        final inCart = lines.fold<int>(0, (s, l) => s + l.quantity);

        if (_needsChoice && inCart == 0) {
          return _Pill(
            tooltip: 'Choose options',
            label: pill ? 'ADD' : null,
            icon: pill ? null : Icons.tune,
            onTap: () => _choose(context),
            caption: pill ? 'customisable' : null,
          );
        }

        if (inCart == 0) {
          return _Pill(
            tooltip: 'Add to cart',
            label: pill ? 'ADD' : null,
            icon: pill ? null : Icons.add,
            onTap: () => _add(context),
          );
        }

        // The shown count is everything of this product in the cart; "-" takes
        // from the line added last, "+" repeats it (or, for a customisable
        // item, reopens the sheet on it so a different choice is one tap away).
        final line = lines.last;
        return _Stepper(
          compact: compact,
          quantity: inCart,
          onMinus: () {
            DsHaptics.select();
            AppState.instance.updateQuantity(line.key, line.quantity - 1);
          },
          onPlus: () {
            if (_needsChoice) return _choose(context, last: line);
            DsHaptics.select();
            if (!AppState.instance.addToCart(product, variant: line.variant)) {
              _maxReached(context);
            }
          },
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final String tooltip;
  final String? label;
  final IconData? icon;
  final String? caption;
  final VoidCallback onTap;

  const _Pill({
    required this.tooltip,
    required this.onTap,
    this.label,
    this.icon,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final isText = label != null;

    final button = Tooltip(
      message: tooltip,
      child: Material(
        color: isText ? c.surface : c.accent,
        borderRadius: DsRadius.controlAll,
        child: InkWell(
          borderRadius: DsRadius.controlAll,
          onTap: onTap,
          child: Container(
            width: isText ? 76 : 36,
            height: isText ? 34 : 36,
            alignment: Alignment.center,
            decoration: isText
                ? BoxDecoration(
                    borderRadius: DsRadius.controlAll,
                    border: Border.all(color: c.accent),
                  )
                : null,
            child: isText
                ? Text(label!,
                    style: TextStyle(
                        fontSize: DsText.sm,
                        fontWeight: DsWeight.bold,
                        color: c.accent))
                : Icon(icon, size: 20, color: c.onAccent),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(caption!,
                style: TextStyle(fontSize: 9, color: c.inkSubtle)),
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final bool compact;

  const _Stepper(
      {required this.quantity,
      required this.onMinus,
      required this.onPlus,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    Widget button(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: DsRadius.controlAll,
            onTap: onTap,
            child: SizedBox(
                width: compact ? 26 : 32,
                height: 34,
                child: Icon(icon, size: 18, color: c.onAccent)),
          ),
        );

    return Container(
      height: 34,
      decoration: BoxDecoration(
          color: c.accent, borderRadius: DsRadius.controlAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove, 'Remove one', onMinus),
          Container(
            constraints: BoxConstraints(minWidth: compact ? 16 : 20),
            alignment: Alignment.center,
            child: Text('$quantity',
                style: TextStyle(
                    fontSize: DsText.sm,
                    fontWeight: DsWeight.bold,
                    color: c.onAccent)),
          ),
          button(Icons.add, 'Add one more', onPlus),
        ],
      ),
    );
  }
}
