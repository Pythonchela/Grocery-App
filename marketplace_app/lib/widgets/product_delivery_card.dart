import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/cart_delivery.dart';
import '../data/models.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// "Delivery details" on a product page: where it would go, when it would
/// arrive, and who is selling it.
///
/// The date comes from the same delivery quote the cart uses, for the shopper's
/// default address, so it is the real promise rather than a guess. Signed out,
/// or with no address yet, it says how the item is delivered in general instead.
/// Display only: checkout quotes again with the final choices.
class ProductDeliveryCard extends StatefulWidget {
  final Product product;

  const ProductDeliveryCard({super.key, required this.product});

  @override
  State<ProductDeliveryCard> createState() => _ProductDeliveryCardState();
}

class _ProductDeliveryCardState extends State<ProductDeliveryCard> {
  Address? _address;
  DeliveryOption? _option;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = AppState.instance.token;
    if (token == null) return;

    try {
      final list = await ApiClient.request('/addresses', token: token) as List;
      final all = list.whereType<Map<String, dynamic>>().map(Address.fromJson).toList();
      final address = all.where((a) => a.isDefault).firstOrNull ?? all.firstOrNull;
      if (address == null || !mounted) return;
      setState(() => _address = address);

      final p = widget.product;
      final data = await ApiClient.request(
        '/delivery/quote',
        method: 'POST',
        body: {
          'pincode': address.pincode,
          'cod': false,
          'order_value': p.price,
          'items': [
            {'product_id': p.id, 'quantity': 1}
          ],
        },
      ) as Map<String, dynamic>;

      final options = ((data['options'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DeliveryOption.fromJson)
          .toList();
      if (options.isEmpty || !mounted) return;
      // The fastest one is the date the shopper cares about.
      setState(() => _option = options.reduce((a, b) => a.etaMinutes <= b.etaMinutes ? a : b));
    } catch (_) {
      // Supplementary: the general line below still shows.
    }
  }

  String get _general => switch (widget.product.deliveryProfile) {
        'instant' => widget.product.prepMinutes > 0
            ? 'Quick local delivery · ready in about ${widget.product.prepMinutes} mins'
            : 'Quick local delivery from the store',
        'heavy' => 'Delivered by truck in a booked slot',
        'parcel' => 'Courier delivery · free above ₹1,999 · track every step',
        _ => 'Free delivery above ₹1,999',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final p = widget.product;
    final address = _address;
    final option = _option;

    final rows = <Widget>[
      if (address != null)
        _Row(
          icon: Icons.location_on_outlined,
          child: Text(
            [address.line1, address.city, address.pincode].where((s) => s.isNotEmpty).join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.semibold, color: c.ink),
          ),
        ),
      _Row(
        icon: p.deliveryProfile == 'instant' ? Icons.bolt : Icons.local_shipping_outlined,
        child: option != null ? _when(option, c) : Text(_general, style: _body(c)),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delivery details',
            style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
        const SizedBox(height: DsSpace.s3),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.line),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  TextStyle _body(DsColors c) =>
      TextStyle(fontSize: DsText.base, fontWeight: DsWeight.semibold, color: c.ink);

  /// "Delivery by **Fri, 16 Oct**" / "Delivery in **25 mins**".
  Widget _when(DeliveryOption option, DsColors c) {
    final phrase = etaPhrase(option);
    final split = phrase.indexOf(RegExp(r' (by|in) '));
    if (split < 0) return Text(phrase, style: _body(c));

    final lead = phrase.substring(0, phrase.indexOf(' ', split + 1) + 1);
    return Text.rich(TextSpan(children: [
      TextSpan(text: lead, style: _body(c).copyWith(color: c.inkMuted)),
      TextSpan(text: phrase.substring(lead.length), style: _body(c).copyWith(fontWeight: DsWeight.bold)),
    ]));
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Widget child;

  const _Row({required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.inkMuted),
          const SizedBox(width: DsSpace.s3),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A row of small promises under the price: returns, cash on delivery, how fast.
class ProductAssurances extends StatelessWidget {
  final Product product;

  const ProductAssurances({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final items = <(IconData, String)>[
      (Icons.assignment_return_outlined, '7-day return'),
      (product.codAvailable ? Icons.payments_outlined : Icons.credit_card_outlined,
          product.codAvailable ? 'Cash on delivery' : 'Prepaid only'),
      if (product.deliveryProfile == 'instant') (Icons.bolt, 'Quick delivery'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (icon, label) in items)
            Container(
              margin: const EdgeInsets.only(right: DsSpace.s2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: c.accent),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontSize: DsText.sm, fontWeight: DsWeight.semibold, color: c.ink)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
