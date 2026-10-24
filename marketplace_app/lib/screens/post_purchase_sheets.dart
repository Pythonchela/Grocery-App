import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// What a customer does *after* delivery: review the thing, or send it back.
///
/// Both are sheets rather than screens because they are single-purpose forms
/// launched from one place — an order. Making them routes would mean handling
/// deep-link entry into a form that only makes sense with an order behind it.

// ─── Write a review ──────────────────────────────────────────────────────────

Future<bool?> showWriteReviewSheet({
  required BuildContext context,
  required String productId,
  required String productTitle,
  required String orderId,
}) {
  return showBxSheet<bool>(
    context: context,
    title: 'Review this product',
    child: _WriteReviewForm(
      productId: productId,
      productTitle: productTitle,
      orderId: orderId,
    ),
  );
}

class _WriteReviewForm extends StatefulWidget {
  final String productId;
  final String productTitle;
  final String orderId;

  const _WriteReviewForm({
    required this.productId,
    required this.productTitle,
    required this.orderId,
  });

  @override
  State<_WriteReviewForm> createState() => _WriteReviewFormState();
}

class _WriteReviewFormState extends State<_WriteReviewForm> {
  int _rating = 0;
  final _title = TextEditingController();
  final _body = TextEditingController();

  /// The same attributes the web PDP averages and displays. Optional — a
  /// mandatory five-slider form is how you get no reviews at all.
  final Map<String, int> _attributes = {'Quality': 0, 'Value for money': 0, 'Fit / accuracy': 0};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Pick a star rating first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient.request(
        '/products/${widget.productId}/reviews',
        method: 'POST',
        token: AppState.instance.token,
        body: {
          'order_id': widget.orderId,
          'rating': _rating,
          'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
          'body': _body.text.trim().isEmpty ? null : _body.text.trim(),
          'attribute_ratings': Map.fromEntries(
            _attributes.entries.where((e) => e.value > 0),
          ),
        },
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.productTitle,
          style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink),
        ),
        const SizedBox(height: DsSpace.s4),

        if (_error != null) ...[
          BxAlert(_error!, tone: BxTone.danger),
          const SizedBox(height: DsSpace.s4),
        ],

        Text(
          'Your rating',
          style: TextStyle(fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.inkMuted),
        ),
        const SizedBox(height: DsSpace.s2),
        Semantics(
          label: 'Star rating, $_rating out of 5',
          child: Row(
            children: List.generate(5, (i) {
              final value = i + 1;
              return IconButton(
                icon: Icon(
                  value <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 34,
                  color: value <= _rating ? c.rating : c.inkSubtle,
                ),
                tooltip: '$value star${value == 1 ? '' : 's'}',
                onPressed: () => setState(() => _rating = value),
              );
            }),
          ),
        ),

        const SizedBox(height: DsSpace.s4),
        BxField(label: 'Headline', hint: 'Sums it up in a few words', controller: _title),
        const SizedBox(height: DsSpace.s4),
        BxField(
          label: 'Your review',
          hint: 'What worked, what did not?',
          controller: _body,
          maxLines: 4,
        ),

        const SizedBox(height: DsSpace.s5),
        Text(
          'Rate specifics (optional)',
          style: TextStyle(fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.inkMuted),
        ),
        const SizedBox(height: DsSpace.s2),
        ..._attributes.keys.map((key) => Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(key, style: TextStyle(fontSize: DsText.base, color: c.ink)),
                  ),
                  ...List.generate(5, (i) {
                    final value = i + 1;
                    return GestureDetector(
                      onTap: () => setState(() => _attributes[key] = value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          value <= _attributes[key]! ? Icons.circle : Icons.circle_outlined,
                          size: 15,
                          color: value <= _attributes[key]! ? c.accent : c.inkSubtle,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            )),

        const SizedBox(height: DsSpace.s5),
        BxButton(
          label: 'Submit review',
          size: BxButtonSize.lg,
          fullWidth: true,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
        const SizedBox(height: DsSpace.s2),
        Text(
          'Only customers with a delivered order can review, and it is marked a verified purchase.',
          style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle),
        ),
      ],
    );
  }
}

