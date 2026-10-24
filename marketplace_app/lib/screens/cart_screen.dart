import 'package:flutter/material.dart';

import '../data/bundles.dart';
import '../data/cart_delivery.dart';
import '../data/models.dart';
import '../data/shop.dart';
import '../design/components.dart';
import '../design/mobile.dart';
import '../design/mobile_components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import '../widgets/delivery_widgets.dart';
import '../widgets/shop_card.dart';
import 'account_screen.dart';
import 'address_screen.dart';
import 'checkout_screen.dart';
import '../widgets/option_picks.dart';
import 'product_detail_screen.dart';
import 'shop_screen.dart';

/// The cart, laid out the way quick-commerce apps do it: the delivery promise
/// first, what you save and how close you are to free delivery next, then the
/// items, then a plain bill - and a single sticky action at the bottom.
class CartScreen extends StatefulWidget {
  final VoidCallback? onStartShopping;
  const CartScreen({super.key, this.onStartShopping});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartDelivery _delivery = CartDelivery();

  // The shop the basket is from (stores that show shops), for its name, hours
  // and minimum order.
  Shop? _shop;
  String? _shopFor;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onAppState);
    _delivery.addListener(_rebuild);
    _delivery.refresh();
    _syncShop();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppState);
    _delivery.removeListener(_rebuild);
    _delivery.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// The cart or the session changed; the delivery promise may have too.
  void _onAppState() {
    _delivery.refresh();
    _syncShop();
  }

  /// Reads the basket's shop when the basket moves to a different one.
  Future<void> _syncShop() async {
    final state = AppState.instance;
    final id = state.storeConfig.showsShops ? state.cartShopId : null;

    if (id == null) {
      if (_shop != null || _shopFor != null) {
        _shop = null;
        _shopFor = null;
        _rebuild();
      }
      return;
    }
    if (id == _shopFor) return;
    _shopFor = id;

    try {
      final shop = await ShopApi.one(id);
      if (mounted && _shopFor == id) setState(() => _shop = shop);
    } catch (_) {
      // The basket still works without the shop's details; the server enforces
      // its hours and minimum at checkout either way.
    }
  }

  /// Why checkout cannot go ahead yet, from the shop's own rules; null when it can.
  String? _blockReason(AppState state) {
    final shop = _shop;
    if (shop == null) return null;
    if (!shop.isOpen) return 'Shop is closed';

    final short = shop.minOrder - state.cartSubtotal;
    if (shop.minOrder > 0 && short > 0.004) {
      return 'Add ${formatMoney(short)} more';
    }
    return null;
  }

  Future<void> _pickAddress() async {
    final picked = await Navigator.of(context).push<Address>(
      MaterialPageRoute(builder: (_) => const AddressScreen(selectMode: true)),
    );
    // Picking nothing may still mean they added their first address.
    await _delivery.setAddress(picked ?? _delivery.address);
    if (picked == null) await _delivery.refresh(force: true);
  }

  /// Hands off to the checkout screen rather than placing the order here.
  /// Address, delivery speed, coupon, wallet and points all belong to that flow;
  /// the cart's job ends at "these are the items".
  void _checkout() {
    if (!AppState.instance.isSignedIn) {
      _signIn();
      return;
    }

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }

  void _signIn() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const AccountScreen()));

  /// Removal is immediate (the row has already slid away), with Undo, so a stray
  /// swipe costs one tap rather than a lost item.
  void _remove(BuildContext context, CartLine line) {
    final state = AppState.instance;
    final quantity = line.quantity;
    final index = state.cart.indexWhere((l) => l.key == line.key);
    state.removeFromCart(line.key);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${line.product.title} removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => state.restoreLine(line, quantity, index),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final lines = state.cart;

        // The real quote when we have one, the flat estimate until then.
        final quoted = _delivery.cheapest;
        final deliveryFee = quoted?.price ?? state.estimatedShipping;
        final total = state.cartNetSubtotal + deliveryFee;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Your cart'),
            actions: [
              if (lines.isNotEmpty)
                TextButton(
                  onPressed: state.clearCart,
                  child: Text('Clear',
                      style: TextStyle(
                          color: c.danger, fontWeight: DsWeight.bold)),
                ),
            ],
          ),
          body: lines.isEmpty
              ? BxEmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Your cart is empty',
                  description: 'Products you add will show up here.',
                  action: BxButton(
                    label: 'Start shopping',
                    onPressed: widget.onStartShopping ??
                        () => Navigator.of(context).maybePop(),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _delivery.refresh(force: true),
                  color: c.accent,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s8),
                    children: [
                      if (_shop != null) ...[
                        _ShopStrip(
                          shop: _shop!,
                          subtotal: state.cartSubtotal,
                          onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ShopScreen(shop: _shop!))),
                        ),
                        const SizedBox(height: DsSpace.s3),
                      ],
                      DeliveryEtaStrip(
                        delivery: _delivery,
                        signedIn: state.isSignedIn,
                        itemCount: state.cartCount,
                        onChangeAddress: _pickAddress,
                        onSignIn: _signIn,
                      ),
                      if (state.isSignedIn && _delivery.hasAddress) ...[
                        const SizedBox(height: DsSpace.s2),
                        _AddressLine(
                            address: _delivery.address!, onChange: _pickAddress),
                      ],
                      if (state.cartTotalSavings > 0) ...[
                        const SizedBox(height: DsSpace.s3),
                        SavingsBanner(amount: state.cartTotalSavings),
                      ],
                      const SizedBox(height: DsSpace.s3),
                      FreeDeliveryMeter(
                        subtotal: state.cartNetSubtotal,
                        threshold: state.freeShippingThreshold,
                      ),
                      const SizedBox(height: DsSpace.s5),
                      _SectionLabel('${state.cartCount} '
                          '${state.cartCount == 1 ? 'item' : 'items'}'),
                      BxCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < lines.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: c.line),
                              BxSwipeToRemove(
                                dismissKey: ValueKey(lines[i].key),
                                onRemoved: () => _remove(context, lines[i]),
                                child: _CartLineTile(
                                  line: lines[i],
                                  onRemove: () => _remove(context, lines[i]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      for (final bundle
                          in BundlePricing.suggestions(lines, state.bundles))
                        Padding(
                          padding: const EdgeInsets.only(top: DsSpace.s3),
                          child: _BundleHint(bundle: bundle, cart: lines),
                        ),
                      const SizedBox(height: DsSpace.s5),
                      const _SectionLabel('Bill details'),
                      BxCard(
                        child: Column(
                          children: [
                            BillLine(
                              'Item total',
                              formatMoney(state.cartSubtotal),
                              icon: Icons.receipt_long_outlined,
                              strike: state.cartMrpTotal > state.cartSubtotal
                                  ? formatMoney(state.cartMrpTotal)
                                  : null,
                            ),
                            for (final applied in state.cartBundles) ...[
                              const SizedBox(height: DsSpace.s3),
                              BillLine(
                                applied.bundle.name.isEmpty
                                    ? 'Bundle savings'
                                    : 'Bundle — ${applied.bundle.name}',
                                '-${formatMoney(applied.discount)}',
                                icon: Icons.local_offer_outlined,
                                valueColor: c.success,
                              ),
                            ],
                            const SizedBox(height: DsSpace.s3),
                            BillLine(
                              'Delivery fee',
                              deliveryFee == 0
                                  ? 'FREE'
                                  : formatMoney(deliveryFee),
                              icon: Icons.local_shipping_outlined,
                              valueColor: deliveryFee == 0 ? c.success : null,
                            ),
                            if (_delivery.fastest != null &&
                                quoted != null &&
                                _delivery.fastest!.price > quoted.price) ...[
                              const SizedBox(height: DsSpace.s1),
                              Text(
                                'Want it ${etaPhrase(_delivery.fastest!).replaceFirst('Delivery ', '')}? '
                                'Faster delivery is ${formatMoney(_delivery.fastest!.price)} - '
                                'choose it at checkout.',
                                style: TextStyle(
                                    fontSize: DsText.xs, color: c.inkMuted),
                              ),
                            ],
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: DsSpace.s3),
                              child: Divider(height: 1, color: c.line),
                            ),
                            BillLine('To pay', formatMoney(total), bold: true),
                            const SizedBox(height: DsSpace.s2),
                            Text(
                              'Coupons, wallet and points are applied at checkout, '
                              'where you also choose how fast it arrives. The final '
                              'total is always worked out by the server.',
                              style: TextStyle(
                                  fontSize: DsText.xs, color: c.inkSubtle),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: DsSpace.s4),
                      BxCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.verified_user_outlined,
                                color: c.inkMuted, size: DsTouch.iconSm),
                            const SizedBox(width: DsSpace.s3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Cancellation policy',
                                      style: TextStyle(
                                          fontSize: DsText.base,
                                          fontWeight: DsWeight.bold,
                                          color: c.ink)),
                                  Text(
                                    'You can cancel until the order is out for '
                                    'delivery. After that it can only be returned.',
                                    style: TextStyle(
                                        fontSize: DsText.sm,
                                        color: c.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          bottomNavigationBar: lines.isEmpty
              ? null
              : BxBottomBar(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BxTotalAction(
                        label: 'Total',
                        amount: formatMoney(total),
                        button: BxButton(
                          label: _blockReason(state) ??
                              (state.isSignedIn
                                  ? 'Proceed to checkout'
                                  : 'Sign in to checkout'),
                          size: BxButtonSize.lg,
                          fullWidth: true,
                          trailingIcon:
                              _blockReason(state) == null ? Icons.arrow_forward : null,
                          onPressed: _blockReason(state) == null ? _checkout : null,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: DsSpace.s2, left: DsSpace.s1),
        child: Text(
          text,
          style: TextStyle(
            fontSize: DsText.base,
            fontWeight: DsWeight.black,
            color: context.ds.inkMuted,
          ),
        ),
      );
}

/// "Delivering to Home - 221B Indiranagar, Bengaluru   Change"
class _AddressLine extends StatelessWidget {
  final Address address;
  final VoidCallback onChange;

  const _AddressLine({required this.address, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final label = address.tag?.isNotEmpty == true ? address.tag! : 'your address';

    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s2),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, size: 18, color: c.accent),
          const SizedBox(width: DsSpace.s2),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Delivering to '),
                TextSpan(
                  text: label,
                  style: const TextStyle(fontWeight: DsWeight.black),
                ),
                TextSpan(text: ' · ${address.line1}'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
            ),
          ),
          BxButton(
            label: 'Change',
            variant: BxButtonVariant.link,
            size: BxButtonSize.sm,
            onPressed: onChange,
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  final CartLine line;
  final VoidCallback onRemove;

  const _CartLineTile({required this.line, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final mrp = line.unitMrp;
    final onSale = mrp > line.unitPrice;
    // On a phone-width screen (or with enlarged system text) the title and the
    // stepper cannot share a row without the title being cut to a few letters,
    // so the stepper drops below the details.
    final roomy = MediaQuery.textScalerOf(context).scale(14) / 14 <= 1.2 &&
        MediaQuery.sizeOf(context).width >= 420;

    return Container(
      color: c.surface,
      padding: const EdgeInsets.all(DsSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: DsRadius.controlAll,
            child: Container(
              width: 64,
              height: 64,
              color: c.surfaceSunken,
              child: Image.network(
                line.product.image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                    Icons.image_not_supported_outlined,
                    size: 20,
                    color: c.inkSubtle),
              ),
            ),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DsText.base,
                    fontWeight: DsWeight.bold,
                    color: c.ink,
                  ),
                ),
                if (line.variant != null &&
                    line.variant!.label.isNotEmpty &&
                    line.product.variants.length > 1)
                  Text(line.variant!.label,
                      style:
                          TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                OptionPicks(picks: line.picks),
                const SizedBox(height: DsSpace.s1),
                Wrap(
                  spacing: DsSpace.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatMoney(line.lineTotal),
                      style: TextStyle(
                        fontSize: DsText.base,
                        fontWeight: DsWeight.black,
                        color: c.ink,
                      ),
                    ),
                    if (onSale)
                      Text(
                        formatMoney(mrp * line.quantity),
                        style: TextStyle(
                          fontSize: DsText.sm,
                          color: c.inkSubtle,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                  ],
                ),
                if (!roomy) ...[
                  const SizedBox(height: DsSpace.s2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _QtyStepper(line: line, onRemove: onRemove),
                  ),
                ],
              ],
            ),
          ),
          if (roomy) ...[
            const SizedBox(width: DsSpace.s2),
            _QtyStepper(line: line, onRemove: onRemove),
          ],
        ],
      ),
    );
  }
}

