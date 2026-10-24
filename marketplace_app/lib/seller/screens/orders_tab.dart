import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_api.dart';
import '../seller_format.dart';
import '../seller_models.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/paged_loader.dart';
import '../widgets/seller_widgets.dart';
import 'order_desk.dart';
import 'ship_sheet.dart';

/// The seller's workflow for the lines they have sold: pack it, hand it to a
/// courier, and follow it to the door.
class OrdersTab extends StatefulWidget {
  final SellerApi api;

  /// Told after any pack or ship, so the overview's counts can refresh.
  final VoidCallback? onChanged;

  /// Asked for by the dashboard (the "new orders" banner): switch to this stage.
  final ValueListenable<String?>? stageRequest;

  const OrdersTab({super.key, required this.api, this.onChanged, this.stageRequest});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  // Stages, not raw order statuses: the seller cares about "what do I need to
  // do", and one order can be at different stages for different sellers.
  static const _stages = [
    BxTab('new', 'New'),
    BxTab('to_pack', 'To pack'),
    BxTab('packed', 'Packed'),
    BxTab('shipped', 'Shipped'),
    BxTab('delivered', 'Delivered'),
    BxTab('cancelled', 'Cancelled'),
  ];

  // The dashboard may have asked for a stage before this tab existed (it is built on first open).
  late String _stage = widget.stageRequest?.value ?? 'to_pack';
  late PagedLoader<SellerOrderItem> _loader;
  final Set<String> _busy = {};

