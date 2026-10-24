import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../document_picker.dart';
import '../seller_api.dart';
import '../seller_format.dart';
import '../seller_models.dart';
import '../validators.dart';
import 'onboarding_documents.dart';
import 'onboarding_review.dart';

/// The guided application: business → address → bank → documents → review.
///
/// Each step saves as you continue, so leaving halfway loses nothing. The API is
/// the source of truth for what is still missing; this screen only mirrors its
/// rules to catch typos early.
class OnboardingWizard extends StatefulWidget {
  final SellerApi api;
  final DocumentPicker picker;
  final Onboarding onboarding;

  /// Every successful call returns the full new state; pass it up so the gate
  /// (and this screen) rebuild from it.
  final ValueChanged<Onboarding> onChanged;

  const OnboardingWizard({
    super.key,
    required this.api,
    required this.picker,
    required this.onboarding,
    required this.onChanged,
  });

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

const _stepTitles = ['Business', 'Address', 'Bank', 'Documents', 'Review'];

class _OnboardingWizardState extends State<OnboardingWizard> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  late String _businessType;
  late final TextEditingController _legalName;
  final _pan = TextEditingController();
  final _gstin = TextEditingController();
  late final TextEditingController _line1;
  late final TextEditingController _line2;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _pincode;
  late final TextEditingController _holder;
  final _account = TextEditingController();
  late final TextEditingController _ifsc;
  late final TextEditingController _bankName;

  Onboarding get _ob => widget.onboarding;

  @override
  void initState() {
    super.initState();
    final k = _ob.kyc;
    _businessType = k.businessType;
    _legalName = TextEditingController(text: k.legalName);
    _line1 = TextEditingController(text: k.line1);
    _line2 = TextEditingController(text: k.line2);
    _city = TextEditingController(text: k.city);
    _state = TextEditingController(text: k.state);
    _pincode = TextEditingController(text: k.pincode);
    _holder = TextEditingController(text: k.bankHolder);
    _ifsc = TextEditingController(text: k.ifsc);
    _bankName = TextEditingController(text: k.bankName);

    // Resume where the seller left off: the first step with something missing.
    _step = _firstIncompleteStep();
  }

  @override
  void dispose() {
    for (final c in [_legalName, _pan, _gstin, _line1, _line2, _city, _state, _pincode, _holder, _account, _ifsc, _bankName]) {
      c.dispose();
    }
    super.dispose();
  }

  int _firstIncompleteStep() {
    final missing = _ob.checklist.missingFields;
    if (missing.any(_businessFields.contains)) return 0;
    if (missing.any(_addressFields.contains)) return 1;
    if (missing.any(_bankFields.contains)) return 2;
    if (_ob.checklist.missingDocuments.isNotEmpty) return 3;
    return 4;
  }

  static const _businessFields = {'business_type', 'legal_name', 'pan'};
  static const _addressFields = {'registered_line1', 'registered_city', 'registered_state', 'registered_pincode'};
  static const _bankFields = {'bank_account_holder', 'bank_account_number', 'bank_ifsc'};

  // ── Saving ────────────────────────────────────────────────────────────────

