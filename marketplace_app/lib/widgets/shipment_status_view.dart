import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/delivery_eta.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/mobile.dart';
import 'delivery_route.dart';

/// Tracking for orders that take days, not minutes: where the parcel is, what
/// has happened so far, and when it should arrive - the way courier and
/// marketplace apps show it. No map: a dot crawling across a country for four
/// days tells the shopper nothing the timeline does not.
class ShipmentStatusView extends StatelessWidget {
  final Order order;
  final Map<String, dynamic> rawOrder;
  final TrackingInfo? tracking;
  final String status;
  final EtaSummary eta;
  final bool justPlaced;
  final VoidCallback onBack;
  final VoidCallback onHelp;
  final VoidCallback onOpenDetails;

  const ShipmentStatusView({
    super.key,
    required this.order,
    required this.rawOrder,
    required this.tracking,
    required this.status,
    required this.eta,
    required this.justPlaced,
    required this.onBack,
    required this.onHelp,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final t = tracking;
    final address = rawOrder['shipping_address'];
    final events = t?.events ?? const <ShipmentEvent>[];
    final problem = t?.shipmentStatus == 'DELAYED' ||
        t?.shipmentStatus == 'DELIVERY_FAILED' ||
        t?.shipmentStatus == 'RETURNING';
    final latest = events.isEmpty ? null : events.first;

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: const Text('Track order'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: onBack),
        actions: [
          IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Help',
              onPressed: onHelp),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(DsSpace.s4),
        children: [
          if (justPlaced) ...[
            const BxAlert('We will tell you at every step.',
                title: 'Order placed', tone: BxTone.success),
            const SizedBox(height: DsSpace.s3),
          ],
          BxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.orderNumber,
                    style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                const SizedBox(height: 2),
                Text(
                  eta.headline,
                  style: TextStyle(
                    fontFamily: DsFont.display,
                    fontSize: DsText.xl,
                    fontWeight: DsWeight.bold,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    t?.statusLabel ?? statusHeadline(status),
                    if (eta.detail.isNotEmpty) eta.detail,
                  ].join(' · '),
                  style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                ),
                if (status != 'CANCELLED') ...[
                  const SizedBox(height: DsSpace.s4),
                  DeliveryStages(status: status),
                ],
              ],
            ),
          ),
          if (status == 'CANCELLED') ...[
            const SizedBox(height: DsSpace.s3),
            const BxAlert('This order was cancelled.', tone: BxTone.danger),
          ],
          if (problem) ...[
            const SizedBox(height: DsSpace.s3),
            BxAlert(
              latest?.description?.isNotEmpty == true
                  ? latest!.description!
                  : 'The courier reported a problem with this shipment.',
              title: t!.statusLabel,
              tone: BxTone.warning,
            ),
          ],
          if (latest != null && latest.location.isNotEmpty && status != 'DELIVERED') ...[
            const SizedBox(height: DsSpace.s3),
            _WhereCard(location: latest.location, at: latest.at),
          ],
          const SizedBox(height: DsSpace.s5),
          Text('Updates',
              style: TextStyle(
                  fontSize: DsText.md,
                  fontWeight: DsWeight.bold,
                  color: c.ink)),
          const SizedBox(height: DsSpace.s3),
          if (events.isEmpty)
            Text(
              t?.message ?? 'Updates appear here as soon as the courier scans your parcel.',
              style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
            )
          else
            ShipmentTimeline(events: events),
          if (t != null && (t.courier != null || t.carrierLabel != null || t.trackingNo != null)) ...[
            const SizedBox(height: DsSpace.s5),
            _CourierCard(tracking: t),
          ],
          const SizedBox(height: DsSpace.s5),
          BxCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined,
                    color: c.inkMuted, size: DsTouch.iconSm),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Delivering to',
                          style: TextStyle(
                              fontSize: DsText.sm,
                              fontWeight: DsWeight.bold,
                              color: c.ink)),
                      if (address is Map)
                        Text(
                          [address['line1'], address['line2'], address['city'], address['pincode']]
                              .where((v) => v != null && '$v'.isNotEmpty)
                              .join(', '),
                          style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DsSpace.s3),
          BxCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shopping_bag_outlined,
                    color: c.inkMuted, size: DsTouch.iconSm),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.items.length} ${order.items.length == 1 ? 'item' : 'items'} · ${formatMoney(order.totalAmount)}',
                        style: TextStyle(
                            fontSize: DsText.sm,
                            fontWeight: DsWeight.bold,
                            color: c.ink),
                      ),
                      Text(
                        order.items.map((i) => '${i.title} ×${i.quantity}').join(', '),
                        style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DsSpace.s4),
          BxButton(
            label: 'Order details, receipt & returns',
            variant: BxButtonVariant.secondary,
            fullWidth: true,
            onPressed: onOpenDetails,
          ),
          if (justPlaced) ...[
            const SizedBox(height: DsSpace.s2),
            BxButton(
                label: 'Continue shopping',
                variant: BxButtonVariant.ghost,
                fullWidth: true,
                onPressed: onBack),
          ],
        ],
      ),
    );
  }
}

