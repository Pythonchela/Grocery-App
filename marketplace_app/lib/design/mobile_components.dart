import 'package:flutter/material.dart';

import 'mobile.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// Components that exist because the app runs on a phone. They are built on the
/// shared tokens (colour, radius, type) and the mobile tokens in `mobile.dart`.

// ─── Pressable ───────────────────────────────────────────────────────────────

/// Anything tappable that is not a button: a card, a row, a tile.
///
/// Guarantees a finger-sized hit area, gives the press a visible response (ink
/// plus a slight settle, since a phone has no hover state to hint at
/// tappability), and optionally ticks the haptic motor.
class BxPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final bool haptic;
  final String? semanticLabel;

  const BxPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = DsRadius.cardAll,
    this.haptic = false,
    this.semanticLabel,
  });

  @override
  State<BxPressable> createState() => _BxPressableState();
}

class _BxPressableState extends State<BxPressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;

    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            minHeight: DsTouch.minTarget, minWidth: DsTouch.minTarget),
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: DsMobileMotion.of(context, DsMobileMotion.instant),
          curve: DsMobileMotion.enter,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: widget.borderRadius,
              onTap: widget.onTap == null
                  ? null
                  : () {
                      if (widget.haptic) DsHaptics.tap();
                      widget.onTap!();
                    },
              onLongPress: widget.onLongPress,
              onHighlightChanged: _set,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom action bar ───────────────────────────────────────────────────────

/// The sticky bar that holds a screen's primary action (Buy now, Checkout,
/// Place order).
///
/// It sits at the bottom because that is where a thumb rests, respects the
/// gesture bar and display cutouts via the safe area, lifts above the keyboard,
/// and is separated from the content with a hairline rather than a shadow so it
/// reads as part of the screen rather than a floating card.
class BxBottomBar extends StatelessWidget {
  final Widget child;
  const BxBottomBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Material(
      color: c.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                DsSpace.s4, DsSpace.s3, DsSpace.s4, DsSpace.s3),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── Quantity stepper ────────────────────────────────────────────────────────

/// "− 2 +" with finger-sized buttons.
///
/// At [minQuantity] the minus becomes a bin, so one control both reduces and
/// removes and the shopper is never left hunting for a separate delete.
class BxQuantityStepper extends StatelessWidget {
  final int quantity;
  final int maxQuantity;
  final int minQuantity;
  final ValueChanged<int> onChanged;

  /// Called instead of [onChanged] when the minus is pressed at [minQuantity].
  final VoidCallback? onRemove;

  const BxQuantityStepper({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.maxQuantity = 20,
    this.minQuantity = 1,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final atMin = quantity <= minQuantity;
    final canRemove = atMin && onRemove != null;

    Widget step(IconData icon, String tooltip, VoidCallback? onTap) => SizedBox(
          width: DsTouch.minTarget,
          height: DsTouch.minTarget,
          child: IconButton(
            icon: Icon(icon, size: DsTouch.iconSm),
            tooltip: tooltip,
            color: c.ink,
            onPressed: onTap == null
                ? null
                : () {
                    DsHaptics.select();
                    onTap();
                  },
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: DsRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          step(
            canRemove ? Icons.delete_outline : Icons.remove,
            canRemove ? 'Remove from cart' : 'Decrease quantity',
            canRemove
                ? onRemove
                : atMin
                    ? null
                    : () => onChanged(quantity - 1),
          ),
          Semantics(
            label: 'Quantity $quantity',
            excludeSemantics: true,
            child: SizedBox(
              width: 28,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: DsText.md,
                  fontWeight: DsWeight.bold,
                  color: c.ink,
                ),
              ),
            ),
          ),
          step(
            Icons.add,
            'Increase quantity',
            quantity >= maxQuantity ? null : () => onChanged(quantity + 1),
          ),
        ],
      ),
    );
  }
}

// ─── Swipe to remove ─────────────────────────────────────────────────────────

/// Swipe a row away to delete it — the gesture phone users already expect from
/// lists. Removal is immediate; the caller is expected to offer Undo, so a
/// stray swipe costs one tap rather than a lost item.
class BxSwipeToRemove extends StatelessWidget {
  final Key dismissKey;
  final Widget child;
  final VoidCallback onRemoved;

