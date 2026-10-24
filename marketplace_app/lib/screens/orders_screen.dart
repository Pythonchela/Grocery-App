import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/mobile.dart';
import '../design/mobile_components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'account_screen.dart';
import 'cart_screen.dart';
import 'order_detail_screen.dart';
import '../widgets/option_picks.dart';
import '../widgets/shop_switch.dart';
import 'order_tracking_screen.dart';

/// Where an order sits, in the four buckets a shopper thinks in.
enum OrderBucket { all, pending, processing, completed, cancelled }

extension on OrderBucket {
  String get label => switch (this) {
        OrderBucket.all => 'All',
        OrderBucket.pending => 'Pending',
        OrderBucket.processing => 'Processing',
        OrderBucket.completed => 'Completed',
        OrderBucket.cancelled => 'Cancelled',
      };
}

/// Which bucket a raw order status belongs to.
OrderBucket bucketOf(String status) => switch (status) {
      'PENDING' || 'CONFIRMED' => OrderBucket.pending,
      'PACKED' || 'SHIPPED' || 'OUT_FOR_DELIVERY' => OrderBucket.processing,
      'DELIVERED' => OrderBucket.completed,
      'CANCELLED' => OrderBucket.cancelled,
      _ => OrderBucket.pending,
    };

/// The shopper's orders: filter chips along the top, a card per order with its
/// first item, status, total and the two things you usually want next.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Order> _orders = [];
  bool _loading = true;
  String? _error;
  OrderBucket _bucket = OrderBucket.all;
  String? _rebuyingId;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onSession);
    _load();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onSession);
    super.dispose();
  }

  bool _wasSignedIn = AppState.instance.isSignedIn;

  void _onSession() {
    final now = AppState.instance.isSignedIn;
    if (now == _wasSignedIn) return;
    _wasSignedIn = now;
    if (now) {
      _load();
    } else if (mounted) {
      setState(() => _orders = []);
    }
  }

  Future<void> _load() async {
    if (!AppState.instance.isSignedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.request('/orders/mine',
          token: AppState.instance.token) as List;
      if (!mounted) return;
      setState(() {
        _orders = data
            .whereType<Map<String, dynamic>>()
            .map(Order.fromJson)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Order> get _visible => _bucket == OrderBucket.all
      ? _orders
      : _orders.where((o) => bucketOf(o.status) == _bucket).toList();

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  /// Puts the same items (same sizes and colours) back in the cart at today's
  /// prices and stock, skipping anything that is gone.
  Future<void> _buyAgain(Order order) async {
    if (_rebuyingId != null) return;
    setState(() => _rebuyingId = order.id);

    var added = 0;
    var unavailable = 0;
    try {
      for (final item in order.items) {
        try {
          final data = await ApiClient.request('/products/${item.productId}');
          final product = Product.fromJson(data as Map<String, dynamic>);
          // A basket from another shop: ask once, before the first item goes in.
          if (added == 0 && unavailable == 0) {
            if (!mounted || !await confirmShopSwitch(context, product)) return;
          }
          final variant =
              product.variants.where((v) => v.id == item.variantId && v.stock > 0).firstOrNull ??
                  product.variants.where((v) => v.stock > 0).firstOrNull;
          // The same picks (portion, add-ons...) go back in; if one has since
          // been withdrawn the item is reported as unavailable, not guessed at.
          final ok = variant != null &&
              AppState.instance.addToCart(product,
                  variant: variant,
                  selection: item.selection,
                  quantity: item.quantity.clamp(1, variant.stock.clamp(1, 20)));
          ok ? added++ : unavailable++;
        } catch (_) {
          unavailable++;
        }
      }
    } finally {
      if (mounted) setState(() => _rebuyingId = null);
    }

    if (!mounted) return;
    DsHaptics.success();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(added == 0
            ? 'Those items are not available right now'
            : unavailable == 0
                ? '$added ${added == 1 ? 'item' : 'items'} added to your cart'
                : '$added added; $unavailable no longer available'),
        action: added == 0
            ? null
            : SnackBarAction(
                label: 'View cart',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CartScreen())),
              ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: !AppState.instance.isSignedIn
          ? BxEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Sign in to see your orders',
              description: 'Your orders, tracking and invoices live here.',
              action: BxButton(
                label: 'Sign in',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountScreen())),
              ),
            )
          : Column(
              children: [
                _Chips(
                  selected: _bucket,
                  counts: {
                    for (final b in OrderBucket.values)
                      b: b == OrderBucket.all
                          ? _orders.length
                          : _orders.where((o) => bucketOf(o.status) == b).length,
                  },
                  onSelected: (b) => setState(() => _bucket = b),
                ),
                Expanded(
                  child: _loading
                      ? ListView(
                          padding: const EdgeInsets.all(DsSpace.s4),
                          children: const [
                            BxSkeleton(height: 180, radius: DsRadius.cardAll),
                            SizedBox(height: DsSpace.s3),
                            BxSkeleton(height: 180, radius: DsRadius.cardAll),
                          ],
                        )
                      : _error != null
                          ? BxEmptyState(
                              icon: Icons.wifi_off_outlined,
                              title: 'Could not load your orders',
                              description: _error,
                              action: BxButton(
                                  label: 'Try again', onPressed: _load),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: c.accent,
                              child: _visible.isEmpty
                                  ? ListView(children: [
                                      const SizedBox(height: DsSpace.s10),
                                      BxEmptyState(
                                        icon: Icons.receipt_long_outlined,
                                        title: _bucket == OrderBucket.all
                                            ? 'No orders yet'
                                            : 'No ${_bucket.label.toLowerCase()} orders',
                                        description: _bucket == OrderBucket.all
                                            ? 'When you place an order it will show up here.'
                                            : 'Nothing in this list right now.',
                                      ),
                                    ])
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(DsSpace.s4),
                                      itemCount: _visible.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: DsSpace.s3),
                                      itemBuilder: (context, i) {
                                        final order = _visible[i];
                                        return _OrderCard(
                                          order: order,
                                          rebuying: _rebuyingId == order.id,
                                          onOpen: () => _open(
                                              OrderDetailScreen(orderId: order.id)),
                                          onPrimary: () => _primaryAction(order),
                                          onBuyAgain: () => _buyAgain(order),
                                        );
                                      },
                                    ),
                            ),
                ),
              ],
            ),
    );
  }

  void _primaryAction(Order order) {
    switch (bucketOf(order.status)) {
      case OrderBucket.processing:
        if (order.status == 'PACKED') {
          _open(OrderDetailScreen(orderId: order.id));
        } else {
          _open(OrderTrackingScreen(orderId: order.id));
        }
      default:
        _open(OrderDetailScreen(orderId: order.id));
    }
  }
}