  /// Sends only the fields given. Returns whether the server accepted them.
  Future<bool> _save(Map<String, String> fields) async {
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors.clear();
    });

    try {
      final ob = await widget.api.saveKyc(fields);
      if (!mounted) return true;
      setState(() => _busy = false);
      widget.onChanged(ob);
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() {
        _busy = false;
        for (final entry in (e.errors ?? {}).entries) {
          _fieldErrors[entry.key] = entry.value.first;
        }
        _error = e.errors == null ? e.message : null;
      });
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection and try again.';
      });
      return false;
    }
  }

  Future<void> _next() async {
    final fields = switch (_step) {
      0 => _validateBusiness(),
      1 => _validateAddress(),
      2 => _validateBank(),
      _ => <String, String>{},
    };
    if (fields == null) return; // validation failed; errors are on screen

    if (fields.isNotEmpty && !await _save(fields)) return;
    if (!mounted) return;

    setState(() {
      _step = (_step + 1).clamp(0, _stepTitles.length - 1);
      _error = null;
    });
  }

  // Each validator returns the fields to send, or null after putting errors on
  // screen. A masked field left blank means "keep what is saved".

  Map<String, String>? _validateBusiness() {
    final errors = <String, String>{
      if (SellerValidators.required(_legalName.text, 'your legal name') case final e?) 'legal_name': e,
    };

    final panTyped = _pan.text.trim().isNotEmpty;
    if (panTyped) {
      if (SellerValidators.pan(_pan.text) case final e?) errors['pan'] = e;
    } else if (_ob.kyc.panMasked == null) {
      errors['pan'] = 'Enter your PAN.';
    }
    if (SellerValidators.gstin(_gstin.text) case final e?) errors['gstin'] = e;

    return _apply(errors, {
      'business_type': _businessType,
      'legal_name': _legalName.text.trim(),
      if (panTyped) 'pan': SellerValidators.normalise(_pan.text),
      if (_gstin.text.trim().isNotEmpty) 'gstin': SellerValidators.normalise(_gstin.text),
    });
  }

  Map<String, String>? _validateAddress() {
    final errors = <String, String>{
      if (SellerValidators.required(_line1.text, 'address line 1') case final e?) 'registered_line1': e,
      if (SellerValidators.required(_city.text, 'a city') case final e?) 'registered_city': e,
      if (SellerValidators.required(_state.text, 'a state') case final e?) 'registered_state': e,
      if (SellerValidators.pincode(_pincode.text) case final e?) 'registered_pincode': e,
    };

    return _apply(errors, {
      'registered_line1': _line1.text.trim(),
      'registered_line2': _line2.text.trim(),
      'registered_city': _city.text.trim(),
      'registered_state': _state.text.trim(),
      'registered_pincode': _pincode.text.trim(),
    });
  }

  Map<String, String>? _validateBank() {
    final errors = <String, String>{
      if (SellerValidators.required(_holder.text, 'the account holder name') case final e?) 'bank_account_holder': e,
      if (SellerValidators.ifsc(_ifsc.text) case final e?) 'bank_ifsc': e,
    };

    final accountTyped = _account.text.trim().isNotEmpty;
    if (accountTyped) {
      if (SellerValidators.accountNumber(_account.text) case final e?) errors['bank_account_number'] = e;
    } else if (_ob.kyc.bankAccountMasked == null) {
      errors['bank_account_number'] = 'Enter your bank account number.';
    }

    return _apply(errors, {
      'bank_account_holder': _holder.text.trim(),
      'bank_ifsc': SellerValidators.normalise(_ifsc.text),
      if (_bankName.text.trim().isNotEmpty) 'bank_name': _bankName.text.trim(),
      if (accountTyped) 'bank_account_number': _account.text.trim(),
    });
  }

  Map<String, String>? _apply(Map<String, String> errors, Map<String, String> fields) {
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
      _error = null;
    });
    return errors.isEmpty ? fields : null;
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final rejection = _ob.kyc.status == KycStatus.rejected ? _ob.kyc.rejectionReason : null;
    final isLast = _step == _stepTitles.length - 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Your seller application')),
      body: Column(
        children: [
          _Progress(step: _step, onTap: (i) => setState(() => _step = i)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(DsSpace.s4),
              children: [
                if (rejection != null) ...[
                  BxAlert(rejection, title: 'Changes needed', tone: BxTone.warning),
                  const SizedBox(height: DsSpace.s4),
                ],
                if (_error != null) ...[
                  BxAlert(_error!, title: 'Could not save', tone: BxTone.danger),
                  const SizedBox(height: DsSpace.s4),
                ],
                switch (_step) {
                  0 => _businessForm(c),
                  1 => _addressForm(),
                  2 => _bankForm(c),
                  3 => DocumentsStep(api: widget.api, picker: widget.picker, onboarding: _ob, onChanged: widget.onChanged),
                  _ => ReviewStep(
                      api: widget.api,
                      onboarding: _ob,
                      onChanged: widget.onChanged,
                      onJumpTo: (i) => setState(() => _step = i),
                    ),
                },
              ],
            ),
          ),
          if (!isLast)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(DsSpace.s4),
                decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      BxButton(
                        label: 'Back',
                        variant: BxButtonVariant.secondary,
                        onPressed: _busy ? null : () => setState(() => _step -= 1),
                      ),
                      const SizedBox(width: DsSpace.s3),
                    ],
                    Expanded(
                      child: BxButton(
                        label: _step == 3 ? 'Continue to review' : 'Save and continue',
                        onPressed: _busy ? null : _next,
                        loading: _busy,
                        fullWidth: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _businessForm(DsColors c) {
    final k = _ob.kyc;
    final types = _ob.businessTypes.isEmpty ? const ['INDIVIDUAL'] : _ob.businessTypes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading('About your business', 'This is used for verification and tax invoices.'),
        Text('Business type',
            style: TextStyle(fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.inkMuted)),
        const SizedBox(height: DsSpace.s2),
        Wrap(
          spacing: DsSpace.s2,
          runSpacing: DsSpace.s2,
          children: [
            for (final t in types)
              ChoiceChip(
                label: Text(SellerFormat.businessType(t)),
                selected: _businessType == t,
                onSelected: _busy ? null : (_) => setState(() => _businessType = t),
              ),
          ],
        ),
        const SizedBox(height: DsSpace.s4),
        BxField(
          label: 'Legal name',
          helper: 'As it appears on your PAN.',
          controller: _legalName,
          error: _fieldErrors['legal_name'],
          enabled: !_busy,
        ),
        const SizedBox(height: DsSpace.s4),
        BxField(
          label: 'PAN',
          hint: k.panMasked != null ? 'Saved: ${k.panMasked} — leave blank to keep' : 'ABCDE1234F',
          controller: _pan,
          error: _fieldErrors['pan'],
          enabled: !_busy,
        ),
        const SizedBox(height: DsSpace.s4),
        BxField(
          label: 'GSTIN (optional)',
          hint: k.gstinMasked != null ? 'Saved: ${k.gstinMasked} — leave blank to keep' : '29ABCDE1234F1Z5',
          helper: 'If you add one, you will also upload your GST certificate.',
          controller: _gstin,
          error: _fieldErrors['gstin'],
          enabled: !_busy,
        ),
      ],
    );
  }

  Widget _addressForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading('Registered address', 'Where your business is registered.'),
        BxField(label: 'Address line 1', controller: _line1, error: _fieldErrors['registered_line1'], enabled: !_busy),
        const SizedBox(height: DsSpace.s4),
        BxField(label: 'Address line 2 (optional)', controller: _line2, error: _fieldErrors['registered_line2'], enabled: !_busy),
        const SizedBox(height: DsSpace.s4),
        BxField(label: 'City', controller: _city, error: _fieldErrors['registered_city'], enabled: !_busy),
        const SizedBox(height: DsSpace.s4),
        BxField(label: 'State', controller: _state, error: _fieldErrors['registered_state'], enabled: !_busy),
        const SizedBox(height: DsSpace.s4),
        BxField(
          label: 'PIN code',
          controller: _pincode,
          keyboardType: TextInputType.number,
          error: _fieldErrors['registered_pincode'],
          enabled: !_busy,
        ),
      ],
    );
  }

  Widget _bankForm(DsColors c) {
    final k = _ob.kyc;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading('Where should we pay you?', 'Your earnings are paid into this account.'),
        BxField(
          label: 'Account holder name',
          controller: _holder,
          error: _fieldErrors['bank_account_holder'],
          enabled: !_busy,
        ),
        const SizedBox(height: DsSpace.s4),
        BxField(
          label: 'Account number',
          hint: k.bankAccountMasked != null ? 'Saved: ${k.bankAccountMasked} — leave blank to keep' : null,
          controller: _account,
          keyboardType: TextInputType.number,
          error: _fieldErrors['bank_account_number'],
          enabled: !_busy,
        ),
        const SizedBox(height: DsSpace.s4),
        BxField(
          label: 'IFSC code',
          hint: 'HDFC0001234',
          controller: _ifsc,
          error: _fieldErrors['bank_ifsc'],
          enabled: !_busy,
        ),
        const SizedBox(height: DsSpace.s4),
        BxField(label: 'Bank name (optional)', controller: _bankName, error: _fieldErrors['bank_name'], enabled: !_busy),
      ],
    );
  }
}

class _StepHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StepHeading(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: DsText.xl, fontWeight: DsWeight.black, color: c.ink)),
          const SizedBox(height: DsSpace.s1),
          Text(subtitle, style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final int step;
  final ValueChanged<int> onTap;

  const _Progress({required this.step, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s3),
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          for (var i = 0; i < _stepTitles.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == step,
                label: 'Step ${i + 1} of ${_stepTitles.length}: ${_stepTitles[i]}',
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    children: [
                      Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= step ? c.accent : c.line,
                          borderRadius: DsRadius.pillAll,
                        ),
                      ),
                      const SizedBox(height: DsSpace.s1 + 2),
                      Text(
                        _stepTitles[i],
                        style: TextStyle(
                          fontSize: DsText.x2xs,
                          fontWeight: i == step ? DsWeight.black : DsWeight.medium,
                          color: i == step ? c.ink : c.inkSubtle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