/// "Add X and save" — shown when the cart holds one half of a bundle.
class _BundleHint extends StatelessWidget {
  final Bundle bundle;
  final List<CartLine> cart;

  const _BundleHint({required this.bundle, required this.cart});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final inCart = cart.map((l) => l.product.id).toSet();
    final partner =
        inCart.contains(bundle.primary.id) ? bundle.secondary : bundle.primary;

    return BxCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProductDetailScreen(productId: partner.id))),
      child: Row(
        children: [
          Icon(Icons.local_offer_outlined, color: c.accent),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add ${partner.title} and save ${formatMoney(bundle.savings)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: DsText.base,
                        fontWeight: DsWeight.bold,
                        color: c.ink)),
                Text('Bundle price ${formatMoney(bundle.price)} for both',
                    style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.inkSubtle),
        ],
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final CartLine line;
  final VoidCallback onRemove;

  const _QtyStepper({required this.line, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final maxQuantity = (line.variant?.stock ?? 0).clamp(0, 20);
    return BxQuantityStepper(
      quantity: line.quantity,
      maxQuantity: maxQuantity,
      onChanged: (q) => AppState.instance.updateQuantity(line.key, q),
      onRemove: onRemove,
    );
  }
}


/// "Ordering from Sharma Kirana": whose goods these are, whether the shop is
/// taking orders, and how far the basket is from its minimum.
class _ShopStrip extends StatelessWidget {
  final Shop shop;
  final double subtotal;
  final VoidCallback onOpen;

  const _ShopStrip({required this.shop, required this.subtotal, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final minimum = shop.minOrder;
    final short = (minimum - subtotal).clamp(0, double.infinity);
    final reached = minimum <= 0 || short <= 0.004;

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: ShopPicture(shop: shop),
                  ),
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ordering from',
                          style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                      Text(shop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: DsText.base,
                              fontWeight: DsWeight.bold,
                              color: c.ink)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: c.inkSubtle),
              ],
            ),
          ),
          if (!shop.isOpen) ...[
            const SizedBox(height: DsSpace.s3),
            BxAlert(
              '${shop.closedText ?? 'Closed right now'}. You can keep your basket and order when it opens.',
              title: 'Shop is closed',
              tone: BxTone.warning,
            ),
          ] else if (minimum > 0) ...[
            const SizedBox(height: DsSpace.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (subtotal / minimum).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: c.line,
                color: reached ? c.success : c.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              reached
                  ? 'Minimum order of ${formatMoney(minimum)} reached'
                  : 'Add ${formatMoney(short.toDouble())} more for the minimum order of ${formatMoney(minimum)}',
              style: TextStyle(
                  fontSize: DsText.sm,
                  color: reached ? c.success : c.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