class _Chips extends StatelessWidget {
  final OrderBucket selected;
  final Map<OrderBucket, int> counts;
  final ValueChanged<OrderBucket> onSelected;

  const _Chips(
      {required this.selected, required this.counts, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: DsSpace.s4, vertical: DsSpace.s2),
        itemCount: OrderBucket.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: DsSpace.s2),
        itemBuilder: (context, i) {
          final bucket = OrderBucket.values[i];
          final isSelected = bucket == selected;
          final count = counts[bucket] ?? 0;
          return Semantics(
            button: true,
            selected: isSelected,
            child: Material(
              color: isSelected ? c.primary : c.surface,
              borderRadius: DsRadius.controlAll,
              child: InkWell(
                borderRadius: DsRadius.controlAll,
                onTap: () {
                  DsHaptics.select();
                  onSelected(bucket);
                },
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
                  decoration: BoxDecoration(
                    borderRadius: DsRadius.controlAll,
                    border: Border.all(
                        color: isSelected ? c.primary : c.line),
                  ),
                  child: Text(
                    count > 0 && bucket != OrderBucket.all
                        ? '${bucket.label} · $count'
                        : bucket.label,
                    style: TextStyle(
                      fontSize: DsText.sm,
                      fontWeight: DsWeight.semibold,
                      color: isSelected ? c.onPrimary : c.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final bool rebuying;
  final VoidCallback onOpen;
  final VoidCallback onPrimary;
  final VoidCallback onBuyAgain;

  const _OrderCard({
    required this.order,
    required this.rebuying,
    required this.onOpen,
    required this.onPrimary,
    required this.onBuyAgain,
  });

  ({String label, BxTone tone}) get _status => switch (bucketOf(order.status)) {
        OrderBucket.completed => (label: 'Delivered', tone: BxTone.success),
        OrderBucket.cancelled => (label: 'Cancelled', tone: BxTone.danger),
        OrderBucket.processing => (
            label: order.statusLabel,
            tone: BxTone.info
          ),
        _ => (label: order.statusLabel, tone: BxTone.warning),
      };

  String get _primaryLabel => switch (order.status) {
        'PENDING' || 'CONFIRMED' || 'PACKED' => 'Cancel order',
        'SHIPPED' || 'OUT_FOR_DELIVERY' => 'Track order',
        'DELIVERED' => 'Return / refund',
        _ => 'View details',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final first = order.items.isEmpty ? null : order.items.first;
    final more = order.items.length - 1;
    final totalQty = order.items.fold<int>(0, (s, i) => s + i.quantity);
    final status = _status;
    final short = order.orderNumber.replaceFirst(RegExp(r'^ORD-'), '');

    return BxCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          BxPressable(
            onTap: onOpen,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DsRadius.card)),
            child: Padding(
              padding: const EdgeInsets.all(DsSpace.s4),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Order #$short',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: DsText.base,
                                fontWeight: DsWeight.bold,
                                color: c.ink)),
                      ),
                      Text(formatDate(order.createdAt),
                          style: TextStyle(
                              fontSize: DsText.xs, color: c.inkSubtle)),
                    ],
                  ),
                  const SizedBox(height: DsSpace.s3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: DsRadius.controlAll,
                        child: Container(
                          width: 68,
                          height: 68,
                          color: c.surfaceSunken,
                          child: first?.image == null
                              ? Icon(Icons.shopping_bag_outlined,
                                  color: c.inkSubtle)
                              : Image.network(
                                  first!.image!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                      Icons.image_not_supported_outlined,
                                      color: c.inkSubtle),
                                ),
                        ),
                      ),
                      const SizedBox(width: DsSpace.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    first == null
                                        ? 'No items'
                                        : more > 0
                                            ? '${first.title} + $more more'
                                            : first.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: DsText.base,
                                        fontWeight: DsWeight.semibold,
                                        color: c.ink),
                                  ),
                                ),
                                const SizedBox(width: DsSpace.s2),
                                BxBadge(status.label, tone: status.tone),
                              ],
                            ),
                            if (first != null && first.picks.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              OptionPicks(picks: first.picks, maxLines: 1),
                            ],
                            const SizedBox(height: DsSpace.s1),
                            Row(
                              children: [
                                Icon(Icons.payments_outlined,
                                    size: 14, color: c.accent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(order.paymentMethod,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: DsText.xs,
                                          color: c.inkMuted)),
                                ),
                                Text('Qty: $totalQty',
                                    style: TextStyle(
                                        fontSize: DsText.xs,
                                        color: c.inkMuted)),
                              ],
                            ),
                            const SizedBox(height: DsSpace.s1),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text('Total: ${formatMoney(order.totalAmount)}',
                                  style: TextStyle(
                                      fontSize: DsText.base,
                                      fontWeight: DsWeight.bold,
                                      color: c.ink)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                DsSpace.s4, 0, DsSpace.s4, DsSpace.s4),
            child: Row(
              children: [
                Expanded(
                  child: BxButton(
                    label: _primaryLabel,
                    variant: BxButtonVariant.secondary,
                    size: BxButtonSize.sm,
                    fullWidth: true,
                    onPressed: onPrimary,
                  ),
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: BxButton(
                    label: 'Buy again',
                    size: BxButtonSize.sm,
                    fullWidth: true,
                    loading: rebuying,
                    onPressed: rebuying ? null : onBuyAgain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