String _when(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  return DateFormat('d MMM, h:mm a').format(d);
}

/// Newest first, each step with where and when. The latest is drawn solid.
class ShipmentTimeline extends StatelessWidget {
  final List<ShipmentEvent> events;
  const ShipmentTimeline({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == 0 ? c.accent : c.surface,
                          border: Border.all(
                              color: i == 0 ? c.accent : c.lineStrong, width: 2),
                        ),
                      ),
                      if (i < events.length - 1)
                        Expanded(
                            child: Container(width: 2, color: c.line)),
                    ],
                  ),
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: DsSpace.s4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          events[i].label,
                          style: TextStyle(
                            fontSize: DsText.base,
                            fontWeight: i == 0 ? DsWeight.bold : DsWeight.medium,
                            color: c.ink,
                          ),
                        ),
                        if (events[i].location.isNotEmpty)
                          Text(events[i].location,
                              style: TextStyle(
                                  fontSize: DsText.sm, color: c.inkMuted)),
                        if (_when(events[i].at).isNotEmpty)
                          Text(_when(events[i].at),
                              style: TextStyle(
                                  fontSize: DsText.xs, color: c.inkSubtle)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WhereCard extends StatelessWidget {
  final String location;
  final String at;
  const _WhereCard({required this.location, required this.at});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return BxCard(
      child: Row(
        children: [
          CircleAvatar(
              radius: 20,
              backgroundColor: c.accentSoft,
              child: Icon(Icons.place_outlined, color: c.accent, size: 20)),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Last seen',
                    style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                Text(location,
                    style: TextStyle(
                        fontSize: DsText.base,
                        fontWeight: DsWeight.bold,
                        color: c.ink)),
                if (_when(at).isNotEmpty)
                  Text(_when(at),
                      style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CourierCard extends StatelessWidget {
  final TrackingInfo tracking;
  const _CourierCard({required this.tracking});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final name = tracking.carrierLabel ?? tracking.courier ?? 'Courier';
    final awb = tracking.trackingNo;
    final url = tracking.trackUrl;

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  color: c.inkMuted, size: DsTouch.iconSm),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Text(name,
                    style: TextStyle(
                        fontSize: DsText.sm,
                        fontWeight: DsWeight.bold,
                        color: c.ink)),
              ),
            ],
          ),
          if (awb != null) ...[
            const SizedBox(height: DsSpace.s2),
            Row(
              children: [
                Expanded(
                  child: Text('Tracking no. $awb',
                      style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
                ),
                IconButton(
                  tooltip: 'Copy tracking number',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: awb));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tracking number copied')));
                  },
                ),
              ],
            ),
          ],
          if (url != null) ...[
            const SizedBox(height: DsSpace.s1),
            BxButton(
              label: 'Track on $name',
              variant: BxButtonVariant.secondary,
              size: BxButtonSize.sm,
              fullWidth: true,
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
            ),
          ],
        ],
      ),
    );
  }
}
