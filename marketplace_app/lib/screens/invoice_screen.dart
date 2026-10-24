import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// Order receipt for one order, rendered from `/orders/{id}/invoice`.
class InvoiceScreen extends StatefulWidget {
  final String orderId;
  const InvoiceScreen({super.key, required this.orderId});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;

class _InvoiceScreenState extends State<InvoiceScreen> {
  Map<String, dynamic>? _invoice;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.request('/orders/${widget.orderId}/invoice',
          token: AppState.instance.token) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _invoice = data;
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

  List<Map<String, dynamic>> get _items =>
      ((_invoice!['order'] as Map)['items'] as List? ?? [])
          .cast<Map<String, dynamic>>();

  String _itemTitle(Map<String, dynamic> item) {
    final product = item['product'];
    return product is Map ? '${product['title']}' : 'Product';
  }

  /// Plain-text copy for the share sheet, so the receipt can go to email or
  /// WhatsApp without a PDF dependency.
  String _asText() {
    final inv = _invoice!;
    final totals = inv['totals'] as Map;
    final seller = inv['seller'] as Map;
    final b = StringBuffer()
      ..writeln('ORDER RECEIPT ${inv['invoice_number']}')
      ..writeln('Date: ${inv['issued_at']}')
      ..writeln('${seller['name']}');
    if (seller['address']?.toString().isNotEmpty == true) b.writeln(seller['address']);
    if (seller['gstin']?.toString().isNotEmpty == true) b.writeln('GSTIN ${seller['gstin']}');
    b.writeln();
    for (final item in _items) {
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      b.writeln(
          '${_itemTitle(item)} x$qty  ${formatMoney(_num(item['price']) * qty)}');
    }
    b.writeln();
    b.writeln('Subtotal: ${formatMoney(_num(totals['subtotal']))}');
    if (_num(totals['discount']) > 0) b.writeln('Discount: −${formatMoney(_num(totals['discount']))}');
    b.writeln('Shipping: ${formatMoney(_num(totals['shipping']))}');
    if (_num(totals['wallet_applied']) > 0) b.writeln('Wallet applied: −${formatMoney(_num(totals['wallet_applied']))}');
    b.writeln('Total: ${formatMoney(_num(totals['grand_total']))}');
    b.writeln('For a GST tax invoice, contact support.');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order receipt'),
        actions: [
          if (_invoice != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share receipt',
              onPressed: () => SharePlus.instance.share(ShareParams(
                  text: _asText(),
                  subject: 'Order receipt ${_invoice!['invoice_number']}')),
            ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: BxSkeleton(height: 300, radius: DsRadius.cardAll),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load the receipt',
                  description: _error,
                  action: BxButton(label: 'Try again', onPressed: _load),
                )
              : ListView(
                  padding: const EdgeInsets.all(DsSpace.s4),
                  children: [
                    BxCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_invoice!['invoice_number']}',
                              style: TextStyle(
                                  fontFamily: DsFont.mono,
                                  fontSize: DsText.md,
                                  fontWeight: DsWeight.black,
                                  color: c.ink)),
                          Text('Issued ${_invoice!['issued_at']}',
                              style: TextStyle(
                                  fontSize: DsText.xs, color: c.inkSubtle)),
                          const SizedBox(height: DsSpace.s3),
                          Text('${(_invoice!['seller'] as Map)['name']}',
                              style: TextStyle(
                                  fontWeight: DsWeight.bold, color: c.ink)),
                          if ('${(_invoice!['seller'] as Map)['address'] ?? ''}'.isNotEmpty)
                            Text('${(_invoice!['seller'] as Map)['address']}',
                                style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
                          if ('${(_invoice!['seller'] as Map)['gstin'] ?? ''}'.isNotEmpty)
                            Text('GSTIN: ${(_invoice!['seller'] as Map)['gstin']}',
                                style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(height: DsSpace.s3),
                    BxCard(
                      child: Column(
                        children: [
                          for (final item in _items)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: DsSpace.s3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                        '${_itemTitle(item)}  ×${item['quantity']}${item['seller'] is Map ? '\nSold by ${item['seller']['display_name']}' : ''}',
                                        style: TextStyle(
                                            fontSize: DsText.base,
                                            color: c.ink)),
                                  ),
                                  Text(
                                      formatMoney(_num(item['price']) *
                                          _num(item['quantity'])),
                                      style: TextStyle(
                                          fontWeight: DsWeight.bold,
                                          color: c.ink)),
                                ],
                              ),
                            ),
                          Divider(color: c.line),
                          ..._totalRows(context),
                        ],
                      ),
                    ),
                    const SizedBox(height: DsSpace.s3),
                    const Text('This receipt records your order and payment. For a GST tax invoice, contact support.'),
                  ],
                ),
    );
  }

  List<Widget> _totalRows(BuildContext context) {
    final c = context.ds;
    final t = _invoice!['totals'] as Map;
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: bold ? DsText.md : DsText.base,
                          fontWeight: bold ? DsWeight.black : DsWeight.medium,
                          color: bold ? c.ink : c.inkMuted))),
              Text(value,
                  style: TextStyle(
                      fontSize: bold ? DsText.md : DsText.base,
                      fontWeight: bold ? DsWeight.black : DsWeight.bold,
                      color: c.ink)),
            ],
          ),
        );
    final discount = _num(t['discount']);
    final wallet = _num(t['wallet_applied']);
    final shipping = _num(t['shipping']);
    return [
      if (t['taxable_value'] != null) row('Taxable value', formatMoney(_num(t['taxable_value']))),
      if (t['gst'] != null) row('GST (${t['gst_rate']})', formatMoney(_num(t['gst']))),
      row('Subtotal', formatMoney(_num(t['subtotal']))),
      if (discount > 0) row('Discount', '− ${formatMoney(discount)}'),
      row('Shipping', shipping == 0 ? 'FREE' : formatMoney(shipping)),
      if (wallet > 0) row('Wallet applied', '− ${formatMoney(wallet)}'),
      const SizedBox(height: DsSpace.s1),
      row('Grand total', formatMoney(_num(t['grand_total'])), bold: true),
    ];
  }
}
