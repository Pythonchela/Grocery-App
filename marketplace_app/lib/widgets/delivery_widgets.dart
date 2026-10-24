import 'package:flutter/material.dart';

import '../data/cart_delivery.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/mobile.dart';
import '../design/mobile_components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// The quick-commerce promise at the top of the cart: how soon, to where.
///
/// Reads like "Delivery in 25 mins" with the shipment size and address beneath,
/// so the shopper knows what they are committing to before they pay.
class DeliveryEtaStrip extends StatelessWidget {
  final CartDelivery delivery;
  final bool signedIn;
  final int itemCount;
  final VoidCallback? onChangeAddress;
  final VoidCallback? onSignIn;

  const DeliveryEtaStrip({
    super.key,
    required this.delivery,
    required this.signedIn,
    required this.itemCount,
    this.onChangeAddress,
    this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final fastest = delivery.fastest;

    late final String title;
    late final String subtitle;
    VoidCallback? onTap;
    var icon = Icons.bolt;

    if (!signedIn) {
      title = 'See your delivery time';
      subtitle = 'Sign in and add an address';
      onTap = onSignIn;
      icon = Icons.schedule;
    } else if (delivery.loading && !delivery.settled) {
      title = 'Finding the fastest delivery…';
      subtitle = 'Checking what is available near you';
      icon = Icons.schedule;
    } else if (!delivery.hasAddress) {
      title = 'Where should we deliver?';
      subtitle = 'Add an address to see delivery time';
      onTap = onChangeAddress;
      icon = Icons.location_on_outlined;
    } else if (fastest == null && delivery.message != null) {
      title = 'These items ship separately';
      subtitle = delivery.message!;
      icon = Icons.call_split;
    } else if (fastest == null) {
      title = 'Delivery not available here yet';
      subtitle = 'Try another address';
      onTap = onChangeAddress;
      icon = Icons.location_off_outlined;
    } else {
      final instant = fastest.etaMinutes > 0 && fastest.etaMinutes <= 120;
      title = etaPhrase(fastest);
      final what = delivery.parcels > 1
          ? '$itemCount ${itemCount == 1 ? 'item' : 'items'} in ${delivery.parcels} parcels'
          : 'Shipment of $itemCount ${itemCount == 1 ? 'item' : 'items'}';
      final where = delivery.address!.tag?.isNotEmpty == true
          ? delivery.address!.tag!
          : delivery.address!.pincode;
      subtitle = '$what · to $where';
      onTap = onChangeAddress;
      icon = instant ? Icons.bolt : Icons.local_shipping_outlined;
    }

    return BxPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(DsSpace.s4),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: DsRadius.cardAll,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
              child: Icon(icon, color: c.accent, size: DsTouch.icon),
            ),
            const SizedBox(width: DsSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: DsFont.display,
                      fontSize: DsText.lg,
                      fontWeight: DsWeight.black,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// The chosen speed as a headline at the top of checkout: "Delivery in 25 mins".
class EtaHero extends StatelessWidget {
  final DeliveryOption option;
  final int itemCount;

  /// Parcels the order ships as (one per seller pickup point).
  final int parcels;

  const EtaHero(
      {super.key, required this.option, required this.itemCount, this.parcels = 1});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final instant = option.etaMinutes > 0 && option.etaMinutes <= 120;
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: DsRadius.cardAll,
      ),
      child: Row(
        children: [
          Icon(instant ? Icons.bolt : Icons.local_shipping_outlined,
              color: c.accent, size: DsTouch.iconLg),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etaPhrase(option),
                  style: TextStyle(
                    fontFamily: DsFont.display,
                    fontSize: DsText.xl,
                    fontWeight: DsWeight.black,
                    color: c.ink,
                  ),
                ),
                Text(
                  parcels > 1
                      ? '$itemCount ${itemCount == 1 ? 'item' : 'items'} in $parcels parcels, from different sellers'
                      : 'Shipment of $itemCount ${itemCount == 1 ? 'item' : 'items'}',
                  style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "You're saving ₹X on this order".
class SavingsBanner extends StatelessWidget {
  final double amount;
  const SavingsBanner({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();
    final c = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DsSpace.s4, vertical: DsSpace.s3),
      decoration: BoxDecoration(
        color: c.successSoft,
        borderRadius: DsRadius.cardAll,
      ),
      child: Row(
        children: [
          Icon(Icons.savings_outlined, color: c.success, size: DsTouch.iconSm),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: "You're saving "),
                  TextSpan(
                    text: formatMoney(amount),
                    style: const TextStyle(fontWeight: DsWeight.black),
                  ),
                  const TextSpan(text: ' on this order'),
                ],
              ),
              style: TextStyle(fontSize: DsText.base, color: c.success),
            ),
          ),
        ],
      ),
    );
  }
}

