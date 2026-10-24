import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_api.dart';
import '../seller_models.dart';

/// Why a shop turns an order down: the wire value and what the seller reads.
const deskDeclineReasons = [
  ('OUT_OF_STOCK', 'Out of stock'),
  ('SHOP_CLOSED', 'Shop is closed'),
  ('CANNOT_PREPARE', 'Cannot prepare it in time'),
  ('DAMAGED', 'Item is damaged'),
  ('OTHER', 'Another reason'),
];

const _prepChoices = [10, 15, 20, 30, 45, 60, 120];

/// mm:ss until [until], on the server's clock ([offset] = server minus device).
class DeskCountdown extends StatefulWidget {
  final DateTime until;
  final Duration offset;

  const DeskCountdown({super.key, required this.until, this.offset = Duration.zero});

  @override
  State<DeskCountdown> createState() => _DeskCountdownState();
}

class _DeskCountdownState extends State<DeskCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final left = widget.until.difference(DateTime.now().add(widget.offset));
    final seconds = left.isNegative ? 0 : left.inSeconds;
    final text = '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

    return Text(
      text,
      key: const Key('desk-countdown'),
      style: TextStyle(
        fontSize: DsText.lg,
        fontWeight: DsWeight.black,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: seconds < 120 ? c.danger : c.ink,
      ),
    );
  }
}

/// Pick how long the order will take, then accept it. Resolves to true when accepted.
Future<bool?> showAcceptSheet(BuildContext context, SellerApi api, SellerOrderItem item, {int? defaultPrep}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AcceptSheet(api: api, item: item, defaultPrep: defaultPrep),
    );

/// Ask why, then turn the order down. Resolves to true when it was.
Future<bool?> showDeclineSheet(BuildContext context, SellerApi api, SellerOrderItem item, {required bool cancelling}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DeclineSheet(api: api, item: item, cancelling: cancelling),
    );

class _AcceptSheet extends StatefulWidget {
  final SellerApi api;
  final SellerOrderItem item;
  final int? defaultPrep;

  const _AcceptSheet({required this.api, required this.item, this.defaultPrep});

  @override
  State<_AcceptSheet> createState() => _AcceptSheetState();
}

class _AcceptSheetState extends State<_AcceptSheet> {
  late int _prep = widget.defaultPrep ?? 20;
  bool _busy = false;
  String? _error;

  List<int> get _choices => {..._prepChoices, _prep}.toList()..sort();

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.acceptItem(widget.item.id, prepMinutes: _prep);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldError('fulfilment') ?? e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Padding(
      padding: EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s4 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Accept order', style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
          const SizedBox(height: DsSpace.s1),
          Text('${widget.item.title} × ${widget.item.quantity}', style: TextStyle(color: c.inkMuted)),
          const SizedBox(height: DsSpace.s4),
          Text('Ready in', style: TextStyle(fontSize: DsText.sm, fontWeight: DsWeight.bold, color: c.ink)),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s2,
            children: [
              for (final m in _choices)
                ChoiceChip(
                  label: Text('$m min'),
                  selected: _prep == m,
                  onSelected: _busy ? null : (_) => setState(() => _prep = m),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: DsSpace.s3),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: DsText.sm)),
          ],
          const SizedBox(height: DsSpace.s4),
          BxButton(label: 'Accept order', fullWidth: true, loading: _busy, onPressed: _busy ? null : _accept),
        ],
      ),
    );
  }
}

class _DeclineSheet extends StatefulWidget {
  final SellerApi api;
  final SellerOrderItem item;
  final bool cancelling;

  const _DeclineSheet({required this.api, required this.item, required this.cancelling});

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  String _reason = deskDeclineReasons.first.$1;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.rejectItem(widget.item.id, _reason, note: _note.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldError('fulfilment') ?? e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s4 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.cancelling ? 'Cancel this order' : 'Decline order',
              style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
          const SizedBox(height: DsSpace.s1),
          Text('${widget.item.title} × ${widget.item.quantity}', style: TextStyle(color: c.inkMuted)),
          const SizedBox(height: DsSpace.s3),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) {
              if (!_busy) setState(() => _reason = v ?? _reason);
            },
            child: Column(children: [
              for (final (value, label) in deskDeclineReasons)
                RadioListTile<String>(contentPadding: EdgeInsets.zero, dense: true, value: value, title: Text(label)),
            ]),
          ),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Note for the customer (optional)'),
          ),
          Text(
            'The customer is told and refunded automatically.'
            '${_reason == 'OUT_OF_STOCK' ? ' This item will show as sold out until you restock it.' : ''}',
            style: TextStyle(fontSize: DsText.xs, color: c.inkMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: DsSpace.s3),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: DsText.sm)),
          ],
          const SizedBox(height: DsSpace.s4),
          BxButton(
            label: widget.cancelling ? 'Cancel order' : 'Decline order',
            variant: BxButtonVariant.danger,
            fullWidth: true,
            loading: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}
