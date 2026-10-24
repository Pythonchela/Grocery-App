import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../document_picker.dart';
import 'product_form_screen.dart';
import 'shop_profile_screen.dart';
import '../seller_api.dart';
import '../seller_format.dart';
import '../seller_models.dart';
import '../validators.dart';
import '../widgets/seller_widgets.dart';

/// The shop at a glance: what you're owed, what needs shipping, and the
/// contact details shoppers and the marketplace use to reach you.
class OverviewTab extends StatefulWidget {
  final SellerApi api;

  /// For the shop page's logo and banner.
  final DocumentPicker picker;

  /// Jump to another dashboard tab (orders, earnings) from a card.
  final ValueChanged<int> onOpenTab;

  /// Fires when something the counts depend on changed elsewhere (an item was
  /// packed or shipped), so the overview reloads.
  final Listenable? changes;

  const OverviewTab({super.key, required this.api, required this.picker, required this.onOpenTab, this.changes});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _Overview {
  final SellerProfile profile;
  final int toPack;
  final List<SellerOrderItem> recent;

  const _Overview(this.profile, this.toPack, this.recent);
}

class _OverviewTabState extends State<OverviewTab> {
  _Overview? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        widget.api.me(),
        widget.api.orderItems(stage: 'to_pack'),
        widget.api.orderItems(),
      ]);

      if (!mounted) return;
      setState(() {
        _data = _Overview(
          results[0] as SellerProfile,
          (results[1] as ListPage<SellerOrderItem>).total,
          (results[2] as ListPage<SellerOrderItem>).items.take(3).toList(),
        );
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your shop. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  Future<void> _addProduct() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ProductFormScreen(api: widget.api, picker: widget.picker),
    ));
    if (changed == true && mounted) _load();
  }

  Future<void> _editShop(SellerProfile p) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ShopProfileScreen(api: widget.api, picker: widget.picker, shop: p.shop),
    ));
    if (saved == true && mounted) _load();
  }

  /// The one-tap pause: flips "taking orders" and saves it straight away.
  Future<void> _toggleOrders(SellerProfile p, bool accepting) async {
    try {
      await widget.api.updateShop(p.shop.withAccepting(accepting));
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Could not reach the server. Try again.')));
      }
    }
  }

  Future<void> _pause(int minutes) => _deskCall(() => widget.api.pauseShop(minutes));

  Future<void> _setAutoAccept(bool auto) => _deskCall(() => widget.api.setAutoAccept(auto));

  Future<void> _deskCall(Future<void> Function() call) async {
    try {
      await call();
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach the server. Try again.')));
    }
  }

  int _minutesUntilTomorrow() {
    final now = DateTime.now();
    final nine = DateTime(now.year, now.month, now.day + 1, 9);
    return nine.difference(now).inMinutes.clamp(1, 10080);
  }

  Future<void> _editPickup(SellerProfile p) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickupSheet(api: widget.api, address: p.pickup),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _editProfile(SellerProfile p) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProfileSheet(api: widget.api, profile: p),
    );
    if (saved == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final d = _data;

    return RefreshIndicator(
      onRefresh: _load,
      color: c.accent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(DsSpace.s4),
        children: [
          if (_loading && d == null)
            const Column(children: [
              BxSkeleton(height: 96, radius: DsRadius.cardAll),
              SizedBox(height: DsSpace.s3),
              BxSkeleton(height: 96, radius: DsRadius.cardAll),
            ])
          else if (_error != null && d == null)
            SellerLoadError(message: _error!, onRetry: _load)
          else if (d != null) ...[
            Row(children: [
              Expanded(
                child: BxButton(
                  key: const Key('quick-add-product'),
                  label: 'Add product',
                  size: BxButtonSize.sm,
                  leadingIcon: Icons.add,
                  onPressed: _addProduct,
                ),
              ),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: BxButton(
                  key: const Key('quick-orders'),
                  label: 'Orders',
                  size: BxButtonSize.sm,
                  leadingIcon: Icons.local_shipping_outlined,
                  variant: BxButtonVariant.secondary,
                  onPressed: () => widget.onOpenTab(1),
                ),
              ),
            ]),
            const SizedBox(height: DsSpace.s4),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Payout balance',
                    value: SellerFormat.moneyWhole(d.profile.payoutBalance),
                    icon: Icons.account_balance_wallet_outlined,
                    onTap: () => widget.onOpenTab(3),
                  ),
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: _Stat(
                    label: 'To pack',
                    value: '${d.toPack}',
                    icon: Icons.local_shipping_outlined,
                    onTap: () => widget.onOpenTab(1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DsSpace.s3),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Products',
                    value: '${d.profile.productCount}',
                    icon: Icons.inventory_2_outlined,
                    onTap: () => widget.onOpenTab(2),
                  ),
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: _Stat(
                    label: 'Commission',
                    value: '${_trim(d.profile.commissionRate)}%',
                    icon: Icons.percent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DsSpace.s5),
            const SellerSectionTitle('Recent orders'),
            if (d.recent.isEmpty)
              BxCard(
                child: Text(
                  'No orders yet. They will appear here as soon as a shopper buys from you.',
                  style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
                ),
              )
            else
              for (final o in d.recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s2),
                  child: BxCard(
                    onTap: () => widget.onOpenTab(1),
                    child: Row(
                      children: [
                        SellerThumb(url: o.image, size: 44),
                        const SizedBox(width: DsSpace.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(o.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink)),
                              Text('${o.orderNumber} · ${o.quantity} × ${SellerFormat.money(o.price)}',
                                  style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
                            ],
                          ),
                        ),
                        Text(SellerFormat.money(o.earning),
                            style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.black, color: c.success)),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: DsSpace.s5),
            const SellerSectionTitle('Shop details'),
            BxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SellerKeyValue('Shop name', d.profile.displayName),
                  SellerKeyValue('Support email', d.profile.supportEmail ?? ''),
                  SellerKeyValue('Support phone', d.profile.supportPhone ?? ''),
                  const SizedBox(height: DsSpace.s2),
                  BxButton(
                    label: 'Edit details',
                    leadingIcon: Icons.edit_outlined,
                    variant: BxButtonVariant.secondary,
                    size: BxButtonSize.sm,
                    onPressed: () => _editProfile(d.profile),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DsSpace.s5),
            const SellerSectionTitle('Shop page',
                subtitle: 'How shoppers see your shop, and when you take orders.'),
            BxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(d.profile.shop.acceptingOrders ? 'Taking orders' : 'Paused'),
                    subtitle: Text(!d.profile.shop.acceptingOrders
                        ? 'Shoppers can look, but cannot order.'
                        : d.profile.shop.isOpen
                            ? 'Open now'
                            : (d.profile.shop.closedText ?? 'Closed right now')),
                    value: d.profile.shop.acceptingOrders,
                    onChanged: (v) => _toggleOrders(d.profile, v),
                  ),
                  SwitchListTile(
                    key: const Key('confirm-each-order'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Confirm each order myself'),
                    subtitle: const Text('Off: orders are accepted automatically. On: each new order waits for you, and is cancelled if you do not answer in time.'),
                    value: !d.profile.shop.autoAccept,
                    onChanged: (v) => _setAutoAccept(!v),
                  ),
                  Wrap(spacing: DsSpace.s2, children: [
                    if (d.profile.shop.pausedUntil != null && d.profile.shop.pausedUntil!.isAfter(DateTime.now()))
                      ActionChip(
                        label: Text('Paused until ${SellerFormat.dateTime(d.profile.shop.pausedUntil)} · Resume'),
                        onPressed: () => _pause(0),
                      )
                    else ...[
                      ActionChip(label: const Text('Pause 30 min'), onPressed: () => _pause(30)),
                      ActionChip(label: const Text('Pause 1 hour'), onPressed: () => _pause(60)),
                      ActionChip(label: const Text('Pause till tomorrow'), onPressed: () => _pause(_minutesUntilTomorrow())),
                    ],
                  ]),
                  if (d.profile.shop.minOrderAmount > 0)
                    SellerKeyValue('Minimum order', '₹${_trim(d.profile.shop.minOrderAmount)}'),
                  if (d.profile.shop.servicePincodes.isNotEmpty)
                    SellerKeyValue('Delivers to', '${d.profile.shop.servicePincodes.length} PIN codes'),
                  const SizedBox(height: DsSpace.s3),
                  BxButton(
                    label: 'Edit shop page',
                    leadingIcon: Icons.storefront_outlined,
                    variant: BxButtonVariant.secondary,
                    size: BxButtonSize.sm,
                    onPressed: () => _editShop(d.profile),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DsSpace.s5),
            const SellerSectionTitle('Pickup address',
                subtitle: 'Where couriers collect your orders. Delivery times and fees are worked out from here.'),
            BxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.profile.pickup.isSet) ...[
                    SellerKeyValue('Address', d.profile.pickup.oneLine),
                    if ((d.profile.pickup.phone ?? '').isNotEmpty)
                      SellerKeyValue('Phone at pickup', d.profile.pickup.phone!),
                  ] else
                    const BxAlert(
                      'Not set. Until you add it, your orders are collected from the marketplace warehouse, '
                      'so delivery estimates may be wrong for shoppers near you.',
                      tone: BxTone.warning,
                    ),
                  const SizedBox(height: DsSpace.s3),
                  BxButton(
                    label: d.profile.pickup.isSet ? 'Change pickup address' : 'Add pickup address',
                    leadingIcon: Icons.location_on_outlined,
                    variant: BxButtonVariant.secondary,
                    size: BxButtonSize.sm,
                    onPressed: () => _editPickup(d.profile),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 10.0 → "10", 12.5 → "12.5".
  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _Stat({required this.label, required this.value, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return BxCard(
      onTap: onTap,
      padding: const EdgeInsets.all(DsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.accent),
          const SizedBox(height: DsSpace.s2),
          Text(value, style: TextStyle(fontSize: DsText.xl, fontWeight: DsWeight.black, color: c.ink)),
          Text(label, style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
        ],
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final SellerApi api;
  final SellerProfile profile;

  const _EditProfileSheet({required this.api, required this.profile});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.profile.displayName);
  late final _email = TextEditingController(text: widget.profile.supportEmail ?? '');
  late final _phone = TextEditingController(text: widget.profile.supportPhone ?? '');
  bool _busy = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll({
          if (SellerValidators.required(_name.text, 'your shop name') case final e?) 'display_name': e,
          if (SellerValidators.optionalEmail(_email.text) case final e?) 'support_email': e,
          if (SellerValidators.optionalPhone(_phone.text) case final e?) 'support_phone': e,
        });
      _error = null;
    });
    if (_fieldErrors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await widget.api.updateProfile(
        displayName: _name.text.trim(),
        supportEmail: _email.text.trim(),
        supportPhone: _phone.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final f in ['display_name', 'support_email', 'support_phone']) {
          final msg = e.fieldError(f);
          if (msg != null) _fieldErrors[f] = msg;
        }
        _error = e.errors == null ? e.message : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keeps the form above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DsSpace.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SellerSectionTitle('Edit shop details', subtitle: 'Commission and account status are set by the marketplace.'),
            if (_error != null) ...[
              BxAlert(_error!, tone: BxTone.danger),
              const SizedBox(height: DsSpace.s3),
            ],
            BxField(label: 'Shop name', controller: _name, error: _fieldErrors['display_name'], enabled: !_busy),
            const SizedBox(height: DsSpace.s3),
            BxField(
              label: 'Support email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              error: _fieldErrors['support_email'],
              enabled: !_busy,
            ),
            const SizedBox(height: DsSpace.s3),
            BxField(
              label: 'Support phone',
              controller: _phone,
              keyboardType: TextInputType.phone,
              error: _fieldErrors['support_phone'],
              enabled: !_busy,
            ),
            const SizedBox(height: DsSpace.s5),
            BxButton(label: 'Save', fullWidth: true, loading: _busy, onPressed: _busy ? null : _save),
            const SizedBox(height: DsSpace.s2),
          ],
        ),
      ),
    );
  }
}