/// The progress bar towards free delivery - the nudge that turns "I'll just buy
/// this" into "I'll add one more thing".
class FreeDeliveryMeter extends StatelessWidget {
  final double subtotal;
  final double threshold;

  const FreeDeliveryMeter(
      {super.key, required this.subtotal, required this.threshold});

  @override
  Widget build(BuildContext context) {
    if (threshold <= 0) return const SizedBox.shrink();
    final c = context.ds;
    final unlocked = subtotal >= threshold;
    final remaining = (threshold - subtotal).clamp(0, double.infinity);
    final progress = (subtotal / threshold).clamp(0.0, 1.0);

    return BxCard(
      padding: const EdgeInsets.all(DsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unlocked ? Icons.check_circle : Icons.local_shipping_outlined,
                size: DsTouch.iconSm,
                color: unlocked ? c.success : c.accent,
              ),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: Text(
                  unlocked
                      ? 'You have unlocked free delivery'
                      : 'Add ${formatMoney(remaining.toDouble())} more for free delivery',
                  style: TextStyle(
                    fontSize: DsText.base,
                    fontWeight: DsWeight.bold,
                    color: unlocked ? c.success : c.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          Semantics(
            label: 'Free delivery progress',
            value: '${(progress * 100).round()} percent',
            child: ClipRRect(
              borderRadius: DsRadius.pillAll,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: c.surfaceSunken,
                color: unlocked ? c.success : c.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the bill: label on the left, amount on the right, with an
/// optional strike-through original price.
class BillLine extends StatelessWidget {
  final String label;
  final String value;
  final String? strike;
  final Color? valueColor;
  final bool bold;
  final IconData? icon;

  const BillLine(
    this.label,
    this.value, {
    super.key,
    this.strike,
    this.valueColor,
    this.bold = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: c.inkMuted),
          const SizedBox(width: DsSpace.s2),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: bold ? DsText.md : DsText.base,
              fontWeight: bold ? DsWeight.black : DsWeight.medium,
              color: bold ? c.ink : c.inkMuted,
            ),
          ),
        ),
        // Shrinks rather than overflows at large text sizes on narrow phones.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (strike != null) ...[
                  Text(
                    strike!,
                    style: TextStyle(
                      fontSize: DsText.sm,
                      color: c.inkSubtle,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(width: DsSpace.s2),
                ],
                Text(
                  value,
                  style: TextStyle(
                    fontSize: bold ? DsText.md : DsText.base,
                    fontWeight: bold ? DsWeight.black : DsWeight.bold,
                    color: valueColor ?? c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The delivery-speed picker row, quick-commerce style: the time is the
/// headline, the price is secondary.
class DeliverySpeedCard extends StatelessWidget {
  final DeliveryOption option;
  final bool selected;
  final bool fastest;
  final bool cheapest;
  final VoidCallback onTap;

  const DeliverySpeedCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
    this.fastest = false,
    this.cheapest = false,
  });

  IconData get _icon => switch (option.serviceLevel.toUpperCase()) {
        'INSTANT' => Icons.bolt,
        'SAME_DAY' => Icons.electric_moped_outlined,
        'EXPRESS' => Icons.flight_takeoff_outlined,
        'HEAVY' => Icons.local_shipping_outlined,
        _ => Icons.inventory_2_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? c.accentSoft : c.surface,
        borderRadius: DsRadius.cardAll,
        child: InkWell(
          borderRadius: DsRadius.cardAll,
          onTap: () {
            DsHaptics.select();
            onTap();
          },
          child: Ink(
            padding: const EdgeInsets.all(DsSpace.s4),
            decoration: BoxDecoration(
              borderRadius: DsRadius.cardAll,
              border: Border.all(
                  color: selected ? c.accent : c.line, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? c.surface : c.surfaceSunken,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon,
                      color: selected ? c.accent : c.inkMuted,
                      size: DsTouch.icon),
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: DsSpace.s2,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            etaHeadline(option),
                            style: TextStyle(
                              fontFamily: DsFont.display,
                              fontSize: DsText.lg,
                              fontWeight: DsWeight.black,
                              color: c.ink,
                            ),
                          ),
                          if (fastest)
                            const BxBadge('Fastest', tone: BxTone.accent),
                          if (cheapest && !fastest)
                            const BxBadge('Best price', tone: BxTone.success),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: DsText.sm,
                          fontWeight: DsWeight.semibold,
                          color: c.inkMuted,
                        ),
                      ),
                      if (option.freeReason != null)
                        Text(
                          option.freeReason!,
                          style: TextStyle(fontSize: DsText.xs, color: c.success),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: DsSpace.s2),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      option.isFree ? 'Free' : formatMoney(option.price),
                      style: TextStyle(
                        fontSize: DsText.md,
                        fontWeight: DsWeight.black,
                        color: option.isFree ? c.success : c.ink,
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selected ? c.accent : c.lineStrong,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
