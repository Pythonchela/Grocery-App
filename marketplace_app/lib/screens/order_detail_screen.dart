import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/order_alerts.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import '../support/support_api.dart';
import '../support/support_screens.dart';
import 'invoice_screen.dart';
import '../widgets/option_picks.dart';
import 'order_tracking_screen.dart';
import 'post_purchase_sheets.dart';

/// Order detail with live tracking.
///
/// Polls the delivery endpoint while the parcel is moving and stops once it is
/// delivered or the screen goes away — a timer left running against a delivered
/// order is a battery drain and a pointless request every 30 seconds.
class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  final bool justPlaced;

  const OrderDetailScreen({super.key, required this.orderId, this.justPlaced = false});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  TrackingInfo? _tracking;
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.request(
        '/orders/${widget.orderId}',
        token: AppState.instance.token,
      ) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _order = data;
        _loading = false;
      });

      await _refreshTracking();
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
        token: AppState.instance.token,
      ) as Map<String, dynamic>;

      if (!mounted) return;
      final tracking = TrackingInfo.fromJson(data);
      setState(() => _tracking = tracking);

      _schedulePoll(tracking);
    } catch (_) {
      // Tracking is supplementary — a courier API hiccup must not blank the
      // order the customer came here to look at.
    }
  }

  void _schedulePoll(TrackingInfo tracking) {
    _poll?.cancel();

    final settled = tracking.currentStatus == 'DELIVERED' ||
        tracking.currentStatus == 'CANCELLED' ||
        _order?['status'] == 'DELIVERED' ||
        _order?['status'] == 'CANCELLED';

    if (settled) return;

    // Faster while a rider is actually on the road; slower for a multi-day
    // surface shipment where nothing changes for hours.
    final interval = tracking.hasLivePosition
        ? const Duration(seconds: 30)
        : const Duration(minutes: 5);

    _poll = Timer(interval, _refreshTracking);
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showBxSheet<bool>(
      context: context,
      title: 'Cancel this order?',
      child: Text(
        'Stock goes back to inventory and any wallet amount is refunded immediately. '
        'This cannot be undone.',
        style: TextStyle(
          fontSize: DsText.base,
          height: DsText.baseHeight,
          color: context.ds.inkMuted,
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: BxButton(
              label: 'Keep order',
              variant: BxButtonVariant.secondary,
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: BxButton(
              label: 'Cancel it',
              variant: BxButtonVariant.danger,
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient.request(
        '/orders/${widget.orderId}/cancel',
        method: 'POST',
        token: AppState.instance.token,
      );
      await AppState.instance.refreshUser();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _review(OrderItem item) async {
    final done = await showWriteReviewSheet(
      context: context,
      productId: item.productId,
      productTitle: item.title,
      orderId: widget.orderId,
    );

    if (done == true && mounted) {
      // They have reviewed it; no need to nudge them about it later.
      OrderAlerts.instance.cancelReviewReminder(widget.orderId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — your review is in moderation.')),
      );
    }
  }

  Future<void> _return(OrderItem item) async {
    final done = await showReturnSheet(
      context: context,
      orderItemId: item.id,
      productTitle: item.title,
    );

    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Return requested. We will confirm the pickup shortly.')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order')),
        body: const Padding(
          padding: EdgeInsets.all(DsSpace.s4),
          child: Column(
            children: [
              BxSkeleton(height: 120, radius: DsRadius.cardAll),
              SizedBox(height: DsSpace.s3),
              BxSkeleton(height: 200, radius: DsRadius.cardAll),
            ],
          ),
        ),
      );
    }

    if (_error != null || _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order')),
        body: BxEmptyState(
          icon: Icons.error_outline,
          title: 'Could not load this order',
          description: _error,
          action: BxButton(label: 'Go back', onPressed: () => Navigator.of(context).pop()),
        ),
      );
    }

    final order = Order.fromJson(_order!);
    final status = order.status;
    final canCancel = !['DELIVERED', 'CANCELLED', 'OUT_FOR_DELIVERY'].contains(status);

    return Scaffold(
      appBar: AppBar(
        title: Text(order.orderNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s10),
        children: [
          if (widget.justPlaced) ...[
            BxCard(
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 32, color: c.success),
                  const SizedBox(width: DsSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order confirmed',
                          style: TextStyle(
                            fontSize: DsText.md,
                            fontWeight: DsWeight.black,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          'We will notify you at every step.',
                          style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DsSpace.s4),
          ],

          if (!['DELIVERED', 'CANCELLED'].contains(status)) ...[
            BxButton(
              label: 'Track order live',
              size: BxButtonSize.lg,
              fullWidth: true,
              leadingIcon: Icons.electric_moped_outlined,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(orderId: widget.orderId),
                ),
              ),
            ),
            const SizedBox(height: DsSpace.s3),
          ],
          _TrackingCard(order: _order!, tracking: _tracking),

          const SizedBox(height: DsSpace.s4),
          Text('Progress',
              style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
          const SizedBox(height: DsSpace.s3),
          _StatusTimeline(status: status),

          if (_tracking != null && _tracking!.scans.isNotEmpty) ...[
            const SizedBox(height: DsSpace.s5),
            Text('Courier scans',
                style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
            const SizedBox(height: DsSpace.s3),
            BxCard(
              child: Column(
                children: _tracking!.scans
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: DsSpace.s3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.circle, size: 8, color: c.accent),
                              const SizedBox(width: DsSpace.s3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.status,
                                      style: TextStyle(
                                        fontSize: DsText.base,
                                        fontWeight: DsWeight.bold,
                                        color: c.ink,
                                      ),
                                    ),
                                    Text(
                                      [s.location, formatDate(s.at)]
                                          .where((v) => v.isNotEmpty)
                                          .join(' · '),
                                      style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],

          const SizedBox(height: DsSpace.s5),
          Text('Items',
              style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
          const SizedBox(height: DsSpace.s3),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s2),
                child: BxCard(
                  padding: const EdgeInsets.all(DsSpace.s3),
                  child: Row(
                    children: [
                      if (item.image != null)
                        ClipRRect(
                          borderRadius: DsRadius.controlAll,
                          child: Image.network(
                            item.image!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 52,
                              height: 52,
                              color: c.surfaceSunken,
                            ),
                          ),
                        ),
                      const SizedBox(width: DsSpace.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: DsText.base,
                                fontWeight: DsWeight.bold,
                                color: c.ink,
                              ),
                            ),
                            Text('Qty ${item.quantity}',
                                style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                            OptionPicks(picks: item.picks),
                            if (item.cancelledByShop)
                              Text('Cancelled by the shop — refunded',
                                  style: TextStyle(
                                      fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.danger)),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(item.price * item.quantity),
                        style: TextStyle(
                          fontSize: DsText.base,
                          fontWeight: DsWeight.black,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              )),

          // Review and return only exist once something has actually arrived.
          // Offering them earlier produces support tickets, not reviews.
          if (status == 'DELIVERED') ...[
            const SizedBox(height: DsSpace.s4),
            Text('After delivery',
                style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
            const SizedBox(height: DsSpace.s3),
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s2),
                  child: BxCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DsText.base,
                            fontWeight: DsWeight.bold,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: DsSpace.s3),
                        Row(
                          children: [
                            Expanded(
                              child: BxButton(
                                label: 'Write a review',
                                variant: BxButtonVariant.secondary,
                                size: BxButtonSize.sm,
                                fullWidth: true,
                                leadingIcon: Icons.star_outline_rounded,
                                onPressed: () => _review(item),
                              ),
                            ),
                            const SizedBox(width: DsSpace.s2),
                            Expanded(
                              child: BxButton(
                                label: 'Return',
                                variant: BxButtonVariant.secondary,
                                size: BxButtonSize.sm,
                                fullWidth: true,
                                leadingIcon: Icons.assignment_return_outlined,
                                onPressed: () => _return(item),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
          ],

          const SizedBox(height: DsSpace.s4),
          BxCard(
            child: Column(
              children: [
                _row(context, 'Payment', order.paymentMethod),
                const SizedBox(height: DsSpace.s2),
                _row(context, 'Placed', formatDate(order.createdAt)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DsSpace.s3),
                  child: Divider(height: 1, color: c.line),
                ),
                _row(context, 'Total paid', formatMoney(order.totalAmount), bold: true),
              ],
            ),
          ),

          if (order.status != 'CANCELLED') ...[
            const SizedBox(height: DsSpace.s3),
            BxButton(
              label: 'View receipt',
              variant: BxButtonVariant.secondary,
              fullWidth: true,
              leadingIcon: Icons.receipt_long_outlined,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => InvoiceScreen(orderId: widget.orderId)),
              ),
            ),
          ],

          const SizedBox(height: DsSpace.s3),
          BxButton(
            label: 'Get help with this order',
            variant: BxButtonVariant.ghost,
            fullWidth: true,
            leadingIcon: Icons.support_agent_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SupportScreen(
                  api: HttpSupportApi(() => AppState.instance.token),
                  orderId: widget.orderId,
                  orderNumber: '${_order?['order_number'] ?? ''}',
                ),
              ),
            ),
          ),

          if (canCancel) ...[
            const SizedBox(height: DsSpace.s5),
            BxButton(
              label: 'Cancel order',
              variant: BxButtonVariant.dangerSoft,
              fullWidth: true,
              onPressed: _cancelOrder,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) {
    final c = context.ds;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: bold ? DsText.md : DsText.base,
              fontWeight: bold ? DsWeight.black : DsWeight.medium,
              color: bold ? c.ink : c.inkMuted,
            )),
        Text(value,
            style: TextStyle(
              fontSize: bold ? DsText.md : DsText.base,
              fontWeight: bold ? DsWeight.black : DsWeight.bold,
              color: c.ink,
            )),
      ],
    );
  }
}

class _TrackingCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final TrackingInfo? tracking;

  const _TrackingCard({required this.order, this.tracking});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final t = tracking;

    return BxCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, size: 20, color: c.accent),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: Text(
                  t?.serviceLabel ?? order['service_level']?.toString() ?? 'Delivery',
                  style: TextStyle(
                    fontSize: DsText.base,
                    fontWeight: DsWeight.black,
                    color: c.ink,
                  ),
                ),
              ),
              // Never badged LIVE while the position is synthetic — a fake
              // "live" marker is worse than no marker.
              if (t?.sandbox == true) const BxBadge('Sandbox feed', tone: BxTone.warning),
            ],
          ),
          const SizedBox(height: DsSpace.s3),

          if (t == null)
            const BxSkeleton(width: 200)
          else if (!t.isDispatched)
            Text(
              t.message ?? 'Not dispatched yet.',
              style: TextStyle(fontSize: DsText.base, height: DsText.baseHeight, color: c.inkMuted),
            )
          else ...[
            Text(
              t.currentStatus.replaceAll('_', ' '),
              style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink),
            ),
            if (t.etaMinutes != null)
              Text(
                t.etaMinutes! < 60
                    ? 'Arriving in about ${t.etaMinutes} minutes'
                    : 'Arriving in about ${(t.etaMinutes! / 60).round()} hours',
                style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
              ),
            const SizedBox(height: DsSpace.s2),
            Text(
              'Tracking ${t.trackingNo}${t.courier != null ? ' · ${t.courier}' : ''}',
              style: TextStyle(fontFamily: DsFont.mono, fontSize: DsText.xs, color: c.inkSubtle),
            ),
            if (t.riderName != null) ...[
              const SizedBox(height: DsSpace.s3),
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: c.accentSoft,
                    child: Icon(Icons.person, size: 16, color: c.accent),
                  ),
                  const SizedBox(width: DsSpace.s2),
                  Expanded(
                    child: Text(
                      t.riderName!,
                      style: TextStyle(
                        fontSize: DsText.base,
                        fontWeight: DsWeight.bold,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (t.riderPhone != null)
                    BxButton(
                      label: 'Call',
                      variant: BxButtonVariant.secondary,
                      size: BxButtonSize.xs,
                      leadingIcon: Icons.phone_outlined,
                      onPressed: () =>
                          launchUrl(Uri(scheme: 'tel', path: t.riderPhone)),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  final String status;

  const _StatusTimeline({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    if (status == 'CANCELLED') {
      return const BxAlert('This order was cancelled.', tone: BxTone.danger);
    }

    final currentIndex = orderStages.indexOf(status);

    return BxCard(
      child: Column(
        children: List.generate(orderStages.length, (i) {
          final stage = orderStages[i];
          final done = currentIndex >= i;
          final isLast = i == orderStages.length - 1;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: done ? c.success : c.surfaceSunken,
                        borderRadius: DsRadius.pillAll,
                        border: Border.all(color: done ? c.success : c.line),
                      ),
                      child: done
                          ? Icon(Icons.check, size: 12, color: c.inkInverse)
                          : null,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: currentIndex > i ? c.success : c.line,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : DsSpace.s4),
                    child: Text(
                      stageLabels[stage] ?? stage,
                      style: TextStyle(
                        fontSize: DsText.base,
                        fontWeight: currentIndex == i ? DsWeight.black : DsWeight.medium,
                        color: done ? c.ink : c.inkSubtle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
