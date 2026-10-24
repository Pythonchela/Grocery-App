import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_api.dart';
import '../seller_format.dart';
import '../seller_models.dart';
import '../widgets/seller_widgets.dart';

/// The last step: check everything, then hand it to a reviewer.
///
/// Submitting locks the application, so this shows what is still missing (with a
/// way to jump straight to it) and only enables Submit when the server agrees
/// nothing is.
class ReviewStep extends StatefulWidget {
  final SellerApi api;
  final Onboarding onboarding;
  final ValueChanged<Onboarding> onChanged;

  /// Jump to a step by index (0 business, 1 address, 2 bank, 3 documents).
  final ValueChanged<int> onJumpTo;

  const ReviewStep({
    super.key,
    required this.api,
    required this.onboarding,
    required this.onChanged,
    required this.onJumpTo,
  });

  @override
  State<ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends State<ReviewStep> {
  bool _busy = false;
  String? _error;

  Onboarding get _ob => widget.onboarding;

  static const _stepOfField = {
    'business_type': 0, 'legal_name': 0, 'pan': 0,
    'registered_line1': 1, 'registered_city': 1, 'registered_state': 1, 'registered_pincode': 1,
    'bank_account_holder': 2, 'bank_account_number': 2, 'bank_ifsc': 2,
  };

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for review?'),
        content: const Text(
          'You will not be able to change your details while we review them. '
          'We usually respond within two business days.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final ob = await widget.api.submit();
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onChanged(ob);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final k = _ob.kyc;
    final cl = _ob.checklist;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review and submit', style: TextStyle(fontSize: DsText.xl, fontWeight: DsWeight.black, color: c.ink)),
        const SizedBox(height: DsSpace.s4),

        if (!cl.canSubmit) ...[
          const BxAlert('Finish these to submit your application.', title: 'Almost there', tone: BxTone.warning),
          const SizedBox(height: DsSpace.s3),
          for (final f in cl.missingFields)
            _MissingRow(label: SellerFormat.field(f), onFix: () => widget.onJumpTo(_stepOfField[f] ?? 0)),
          for (final d in cl.missingDocuments)
            _MissingRow(label: '${SellerFormat.documentKind(d)} (document)', onFix: () => widget.onJumpTo(3)),
          const SizedBox(height: DsSpace.s3),
        ],

        BxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle('Business', onEdit: () => widget.onJumpTo(0)),
              SellerKeyValue('Type', SellerFormat.businessType(k.businessType)),
              SellerKeyValue('Legal name', k.legalName),
              SellerKeyValue('PAN', k.panMasked ?? ''),
              SellerKeyValue('GSTIN', k.gstinMasked ?? 'Not provided'),
            ],
          ),
        ),
        const SizedBox(height: DsSpace.s3),
        BxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle('Address', onEdit: () => widget.onJumpTo(1)),
              SellerKeyValue('Address', [k.line1, k.line2].where((e) => e.isNotEmpty).join(', ')),
              SellerKeyValue('City', k.city),
              SellerKeyValue('State', k.state),
              SellerKeyValue('PIN code', k.pincode),
            ],
          ),
        ),
        const SizedBox(height: DsSpace.s3),
        BxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle('Bank account', onEdit: () => widget.onJumpTo(2)),
              SellerKeyValue('Account holder', k.bankHolder),
              SellerKeyValue('Account number', k.bankAccountMasked ?? ''),
              SellerKeyValue('IFSC', k.ifsc),
              SellerKeyValue('Bank', k.bankName),
            ],
          ),
        ),
        const SizedBox(height: DsSpace.s3),
        BxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle('Documents', onEdit: () => widget.onJumpTo(3)),
              if (_ob.documents.isEmpty)
                Text('None uploaded yet.', style: TextStyle(fontSize: DsText.sm, color: c.inkMuted))
              else
                for (final d in _ob.documents) SellerKeyValue(SellerFormat.documentKind(d.kind), d.originalName),
            ],
          ),
        ),

        const SizedBox(height: DsSpace.s5),
        if (_error != null) ...[
          BxAlert(_error!, title: 'Could not submit', tone: BxTone.danger),
          const SizedBox(height: DsSpace.s3),
        ],
        BxButton(
          label: 'Submit for review',
          fullWidth: true,
          size: BxButtonSize.lg,
          loading: _busy,
          // The server is the authority on completeness; the button follows it.
          onPressed: (_busy || !cl.canSubmit) ? null : _submit,
        ),
        const SizedBox(height: DsSpace.s6),
      ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String title;
  final VoidCallback onEdit;

  const _CardTitle(this.title, {required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(fontSize: DsText.md, fontWeight: DsWeight.black, color: c.ink)),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit')),
        ],
      ),
    );
  }
}

class _MissingRow extends StatelessWidget {
  final String label;
  final VoidCallback onFix;

  const _MissingRow({required this.label, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s1),
      child: Row(
        children: [
          Icon(Icons.radio_button_unchecked, size: 16, color: c.warning),
          const SizedBox(width: DsSpace.s2),
          Expanded(child: Text(label, style: TextStyle(fontSize: DsText.base, color: c.ink))),
          TextButton(onPressed: onFix, child: const Text('Fix')),
        ],
      ),
    );
  }
}
