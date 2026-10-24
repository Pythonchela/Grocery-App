import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/payments.dart';
import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/mobile_components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'address_screen.dart';
import '../widgets/delivery_widgets.dart';
import 'order_tracking_screen.dart';

/// The money path: address → delivery speed → discounts → place.
///
/// Every figure shown here is advisory. The server re-prices the delivery fee,
/// re-validates the coupon, re-caps the loyalty redemption and recomputes the
/// total when the order is placed — so a tampered client gets a correct order,
/// not a cheap one. This screen's job is to make the outcome predictable, not
/// to be authoritative.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  Address? _address;
  List<DeliveryOption> _options = [];
  DeliveryOption? _selectedOption;

  String _paymentMethod = 'UPI';
  final _couponController = TextEditingController();
  String? _appliedCoupon;
  double _couponDiscount = 0;
  String? _couponError;
  bool _checkingCoupon = false;

  bool _useWallet = false;
  int _redeemPoints = 0;

  /// "Leave at the door", "Call on arrival" - what the delivery partner reads.
  final _instructionsController = TextEditingController();
  final Set<String> _instructionChips = {};

  bool _loadingAddress = true;
  bool _quoting = false;
  bool _placing = false;
  String? _error;
  bool _sandboxDelivery = false;
  int _quoteId = 0;

  @override
  void initState() {
    super.initState();
    _loadDefaultAddress();
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadDefaultAddress() async {
    try {
      final data =
          await ApiClient.request('/addresses', token: AppState.instance.token)
              as List;
      if (!mounted) return;

      final addresses = data.map((a) => Address.fromJson(a)).toList();
      setState(() {
        _address = addresses.where((a) => a.isDefault).firstOrNull ??
            (addresses.isNotEmpty ? addresses.first : null);
        _loadingAddress = false;
      });

      if (_address != null) await _quote();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingAddress = false;
      });
    }
  }

  /// Why nothing can be offered, when the server says (a mixed basket).
  String? _noDeliveryReason;

  /// Parcels the order ships as (one per seller pickup point).
  int _parcels = 1;

  Future<void> _quote() async {
    final address = _address;
    if (address == null) return;
    final quoteId = ++_quoteId;

    setState(() {
      _quoting = true;
      _options = [];
      _selectedOption = null;
      _error = null;
    });

    try {
      final data = await ApiClient.request(
        '/delivery/quote',
        method: 'POST',
        body: {
          'pincode': address.pincode,
          'cod': _paymentMethod == 'COD',
          'order_value': AppState.instance.cartNetSubtotal - _couponDiscount,
          'items': AppState.instance.cart
              .map((l) => {'product_id': l.product.id, 'quantity': l.quantity})
              .toList(),
        },
      ) as Map<String, dynamic>;

      if (!mounted || quoteId != _quoteId) return;

      final options = ((data['options'] as List?) ?? [])
          .map((o) => DeliveryOption.fromJson(o as Map<String, dynamic>))
          .toList();

      setState(() {
        _options = options;
        _sandboxDelivery = data['sandbox'] == true;
        _noDeliveryReason = data['message'] as String?;
        _parcels = ((data['parcels'] as List?)?.length ?? 1).clamp(1, 99);
        // Pre-select what the server recommends: the cheapest for ordinary
        // goods (the fastest is an upsell, and pre-selecting it charges people
        // for a choice they did not make) but the fastest for things that only
        // travel quickly, like hot food.
        final recommended = data['recommended_service_level'];
        _selectedOption = options.isEmpty
            ? null
            : options.where((o) => o.serviceLevel == recommended).firstOrNull ??
                options.reduce((a, b) => a.price <= b.price ? a : b);
        _quoting = false;
      });
    } catch (e) {
      if (!mounted || quoteId != _quoteId) return;
      setState(() {
        _error = e.toString();
        _quoting = false;
      });
    }
  }

  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _checkingCoupon = true;
      _couponError = null;
    });

    try {
      final data = await ApiClient.request(
        '/coupons/preview',
        method: 'POST',
        token: AppState.instance.token,
        body: {
          'code': code,
          'items': AppState.instance.cart
              .map((l) => l.toRequest())
              .toList(),
        },
      ) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _appliedCoupon = code.toUpperCase();
        _couponDiscount = (data['discount'] as num?)?.toDouble() ?? 0;
        _checkingCoupon = false;
      });

      // Free-shipping thresholds are computed on the post-discount value, so a
      // coupon can change which delivery options are free.
      await _quote();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _couponError = e.toString();
        _appliedCoupon = null;
        _couponDiscount = 0;
        _checkingCoupon = false;
      });
    }
  }

  void _removeCoupon() {
    setState(() {
      _appliedCoupon = null;
      _couponDiscount = 0;
      _couponController.clear();
      _couponError = null;
    });
    _quote();
  }

  // ── Delivery instructions ──────────────────────────────────────────────────

  static const _chipOptions = [
    'Leave at the door',
    "Don't ring the bell",
    'Call on arrival',
    'Hand it to me',
  ];

  /// The chips and free text, joined and held to what the API accepts.
  String get _deliveryInstructions {
    final parts = [
      ..._chipOptions.where(_instructionChips.contains),
      _instructionsController.text.trim(),
    ].where((p) => p.isNotEmpty);
    final joined = parts.join('. ');
    return joined.length > 200 ? joined.substring(0, 200) : joined;
  }

  // ── Totals ─────────────────────────────────────────────────────────────────

  double get _subtotal => AppState.instance.cartSubtotal;

  /// Estimated bundle saving; the coupon preview and the order are priced by the
  /// server on what is left after it.
  double get _bundleDiscount => AppState.instance.cartBundleDiscount;
  double get _delivery => _selectedOption?.price ?? 0;

  /// 1 point = ₹0.25, matching the server's default rate. Re-capped server-side
  /// at checkout, so this is a preview and never the authority.
  double get _pointsValue => _redeemPoints * 0.25;

  double get _payableBeforeWallet =>
      (_subtotal - _bundleDiscount - _couponDiscount + _delivery - _pointsValue)
          .clamp(0, double.infinity);

  double get _walletApplied {
    if (!_useWallet) return 0;
    final balance = AppState.instance.user?.walletBalance ?? 0;
    return balance < _payableBeforeWallet ? balance : _payableBeforeWallet;
  }

  double get _total =>
      (_payableBeforeWallet - _walletApplied).clamp(0, double.infinity);

  // ── Place ──────────────────────────────────────────────────────────────────

  Future<void> _placeOrder() async {
    final address = _address;
    final option = _selectedOption;

    if (address == null ||
        option == null ||
        _placing ||
        _quoting ||
        AppState.instance.cart.isEmpty) {
      return;
    }

    setState(() {
      _placing = true;
      _error = null;
    });

    try {
      final items = AppState.instance.cart
          .map((l) => l.toRequest())
          .toList();

      // Everything that moves the price, sent identically to the quote and to
      // checkout: the server pins the quote to this exact cart and refuses the
      // order if any of it differs.
      final pricing = {
        'items': items,
        'payment_method': _paymentMethod,
        'service_level': option.serviceLevel,
        if (_appliedCoupon != null) 'coupon_code': _appliedCoupon,
        'use_wallet': _useWallet,
        'redeem_points': _redeemPoints,
      };

      // Prepaid orders must be paid before they can be placed. The server
      // prices the cart and opens the payment; COD skips all of this.
      var paymentEvidence = <String, dynamic>{};
      if (_paymentMethod != 'COD') {
        final intent = await ApiClient.request(
          '/payments/intent',
          method: 'POST',
          token: AppState.instance.token,
          body: {...pricing, 'pincode': address.pincode},
        ) as Map<String, dynamic>;

        paymentEvidence = {'payment_intent_id': intent['payment_intent_id']};

        // Whichever gateway issued the intent decides what happens here; the
        // sandbox and ₹0 orders have nothing to collect and return null.
        final payment = await Payments.collect(
          intent,
          description: '${AppState.instance.cart.length} item(s)',
          contact: address.phone,
          email: AppState.instance.user?.email,
        );
        if (payment != null) paymentEvidence['payment'] = payment;
      }

      final order = await ApiClient.request(
        '/orders/checkout',
        method: 'POST',
        token: AppState.instance.token,
        body: {
          ...pricing,
          'shipping_address': {
            ...address.toShippingAddress(),
            if (_deliveryInstructions.isNotEmpty)
              'instructions': _deliveryInstructions,
          },
          ...paymentEvidence,
        },
      ) as Map<String, dynamic>;

      if (!mounted) return;

      AppState.instance.clearCart();
      await AppState.instance.refreshUser();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(
              orderId: order['id'] as String, justPlaced: true),
        ),
      );
    } on PaymentCancelled {
      // Closing the payment sheet is the shopper's choice, not an error.
      if (!mounted) return;
      setState(() => _placing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _placing = false;
      });
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final user = AppState.instance.user;
    final canPlace = _address != null &&
        _selectedOption != null &&
        !_placing &&
        !_quoting &&
        AppState.instance.cart.isNotEmpty &&
        (_paymentMethod != 'COD' ||
            (_selectedOption!.codSupported &&
                AppState.instance.cart
                    .every((line) => line.product.codAvailable)));

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s6),
        children: [
          if (_error != null) ...[
            BxAlert(_error!,
                title: 'Could not complete checkout', tone: BxTone.danger),
            const SizedBox(height: DsSpace.s4),
          ],
          if (_selectedOption != null && !_quoting) ...[
            EtaHero(
                option: _selectedOption!,
                itemCount: AppState.instance.cartCount,
                parcels: _parcels),
            const SizedBox(height: DsSpace.s2),
          ],
          const _SectionTitle('Deliver to'),
          if (_loadingAddress)
            const BxSkeleton(height: 92, radius: DsRadius.cardAll)
          else if (_address == null)
            BxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No delivery address yet',
                    style: TextStyle(
                      fontSize: DsText.base,
                      fontWeight: DsWeight.bold,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: DsSpace.s3),
                  BxButton(
                    label: 'Add an address',
                    size: BxButtonSize.sm,
                    onPressed: _pickAddress,
                  ),
                ],
              ),
            )
          else
            BxCard(
              onTap: _pickAddress,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_address!.tag?.isNotEmpty == true) ...[
                              BxBadge(_address!.tag!, tone: BxTone.accent),
                              const SizedBox(width: DsSpace.s2),
                            ],
                            Text(
                              _address!.name,
                              style: TextStyle(
                                fontSize: DsText.base,
                                fontWeight: DsWeight.black,
                                color: c.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _address!.oneLine,
                          style: TextStyle(
                              fontSize: DsText.base, color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.inkSubtle),
                ],
              ),
            ),
          const _SectionTitle('How fast do you want it?'),
          if (_quoting)
            const Column(
              children: [
                BxSkeleton(height: 84, radius: DsRadius.cardAll),
                SizedBox(height: DsSpace.s2),
                BxSkeleton(height: 84, radius: DsRadius.cardAll),
              ],
            )
          else if (_options.isEmpty)
            BxAlert(
              _address == null
                  ? 'Choose an address to see delivery options.'
                  : (_noDeliveryReason ?? 'No courier currently serves this pincode.'),
              tone: BxTone.warning,
            )
          else ...[
            ..._options.map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s2),
                  child: DeliverySpeedCard(
                    option: o,
                    selected: o.serviceLevel == _selectedOption?.serviceLevel,
                    fastest: _options.length > 1 && o == _fastest,
                    cheapest: _options.length > 1 && o == _cheapest,
                    onTap: () => setState(() => _selectedOption = o),
                  ),
                )),
            if (_sandboxDelivery) ...[
              const SizedBox(height: DsSpace.s1),
              Text(
                'Sandbox courier pricing — no carrier account is connected, so these '
                'rates are representative rather than live quotes.',
                style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle),
              ),
            ],
          ],
          const _SectionTitle('Delivery instructions'),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s2,
            children: [
              for (final option in _chipOptions)
                FilterChip(
                  label: Text(option),
                  selected: _instructionChips.contains(option),
                  showCheckmark: false,
                  onSelected: (on) => setState(() => on
                      ? _instructionChips.add(option)
                      : _instructionChips.remove(option)),
                ),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          BxField(
            label: 'Anything else the delivery partner should know?',
            hint: 'e.g. Gate code 4821, 3rd floor',
            controller: _instructionsController,
            maxLines: 2,
          ),
          const _SectionTitle('Payment method'),
          BxTabs(
            tabs: const [
              BxTab('UPI', 'UPI'),
              BxTab('CARD', 'Card'),
              BxTab('NETBANKING', 'Netbanking'),
              BxTab('COD', 'Cash'),
            ],
            value: _paymentMethod,
            onChanged: (v) {
              setState(() => _paymentMethod = v);
              // COD changes which carriers will take the job — rider networks
              // do not collect cash — so the options must be re-quoted.
              _quote();
            },
          ),
          if (_paymentMethod == 'COD' &&
              _selectedOption?.codSupported == false) ...[
            const SizedBox(height: DsSpace.s3),
            const BxAlert(
              'The selected delivery speed cannot collect cash. Pick another speed or pay online.',
              tone: BxTone.warning,
            ),
          ],
          if (_paymentMethod == 'COD')
            for (final line in AppState.instance.cart
                .where((l) => !l.product.codAvailable)) ...[
              const SizedBox(height: DsSpace.s3),
              BxAlert(
                "Cash on delivery isn't available for ${line.product.title}. "
                'Pay online, or remove it from your cart.',
                tone: BxTone.warning,
              ),
            ],
          const _SectionTitle('Coupon'),
          if (_appliedCoupon != null)
            BxCard(
              child: Row(
                children: [
                  Icon(Icons.local_offer_outlined, size: 18, color: c.success),
                  const SizedBox(width: DsSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _appliedCoupon!,
                          style: TextStyle(
                            fontFamily: DsFont.mono,
                            fontSize: DsText.base,
                            fontWeight: DsWeight.bold,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          'You save ${formatMoney(_couponDiscount)}',
                          style:
                              TextStyle(fontSize: DsText.xs, color: c.success),
                        ),
                      ],
                    ),
                  ),
                  BxButton(
                    label: 'Remove',
                    variant: BxButtonVariant.ghost,
                    size: BxButtonSize.xs,
                    onPressed: _removeCoupon,
                  ),
                ],
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: BxField(
                    label: 'Have a code?',
                    hint: 'BHARAT15',
                    controller: _couponController,
                    error: _couponError,
                    onSubmitted: (_) => _applyCoupon(),
                  ),
                ),
                const SizedBox(width: DsSpace.s3),
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: BxButton(
                    label: 'Apply',
                    variant: BxButtonVariant.secondary,
                    loading: _checkingCoupon,
                    onPressed: _checkingCoupon ? null : _applyCoupon,
                  ),
                ),
              ],
            ),
          if (user != null &&
              (user.walletBalance > 0 || user.loyaltyPoints > 0)) ...[
            const _SectionTitle('Use your balance'),
            if (user.walletBalance > 0)
              BxCard(
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 18, color: c.accent),
                    const SizedBox(width: DsSpace.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DsBrand.walletName,
                            style: TextStyle(
                              fontSize: DsText.base,
                              fontWeight: DsWeight.bold,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            'Balance ${formatMoney(user.walletBalance)}',
                            style: TextStyle(
                                fontSize: DsText.xs, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _useWallet,
                      activeThumbColor: c.accent,
                      onChanged: (v) => setState(() => _useWallet = v),
                    ),
                  ],
                ),
              ),
            if (user.loyaltyPoints > 0) ...[
              const SizedBox(height: DsSpace.s2),
              BxCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.stars_outlined, size: 18, color: c.rating),
                        const SizedBox(width: DsSpace.s3),
                        Expanded(
                          child: Text(
                            '${DsBrand.loyaltyName} — ${user.loyaltyPoints} available',
                            style: TextStyle(
                              fontSize: DsText.base,
                              fontWeight: DsWeight.bold,
                              color: c.ink,
                            ),
                          ),
                        ),
                        Text(
                          _redeemPoints == 0
                              ? '—'
                              : '-${formatMoney(_pointsValue)}',
                          style: TextStyle(
                            fontSize: DsText.base,
                            fontWeight: DsWeight.bold,
                            color: _redeemPoints == 0 ? c.inkSubtle : c.success,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _redeemPoints.toDouble(),
                      max: user.loyaltyPoints.toDouble(),
                      divisions:
                          user.loyaltyPoints > 0 ? user.loyaltyPoints : null,
                      activeColor: c.accent,
                      label: '$_redeemPoints points',
                      onChanged: (v) =>
                          setState(() => _redeemPoints = v.round()),
                    ),
                    Text(
                      'The server re-caps this against the payable amount, so you can never '
                      'redeem more than the order is worth.',
                      style:
                          TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const _SectionTitle('Summary'),
          BxCard(
            child: Column(
              children: [
                _SummaryRow('Subtotal', formatMoney(_subtotal)),
                if (_bundleDiscount > 0) ...[
                  const SizedBox(height: DsSpace.s2),
                  _SummaryRow('Bundle savings', '-${formatMoney(_bundleDiscount)}',
                      valueColor: c.success),
                ],
                if (_couponDiscount > 0) ...[
                  const SizedBox(height: DsSpace.s2),
                  _SummaryRow('Coupon', '-${formatMoney(_couponDiscount)}',
                      valueColor: c.success),
                ],
                if (_pointsValue > 0) ...[
                  const SizedBox(height: DsSpace.s2),
                  _SummaryRow('Points', '-${formatMoney(_pointsValue)}',
                      valueColor: c.success),
                ],
                const SizedBox(height: DsSpace.s2),
                _SummaryRow(
                  _selectedOption == null
                      ? 'Delivery'
                      : 'Delivery — ${_selectedOption!.label}',
                  _selectedOption == null
                      ? '—'
                      : (_selectedOption!.isFree
                          ? 'Free'
                          : formatMoney(_delivery)),
                  valueColor:
                      _selectedOption?.isFree == true ? c.success : null,
                ),
                if (_walletApplied > 0) ...[
                  const SizedBox(height: DsSpace.s2),
                  _SummaryRow('Wallet', '-${formatMoney(_walletApplied)}',
                      valueColor: c.success),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DsSpace.s3),
                  child: Divider(height: 1, color: c.line),
                ),
                _SummaryRow('To pay', formatMoney(_total), bold: true),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BxBottomBar(
        child: BxTotalAction(
          label: 'To pay',
          amount: formatMoney(_total),
          button: BxButton(
            label: 'Place order',
            size: BxButtonSize.lg,
            fullWidth: true,
            loading: _placing,
            onPressed: canPlace ? _placeOrder : null,
          ),
        ),
      ),
    );
  }

  DeliveryOption? get _fastest => _options.isEmpty
      ? null
      : _options.reduce((a, b) => a.etaMinutes <= b.etaMinutes ? a : b);

  DeliveryOption? get _cheapest => _options.isEmpty
      ? null
      : _options.reduce((a, b) => a.price <= b.price ? a : b);

  Future<void> _pickAddress() async {
    final picked = await Navigator.of(context).push<Address>(
      MaterialPageRoute(builder: (_) => const AddressScreen(selectMode: true)),
    );

    if (picked != null) {
      setState(() => _address = picked);
      await _quote();
    } else {
      // They may have added their first address without picking one.
      await _loadDefaultAddress();
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DsSpace.s6, bottom: DsSpace.s3),
      child: Text(
        text,
        style: TextStyle(
          fontSize: DsText.lg,
          fontWeight: DsWeight.black,
          color: context.ds.ink,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _SummaryRow(this.label, this.value,
      {this.bold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
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
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? DsText.md : DsText.base,
            fontWeight: bold ? DsWeight.black : DsWeight.bold,
            color: valueColor ?? c.ink,
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
