import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_api.dart';
import '../seller_models.dart';
import '../widgets/seller_widgets.dart';

/// Hands a parcel to a courier.
///
/// By default the seller types nothing: one tap and the server books the
/// courier and supplies the tracking number the customer follows. If booking is
/// switched off, or the courier refuses, the form below opens (with the reason)
/// so the seller can book it themselves and type both in; the tracking number is
/// never optional, because a parcel handed over without one is a support ticket
/// waiting to happen. Reopened on an already-shipped line it becomes a correction.
class ShipSheet extends StatefulWidget {
  final SellerApi api;
  final SellerOrderItem item;

  const ShipSheet({super.key, required this.api, required this.item});

  /// Opens the sheet; resolves to the updated line, or null if dismissed.
  static Future<SellerOrderItem?> show(
          BuildContext context, SellerApi api, SellerOrderItem item) =>
      showModalBottomSheet<SellerOrderItem>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ShipSheet(api: api, item: item),
      );

  @override
  State<ShipSheet> createState() => _ShipSheetState();
}

class _ShipSheetState extends State<ShipSheet> {
  /// The common Indian couriers, one tap each. Anything else can be typed.
  static const _couriers = [
    'Delhivery',
    'Blue Dart',
    'DTDC',
    'India Post',
    'Ecom Express',
    'XpressBees',
    'Shadowfax'
  ];

  late final _courier = TextEditingController(text: widget.item.courier ?? '');
  late final _tracking =
      TextEditingController(text: widget.item.trackingNo ?? '');
  bool _busy = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  bool get _isCorrection => widget.item.fulfilmentStatus == 'SHIPPED';

  /// Whether the typed-in form is showing. A correction always is; a first
  /// ship starts on the one-tap booking.
  late bool _manual = _isCorrection;

  @override
  void dispose() {
    _courier.dispose();
    _tracking.dispose();
    super.dispose();
  }

  /// The seller types nothing; the server books the courier. If it can't (booking
  /// is switched off, or the courier refused) the form opens with the reason.
  Future<void> _book() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.api.shipItem(widget.item.id);
      if (mounted) Navigator.pop(context, updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _manual = true;
        for (final f in ['courier', 'tracking_no']) {
          final msg = e.fieldError(f);
          if (msg != null) _fieldErrors[f] = msg;
        }
        _error =
            e.fieldError('fulfilment') ?? (e.errors == null ? e.message : null);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Try again.';
      });
    }
  }

  Future<void> _submit() async {
    final courier = _courier.text.trim();
    final tracking = _tracking.text.trim();

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll({
          if (courier.isEmpty) 'courier': 'Choose or enter the courier.',
          if (courier.length > 80) 'courier': 'That name is too long.',
          if (tracking.isEmpty) 'tracking_no': 'Enter the tracking number.',
          if (tracking.length > 80)
            'tracking_no': 'That tracking number is too long.',
        });
      _error = null;
    });
    if (_fieldErrors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      final updated = await widget.api
          .shipItem(widget.item.id, courier: courier, trackingNo: tracking);
      if (mounted) Navigator.pop(context, updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final f in ['courier', 'tracking_no']) {
          final msg = e.fieldError(f);
          if (msg != null) _fieldErrors[f] = msg;
        }
        // e.g. "This order has already left for delivery." — shown as a banner.
        _error =
            e.fieldError('fulfilment') ?? (e.errors == null ? e.message : null);
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
    final c = context.ds;

    return Padding(
      // Keeps the form above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DsSpace.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SellerSectionTitle(
              _isCorrection
                  ? 'Correct tracking details'
                  : (_manual ? 'Mark as shipped' : 'Ready for pickup'),
              subtitle: '${widget.item.title} · ${widget.item.orderNumber}',
            ),
            if (_error != null) ...[
              BxAlert(_error!, tone: BxTone.danger),
              const SizedBox(height: DsSpace.s3),
            ],
            if (!_manual) ...[
              Text(
                'We book the courier for you and give the customer a tracking number. '
                'Have the parcel packed and ready for the courier to collect.',
                style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
              ),
              const SizedBox(height: DsSpace.s4),
              BxButton(
                label: 'Book courier',
                fullWidth: true,
                loading: _busy,
                onPressed: _busy ? null : _book,
              ),
              const SizedBox(height: DsSpace.s2),
              Center(
                child: TextButton(
                  onPressed:
                      _busy ? null : () => setState(() => _manual = true),
                  child: const Text('Enter courier and tracking myself'),
                ),
              ),
            ] else ...[
              Text('Courier',
                  style: TextStyle(
                      fontSize: DsText.xs,
                      fontWeight: DsWeight.bold,
                      color: c.inkMuted)),
              const SizedBox(height: DsSpace.s2),
              Wrap(
                spacing: DsSpace.s2,
                runSpacing: DsSpace.s2,
                children: [
                  for (final name in _couriers)
                    ChoiceChip(
                      label: Text(name),
                      selected: _courier.text.trim() == name,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _courier.text = name),
                    ),
                ],
              ),
              const SizedBox(height: DsSpace.s3),
              BxField(
                label: 'Courier name',
                hint: 'Or type another courier',
                controller: _courier,
                error: _fieldErrors['courier'],
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: DsSpace.s3),
              BxField(
                label: 'Tracking number (AWB)',
                controller: _tracking,
                error: _fieldErrors['tracking_no'],
                enabled: !_busy,
              ),
              const SizedBox(height: DsSpace.s2),
              Text(
                'The customer is told once every seller on the order has shipped.',
                style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
              ),
              const SizedBox(height: DsSpace.s5),
              BxButton(
                label: _isCorrection ? 'Save changes' : 'Mark as shipped',
                fullWidth: true,
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: DsSpace.s2),
            ],
          ],
        ),
      ),
    );
  }
}