  const BxSwipeToRemove({
    super.key,
    required this.dismissKey,
    required this.child,
    required this.onRemoved,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Dismissible(
      key: dismissKey,
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        DsHaptics.warn();
        onRemoved();
      },
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s5),
        decoration: BoxDecoration(
          color: c.danger,
          borderRadius: DsRadius.cardAll,
        ),
        child: Icon(Icons.delete_outline, color: c.onPrimary),
      ),
      child: child,
    );
  }
}

// ─── Sheet handle ────────────────────────────────────────────────────────────

/// The little bar at the top of a bottom sheet that says "this drags".
class BxSheetHandle extends StatelessWidget {
  const BxSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      label: 'Drag to dismiss',
      child: Padding(
        padding: const EdgeInsets.only(top: DsSpace.s2),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.lineStrong,
              borderRadius: DsRadius.pillAll,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Adaptive content width ──────────────────────────────────────────────────

/// Holds content to a comfortable reading width on tablets and wide windows,
/// centred; a no-op on phones.
class BxAdaptiveBody extends StatelessWidget {
  final Widget child;
  const BxAdaptiveBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final max = context.dsWindow.maxContentWidth;
    if (max == double.infinity) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
    );
  }
}

// ─── Total + action ──────────────────────────────────────────────────────────

/// "₹1,048  [ Place order ]" for a bottom bar.
///
/// Side by side when there is room. When the screen is narrow or the shopper
/// has enlarged their text, the total moves above a full-width button instead -
/// squeezing the button into whatever the total leaves behind makes it too small
/// to read or press.
class BxTotalAction extends StatelessWidget {
  final String label;
  final String amount;
  final Widget button;

  const BxTotalAction({
    super.key,
    required this.label,
    required this.amount,
    required this.button,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stacked = scale > 1.3 || MediaQuery.sizeOf(context).width < 340;

    final total = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
        Text(
          amount,
          style: TextStyle(
            fontSize: DsText.lg,
            fontWeight: DsWeight.black,
            color: c.ink,
          ),
        ),
      ],
    );

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label,
                  style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
              const SizedBox(width: DsSpace.s3),
              // Shrinks rather than overflows when the figure is long and the
              // text is large.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    amount,
                    style: TextStyle(
                      fontSize: DsText.lg,
                      fontWeight: DsWeight.black,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s2),
          button,
        ],
      );
    }

    return Row(
      children: [
        total,
        const SizedBox(width: DsSpace.s4),
        Expanded(child: button),
      ],
    );
  }
}

// ─── Bottom navigation ───────────────────────────────────────────────────────

/// One destination in [BxBottomNav].
class BxNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// A count shown on the icon; 0 hides it.
  final int badge;

  const BxNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
  });
}

/// Bottom navigation in the pill style: every tab is just an icon, and the
/// selected one grows into a dark pill carrying its label. It keeps the bar
/// quiet - one word on screen instead of five - while the selected tab is still
/// unmistakable. Every icon keeps its full name for screen readers and long-press.
class BxBottomNav extends StatelessWidget {
  final List<BxNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const BxBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Material(
      color: c.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _NavButton(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final BxNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton(
      {required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final icon = Icon(
      selected ? item.activeIcon : item.icon,
      size: 22,
      color: selected ? c.onPrimary : c.inkMuted,
    );

    final badge = item.badge <= 0
        ? icon
        : Badge(
            label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
            backgroundColor: c.danger,
            textColor: c.onPrimary,
            child: icon,
          );

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        child: AnimatedContainer(
          duration: DsMobileMotion.of(context, DsMobileMotion.standard),
          curve: DsMobileMotion.enter,
          decoration: BoxDecoration(
            color: selected ? c.primary : Colors.transparent,
            borderRadius: DsRadius.pillAll,
          ),
          child: InkWell(
            borderRadius: DsRadius.pillAll,
            onTap: () {
              if (!selected) DsHaptics.select();
              onTap();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  minHeight: DsTouch.minTarget, minWidth: DsTouch.minTarget),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: selected ? DsSpace.s4 : DsSpace.s2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    badge,
                    if (selected) ...[
                      const SizedBox(width: DsSpace.s2),
                      Text(
                        item.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: DsText.sm,
                          fontWeight: DsWeight.semibold,
                          color: c.onPrimary,
                        ),
                      ),
                    ],
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
