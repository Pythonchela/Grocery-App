import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api_client.dart';
import '../data/delivery_eta.dart';
import '../data/models.dart';
import '../data/order_alerts.dart';
import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/mobile.dart';
import '../design/mobile_components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import '../widgets/delivery_route.dart';
import '../widgets/shipment_status_view.dart';
import 'order_detail_screen.dart';

/// Live order tracking, in the manner of a food-delivery app: a route panel up
/// top with the delivery partner moving along it, and over it a sheet you can
/// drag up for the arrival time, the steps, who is bringing it and what is in it.
class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  /// True straight after checkout: shows the confirmation and, on the way out,
  /// returns to the shop rather than to the checkout that no longer exists.
  final bool justPlaced;

  const OrderTrackingScreen(
      {super.key, required this.orderId, this.justPlaced = false});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Map<String, dynamic>? _order;
  TrackingInfo? _tracking;
  bool _loading = true;
  String? _error;
  Timer? _poll;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    // Re-evaluates "arriving in N mins" between polls without another request.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  String get _status => '${_order?['status'] ?? 'PENDING'}';
  bool get _settled => _status == 'DELIVERED' || _status == 'CANCELLED';

  DateTime? _date(dynamic raw) =>
      raw == null ? null : DateTime.tryParse('$raw')?.toLocal();

  Future<void> _load() async {
    try {
      final data = await ApiClient.request('/orders/${widget.orderId}',
          token: AppState.instance.token) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _order = data;
        _loading = false;
        _error = null;
      });
      await _refreshTracking();
      _afterUpdate();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshTracking() async {
    try {
      final data = await ApiClient.request(
              '/delivery/orders/${widget.orderId}/track',
              token: AppState.instance.token)
          as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _tracking = TrackingInfo.fromJson(data);
        // The courier's own status can run ahead of the order record.
        if (_tracking!.currentStatus == 'DELIVERED' && _status != 'DELIVERED') {
          _order = {...?_order, 'status': 'DELIVERED'};
        }
      });
    } catch (_) {
      // Tracking is supplementary; the order itself is still worth showing.
    }
  }

  /// Keeps polling until the order settles, and rewards a delivery with a
  /// reminder to review it.
  void _afterUpdate() {
    _poll?.cancel();
    if (_status == 'DELIVERED') {
      final number = '${_order?['order_number'] ?? ''}';
      unawaited(OrderAlerts.instance.scheduleReviewReminder(widget.orderId, number));
    }
    if (_settled) return;

    final interval = _tracking?.hasLivePosition == true
        ? const Duration(seconds: 20)
        : const Duration(seconds: 45);
    _poll = Timer(interval, () async {
      await _load();
    });
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the dialler for $phone')));
    }
  }

  Future<void> _help() async {
    final uri = Uri(
      scheme: 'mailto',
      path: DsBrand.supportEmail,
      query: 'subject=${Uri.encodeComponent('Help with order ${_order?['order_number'] ?? ''}')}',
    );
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Write to us at ${DsBrand.supportEmail}')));
    }
  }

  void _leave() {
    if (widget.justPlaced) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tracking')),
        body: const Padding(
          padding: EdgeInsets.all(DsSpace.s4),
          child: Column(children: [
            BxSkeleton(height: 220, radius: DsRadius.cardAll),
            SizedBox(height: DsSpace.s3),
            BxSkeleton(height: 140, radius: DsRadius.cardAll),
          ]),
        ),
      );
    }

    if (_error != null || _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tracking')),
        body: BxEmptyState(
          icon: Icons.error_outline,
          title: 'Could not load this order',
          description: _error,
          action: BxButton(label: 'Try again', onPressed: _load),
        ),
      );
    }

    final order = Order.fromJson(_order!);
    final tracking = _tracking;
    final status = _status;
    final promisedBy = _date(_order!['promised_by'] ?? tracking?.promisedBy);
    final placedAt = _date(_order!['created_at']);
    final eta = describeEta(
      status: status,
      etaMinutes: status == 'DELIVERED' ? null : tracking?.etaMinutes,
      promisedBy: promisedBy,
    );
    final progress = DeliveryProgress.of(status,
        placedAt: placedAt, promisedBy: promisedBy);
    // The server decides: a rider bringing it within hours gets a live map; a
    // parcel in a courier's network gets where-it-is updates and a due date.
    final mode = tracking?.mode ?? '${_order!['tracking_mode'] ?? 'live_map'}';
    if (mode == 'status_updates') {
      final expected = _date(tracking?.expectedBy ?? _order!['promised_by']);
      return PopScope(
        canPop: !widget.justPlaced,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: ShipmentStatusView(
          order: order,
          rawOrder: _order!,
          tracking: tracking,
          status: status,
          eta: describeEta(status: status, promisedBy: expected),
          justPlaced: widget.justPlaced,
          onBack: _leave,
          onHelp: _help,
          onOpenDetails: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: widget.orderId))),
        ),
      );
    }

    final address = _order!['shipping_address'];
    final instructions =
        address is Map ? '${address['instructions'] ?? ''}'.trim() : '';

    return PopScope(
      canPop: !widget.justPlaced,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: c.canvas,
        body: Stack(
          children: [
            // The route panel fills the top of the screen behind the sheet.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: DeliveryRouteMap(
                visibleHeight: MediaQuery.sizeOf(context).height * 0.40,
                progress: progress,
                live: tracking?.hasLivePosition == true && !tracking!.sandbox,
                delivered: status == 'DELIVERED',
                cancelled: status == 'CANCELLED',
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(DsSpace.s2),
                child: Row(
                  children: [
                    _RoundButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Back',
                        onTap: _leave),
                    const Spacer(),
                    _RoundButton(
                        icon: Icons.help_outline, tooltip: 'Help', onTap: _help),
                  ],
                ),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.4,
              maxChildSize: 0.92,
              builder: (context, controller) => DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(DsRadius.panel)),
                  boxShadow: context.dsShadow.card,
                ),
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                      DsSpace.s4, 0, DsSpace.s4, DsSpace.s10),
                  children: [
                    const BxSheetHandle(),
                    const SizedBox(height: DsSpace.s3),
                    if (widget.justPlaced) ...[
                      const BxAlert(
                        'We will tell you at every step.',
                        title: 'Order placed',
                        tone: BxTone.success,
                      ),
                      const SizedBox(height: DsSpace.s4),
                    ],
                    Text(
                      eta.headline,
                      style: TextStyle(
                        fontFamily: DsFont.display,
                        fontSize: DsText.x2xl,
                        fontWeight: DsWeight.black,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusHeadline(status, riderName: tracking?.riderName) +
                          (eta.detail.isEmpty ? '' : ' · ${eta.detail}'),
                      style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
                    ),
                    const SizedBox(height: DsSpace.s5),
                    if (status != 'CANCELLED') DeliveryStages(status: status),
                    if (status == 'CANCELLED')
                      const BxAlert('This order was cancelled.',
                          tone: BxTone.danger),
                    if (tracking?.riderName != null && status != 'DELIVERED') ...[
                      const SizedBox(height: DsSpace.s5),
                      _PartnerCard(
                        name: tracking!.riderName!,
                        carrier: tracking.courier,
                        onCall: tracking.riderPhone == null
                            ? null
                            : () => _call(tracking.riderPhone!),
                      ),
                    ],
                    const SizedBox(height: DsSpace.s5),
                    _InfoCard(
                      icon: Icons.location_on_outlined,
                      title: 'Delivering to',
                      lines: [
                        if (address is Map)
                          [
                            address['line1'],
                            address['line2'],
                            address['city'],
                            address['pincode'],
                          ]
                              .where((v) => v != null && '$v'.isNotEmpty)
                              .join(', '),
                        if (instructions.isNotEmpty) 'Note: $instructions',
                      ],
                    ),
                    const SizedBox(height: DsSpace.s3),
                    _InfoCard(
                      icon: Icons.shopping_bag_outlined,
                      title: '${order.items.length} '
                          '${order.items.length == 1 ? 'item' : 'items'} · '
                          '${formatMoney(order.totalAmount)}',
                      lines: [
                        order.items.map((i) => '${i.title} ×${i.quantity}').join(', '),
                        'Paid by ${order.paymentMethod}',
                      ],
                    ),
                    const SizedBox(height: DsSpace.s4),
                    BxButton(
                      label: 'Order details, receipt & returns',
                      variant: BxButtonVariant.secondary,
                      fullWidth: true,
                      leadingIcon: Icons.receipt_long_outlined,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailScreen(orderId: widget.orderId),
                        ),
                      ),
                    ),
                    if (widget.justPlaced) ...[
                      const SizedBox(height: DsSpace.s2),
                      BxButton(
                        label: 'Continue shopping',
                        variant: BxButtonVariant.ghost,
                        fullWidth: true,
                        onPressed: _leave,
                      ),
                    ],
                    if (tracking?.sandbox == true) ...[
                      const SizedBox(height: DsSpace.s3),
                      Text(
                        'Test delivery network: no live courier account is connected yet, '
                        'so the position shown is an estimate.',
                        style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Material(
      color: c.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: c.ink),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  final String name;
  final String? carrier;
  final VoidCallback? onCall;

  const _PartnerCard({required this.name, this.carrier, this.onCall});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return BxCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: c.accentSoft,
            child: Icon(Icons.person, color: c.accent),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: DsText.md,
                        fontWeight: DsWeight.black,
                        color: c.ink)),
                Text(
                  carrier == null || carrier!.isEmpty
                      ? 'Your delivery partner'
                      : 'Your delivery partner · $carrier',
                  style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                ),
              ],
            ),
          ),
          if (onCall != null)
            IconButton.filled(
              tooltip: 'Call $name',
              style: IconButton.styleFrom(
                  backgroundColor: c.success, foregroundColor: c.onPrimary),
              icon: const Icon(Icons.phone),
              onPressed: () {
                DsHaptics.tap();
                onCall!();
              },
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;

  const _InfoCard({required this.icon, required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return BxCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.inkMuted, size: DsTouch.iconSm),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: DsText.base,
                        fontWeight: DsWeight.bold,
                        color: c.ink)),
                for (final line in lines.where((l) => l.isNotEmpty))
                  Text(line,
                      style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