// ─── Request a return ────────────────────────────────────────────────────────

const _returnReasons = [
  'Damaged or defective',
  'Wrong item delivered',
  'Size or fit issue',
  'Not as described',
  'Changed my mind',
];

Future<bool?> showReturnSheet({
  required BuildContext context,
  required String orderItemId,
  required String productTitle,
}) {
  return showBxSheet<bool>(
    context: context,
    title: 'Return or exchange',
    child: _ReturnForm(orderItemId: orderItemId, productTitle: productTitle),
  );
}

class _ReturnForm extends StatefulWidget {
  final String orderItemId;
  final String productTitle;

  const _ReturnForm({required this.orderItemId, required this.productTitle});

  @override
  State<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends State<_ReturnForm> {
  String _kind = 'RETURN';
  String? _reason;
  String _refundMode = 'WALLET';
  final _comments = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comments.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = 'Choose a reason.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient.request(
        '/returns',
        method: 'POST',
        token: AppState.instance.token,
        body: {
          'order_item_id': widget.orderItemId,
          'kind': _kind,
          'reason': _reason,
          'comments': _comments.text.trim().isEmpty ? null : _comments.text.trim(),
          'refund_mode': _kind == 'RETURN' ? _refundMode : null,
        },
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.productTitle,
          style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink),
        ),
        const SizedBox(height: DsSpace.s4),

        if (_error != null) ...[
          BxAlert(_error!, tone: BxTone.danger),
          const SizedBox(height: DsSpace.s4),
        ],

        BxTabs(
          tabs: const [BxTab('RETURN', 'Return'), BxTab('EXCHANGE', 'Exchange')],
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
        ),

        const SizedBox(height: DsSpace.s5),
        Text(
          'Reason',
          style: TextStyle(fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.inkMuted),
        ),
        const SizedBox(height: DsSpace.s2),
        // RadioGroup rather than per-tile groupValue/onChanged: those were
        // deprecated in Flutter 3.32, and the ancestor form keeps the selection
        // in one place instead of on every tile.
        RadioGroup<String>(
          groupValue: _reason,
          onChanged: (v) => setState(() => _reason = v),
          child: Column(
            children: _returnReasons
                .map((reason) => RadioListTile<String>(
                      value: reason,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: c.accent,
                      title: Text(reason, style: TextStyle(fontSize: DsText.base, color: c.ink)),
                    ))
                .toList(),
          ),
        ),

        const SizedBox(height: DsSpace.s3),
        BxField(
          label: 'Anything else?',
          hint: 'Optional details for the pickup agent',
          controller: _comments,
          maxLines: 3,
        ),

        if (_kind == 'RETURN') ...[
          const SizedBox(height: DsSpace.s5),
          Text(
            'Refund to',
            style: TextStyle(fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.inkMuted),
          ),
          const SizedBox(height: DsSpace.s2),
          BxTabs(
            tabs: const [
              BxTab('WALLET', 'Wallet — instant'),
              BxTab('SOURCE', 'Original payment'),
            ],
            value: _refundMode,
            onChanged: (v) => setState(() => _refundMode = v),
          ),
          const SizedBox(height: DsSpace.s2),
          Text(
            _refundMode == 'WALLET'
                ? 'Credited the moment the item is picked up.'
                : 'Takes 5–7 working days to reach your bank once we receive the item.',
            style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle),
          ),
        ],

        const SizedBox(height: DsSpace.s5),
        BxButton(
          label: _kind == 'RETURN' ? 'Request return' : 'Request exchange',
          size: BxButtonSize.lg,
          fullWidth: true,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
        const SizedBox(height: DsSpace.s2),
        Text(
          'Returns are accepted within 7 days of delivery.',
          style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle),
        ),
      ],
    );
  }
}