  // Server time minus device time, so the countdown follows the server's clock.
  Duration _clockOffset = Duration.zero;
  int? _defaultPrep;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loader = _make(_stage)..refresh();
    widget.stageRequest?.addListener(_onStageRequest);
    // New orders appear by themselves while the seller is looking at them.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_stage == 'new' && mounted) _loader.refresh();
    });
    widget.api.me().then((p) {
      if (mounted) _defaultPrep = p.shop.prepMinutes;
    }).catchError((_) {});
  }

  @override
  void dispose() {
    widget.stageRequest?.removeListener(_onStageRequest);
    _poll?.cancel();
    _loader.dispose();
    super.dispose();
  }

  void _onStageRequest() {
    final wanted = widget.stageRequest?.value;
    if (wanted != null) _select(wanted);
  }

  PagedLoader<SellerOrderItem> _make(String stage) => PagedLoader((page) async {
        final result = await widget.api.orderItems(stage: stage, page: page);
        final serverTime = DateTime.tryParse('${result.extra['server_time'] ?? ''}');
        if (serverTime != null) _clockOffset = serverTime.difference(DateTime.now());
        return result;
      });

  void _select(String stage) {
    if (stage == _stage) return;
    final old = _loader;
    setState(() {
      _stage = stage;
      _loader = _make(stage)..refresh();
    });
    old.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? context.ds.danger : null));
  }

  /// A pack or ship changes which tab a line belongs in, so the list reloads.
  Future<void> _afterChange(String message) async {
    _toast(message);
    widget.onChanged?.call();
    await _loader.refresh();
  }

  Future<void> _pack(SellerOrderItem item) async {
    setState(() => _busy.add(item.id));
    try {
      await widget.api.packItem(item.id);
      await _afterChange('Marked as packed.');
    } on ApiException catch (e) {
      _toast(e.fieldError('fulfilment') ?? e.message, error: true);
      // The line may have changed under us (order cancelled, say): show the truth.
      await _loader.refresh();
    } catch (_) {
      _toast('Could not reach the server. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _accept(SellerOrderItem item) async {
    final accepted = await showAcceptSheet(context, widget.api, item, defaultPrep: _defaultPrep);
    if (accepted == true && mounted) await _afterChange('Order accepted. Pack it before the promised time.');
  }

  Future<void> _decline(SellerOrderItem item) async {
    final done = await showDeclineSheet(context, widget.api, item, cancelling: !item.awaitingAnswer);
    if (done == true && mounted) {
      await _afterChange(item.awaitingAnswer ? 'Order declined. The customer is refunded.' : 'Order cancelled. The customer is refunded.');
    }
  }

  Future<void> _ship(SellerOrderItem item) async {
    final updated = await ShipSheet.show(context, widget.api, item);
    if (updated == null || !mounted) return;
    await _afterChange(item.fulfilmentStatus == 'SHIPPED' ? 'Tracking details updated.' : 'Marked as shipped.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return PagedListView<SellerOrderItem>(
      loader: _loader,
      header: [
        // BxTabs carries its own horizontal padding; pull it back to the edge.
        Transform.translate(
          offset: const Offset(-DsSpace.s4, 0),
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width,
            child: BxTabs(tabs: _stages, value: _stage, onChanged: _select),
          ),
        ),
        const SizedBox(height: DsSpace.s3),
        Text(_hint, style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
        const SizedBox(height: DsSpace.s4),
      ],
      empty: BxEmptyState(
        icon: _stage == 'to_pack' || _stage == 'new' ? Icons.check_circle_outline : Icons.inventory_2_outlined,
        title: _stage == 'new' ? 'No orders waiting' : _stage == 'to_pack' ? 'Nothing to pack' : 'No orders here',
        description: _stage == 'new'
            ? 'New orders appear here by themselves. You have a few minutes to accept each one.'
            : _stage == 'to_pack'
                ? 'Accepted orders for your products will appear here, ready to pack.'
                : 'Items will show up here as they reach this stage.',
      ),
      itemBuilder: (context, item) => _OrderItemCard(
        item: item,
        busy: _busy.contains(item.id),
        clockOffset: _clockOffset,
        onPack: () => _pack(item),
        onShip: () => _ship(item),
        onAccept: () => _accept(item),
        onDecline: () => _decline(item),
      ),
    );
  }

  String get _hint => switch (_stage) {
        'new' => 'Accept an order to start preparing it. An order nobody answers is cancelled when its timer runs out, and the customer is refunded.',
        'to_pack' => 'Pack each item, then mark it shipped with the courier and tracking number.',
        'packed' => 'Packed and waiting to be handed to a courier.',
        'shipped' => 'Handed to a courier. Customers can follow these with the tracking number.',
        'delivered' => 'Delivered to the customer.',
        _ => 'Cancelled orders. Nothing to ship.',
      };
}

class _OrderItemCard extends StatelessWidget {
  final SellerOrderItem item;
  final bool busy;
  final VoidCallback onPack;
  final VoidCallback onShip;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final Duration clockOffset;

  const _OrderItemCard({
    required this.item,
    required this.busy,
    required this.onPack,
    required this.onShip,
    required this.onAccept,
    required this.onDecline,
    this.clockOffset = Duration.zero,
  });

  /// What to call the line's state. While the order is open that is the line's
  /// own progress; once it has moved on, the order's status says it better.
  (String, BxTone) get _badge {
    if (item.sellerResponse == 'REJECTED') {
      return (item.rejectedBy == 'SYSTEM' ? 'Missed' : 'Declined', BxTone.danger);
    }
    if (item.awaitingAnswer) return ('Needs your answer', BxTone.warning);
    switch (item.orderStatus) {
      case 'DELIVERED':
        return ('Delivered', BxTone.success);
      case 'CANCELLED':
        return ('Cancelled', BxTone.danger);
      case 'OUT_FOR_DELIVERY':
        return ('Out for delivery', BxTone.info);
    }
    return switch (item.fulfilmentStatus) {
      'SHIPPED' => ('Shipped', BxTone.info),
      'PACKED' => ('Packed', BxTone.accent),
      _ => ('To pack', BxTone.warning),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final shipTo = [item.shipToName, item.shipToCity, item.shipToPincode].where((e) => e.isNotEmpty).join(', ');
    final (label, tone) = _badge;

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SellerThumb(url: item.image),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink),
                    ),
                    if (item.variantLabel.isNotEmpty)
                      Text(item.variantLabel, style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
                    const SizedBox(height: DsSpace.s1),
                    Text(
                      '${item.quantity} × ${SellerFormat.money(item.price)}',
                      style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                    ),
                    // Under the title, not beside it: a long status would not
                    // leave the title any room on a small phone.
                    const SizedBox(height: DsSpace.s2),
                    BxBadge(label, tone: tone),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          Divider(height: 1, color: c.line),
          const SizedBox(height: DsSpace.s3),
          SellerKeyValue('Order', '${item.orderNumber} · ${SellerFormat.date(item.createdAt)}'),
          SellerKeyValue('Ship to', shipTo),
          SellerKeyValue('You earn', SellerFormat.money(item.earning)),
          if (item.paymentMethod.isNotEmpty) SellerKeyValue('Payment', item.isCod ? 'Cash on delivery' : 'Paid online'),
          if (item.awaitingAnswer && item.acceptBy != null)
            Padding(
              padding: const EdgeInsets.only(top: DsSpace.s2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Answer within', style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
                  DeskCountdown(until: item.acceptBy!, offset: clockOffset),
                ],
              ),
            ),
          if (item.canPack && item.readyBy != null)
            SellerKeyValue(item.isLate ? 'Promised (late)' : 'Promised ready by', SellerFormat.dateTime(item.readyBy)),
          if (item.sellerResponse == 'REJECTED' && item.rejectionReason != null)
            SellerKeyValue('Reason', item.rejectionReason!.replaceAll('_', ' ').toLowerCase()),
          if (item.fulfilmentStatus == 'SHIPPED') ...[
            SellerKeyValue('Courier', item.courier ?? ''),
            SellerKeyValue('Tracking', item.trackingNo ?? ''),
            if (item.shippedAt != null) SellerKeyValue('Shipped', SellerFormat.dateTime(item.shippedAt)),
          ],
          if (item.awaitingAnswer) ...[
            const SizedBox(height: DsSpace.s3),
            Row(children: [
              Expanded(
                child: BxButton(
                  label: 'Accept',
                  leadingIcon: Icons.check,
                  size: BxButtonSize.sm,
                  onPressed: busy ? null : onAccept,
                ),
              ),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: BxButton(
                  label: 'Decline',
                  leadingIcon: Icons.close,
                  variant: BxButtonVariant.dangerSoft,
                  size: BxButtonSize.sm,
                  onPressed: busy ? null : onDecline,
                ),
              ),
            ]),
          ],
          if (item.canPack || item.canShip || item.canEditTracking || item.canCancel) ...[
            const SizedBox(height: DsSpace.s3),
            Wrap(
              spacing: DsSpace.s2,
              runSpacing: DsSpace.s2,
              children: [
                if (item.canCancel)
                  BxButton(
                    label: 'Cancel order',
                    leadingIcon: Icons.cancel_outlined,
                    variant: BxButtonVariant.dangerSoft,
                    size: BxButtonSize.sm,
                    onPressed: busy ? null : onDecline,
                  ),
                if (item.canPack)
                  BxButton(
                    label: 'Mark packed',
                    leadingIcon: Icons.inventory_2_outlined,
                    variant: BxButtonVariant.secondary,
                    size: BxButtonSize.sm,
                    loading: busy,
                    onPressed: busy ? null : onPack,
                  ),
                if (item.canShip)
                  BxButton(
                    label: 'Mark shipped',
                    leadingIcon: Icons.local_shipping_outlined,
                    size: BxButtonSize.sm,
                    onPressed: busy ? null : onShip,
                  ),
                if (item.canEditTracking)
                  BxButton(
                    label: 'Edit tracking',
                    leadingIcon: Icons.edit_outlined,
                    variant: BxButtonVariant.ghost,
                    size: BxButtonSize.sm,
                    onPressed: busy ? null : onShip,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