/// Where couriers collect from. Street and PIN are what delivery needs; the
/// rest helps the courier find the door.
class _PickupSheet extends StatefulWidget {
  final SellerApi api;
  final PickupAddress address;

  const _PickupSheet({required this.api, required this.address});

  @override
  State<_PickupSheet> createState() => _PickupSheetState();
}

class _PickupSheetState extends State<_PickupSheet> {
  late final _line1 = TextEditingController(text: widget.address.line1 ?? '');
  late final _city = TextEditingController(text: widget.address.city ?? '');
  late final _state = TextEditingController(text: widget.address.state ?? '');
  late final _pin = TextEditingController(text: widget.address.pincode ?? '');
  late final _phone = TextEditingController(text: widget.address.phone ?? '');
  bool _busy = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  static const _keys = {
    'pickup_line1': 'line1',
    'pickup_city': 'city',
    'pickup_state': 'state',
    'pickup_pincode': 'pincode',
    'pickup_phone': 'phone',
  };

  @override
  void dispose() {
    for (final c in [_line1, _city, _state, _pin, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll({
          if (SellerValidators.required(_line1.text, 'the street address') case final e?) 'line1': e,
          if (SellerValidators.required(_city.text, 'the city') case final e?) 'city': e,
          if (SellerValidators.pincode(_pin.text) case final e?) 'pincode': e,
          if (SellerValidators.optionalPhone(_phone.text) case final e?) 'phone': e,
        });
      _error = null;
    });
    if (_fieldErrors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await widget.api.updatePickup(PickupAddress(
        line1: _line1.text,
        city: _city.text,
        state: _state.text,
        pincode: _pin.text,
        phone: _phone.text,
      ));
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final entry in _keys.entries) {
          final msg = e.fieldError(entry.key);
          if (msg != null) _fieldErrors[entry.value] = msg;
        }
        _error = e.errors == null ? e.message : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DsSpace.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SellerSectionTitle('Pickup address',
                subtitle: 'Where couriers collect your orders from.'),
            if (_error != null) ...[
              BxAlert(_error!, tone: BxTone.danger),
              const SizedBox(height: DsSpace.s3),
            ],
            BxField(label: 'Street address', controller: _line1, error: _fieldErrors['line1'], enabled: !_busy),
            const SizedBox(height: DsSpace.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: BxField(label: 'City', controller: _city, error: _fieldErrors['city'], enabled: !_busy)),
                const SizedBox(width: DsSpace.s3),
                Expanded(child: BxField(label: 'State', controller: _state, error: _fieldErrors['state'], enabled: !_busy)),
              ],
            ),
            const SizedBox(height: DsSpace.s3),
            BxField(
              label: 'PIN code',
              controller: _pin,
              keyboardType: TextInputType.number,
              error: _fieldErrors['pincode'],
              enabled: !_busy,
            ),
            const SizedBox(height: DsSpace.s3),
            BxField(
              label: 'Phone at pickup',
              controller: _phone,
              keyboardType: TextInputType.phone,
              helper: 'The courier calls this number on arrival.',
              error: _fieldErrors['phone'],
              enabled: !_busy,
            ),
            const SizedBox(height: DsSpace.s5),
            BxButton(label: 'Save', fullWidth: true, loading: _busy, onPressed: _busy ? null : _save),
            const SizedBox(height: DsSpace.s2),
          ],
        ),
      ),
    );
  }
}
