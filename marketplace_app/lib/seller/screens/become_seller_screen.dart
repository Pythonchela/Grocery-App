import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_api.dart';
import '../seller_host.dart';
import '../seller_models.dart';
import '../validators.dart';

/// Step zero: someone who has not applied yet starts an application.
///
/// Applying only ever creates a PENDING account — nothing here can switch a shop
/// on, which is what makes it safe to offer to anyone signed in.
class BecomeSellerScreen extends StatefulWidget {
  final SellerApi api;
  final SellerHost host;
  final ValueChanged<Onboarding> onApplied;

  const BecomeSellerScreen({super.key, required this.api, required this.host, required this.onApplied});

  @override
  State<BecomeSellerScreen> createState() => _BecomeSellerScreenState();
}

class _BecomeSellerScreenState extends State<BecomeSellerScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

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

  bool _validate() {
    _fieldErrors
      ..clear()
      ..addAll({
        if (SellerValidators.required(_name.text, 'your shop name') case final e?) 'display_name': e,
        if (SellerValidators.optionalEmail(_email.text) case final e?) 'support_email': e,
        if (SellerValidators.optionalPhone(_phone.text) case final e?) 'support_phone': e,
      });
    setState(() {});
    return _fieldErrors.isEmpty;
  }

  Future<void> _apply() async {
    if (!_validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final onboarding = await widget.api.apply(
        displayName: _name.text.trim(),
        supportEmail: _email.text.trim(),
        supportPhone: _phone.text.trim(),
      );
      if (!mounted) return;
      widget.onApplied(onboarding);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final f in ['display_name', 'support_email', 'support_phone']) {
          final msg = e.fieldError(f);
          if (msg != null) _fieldErrors[f] = msg;
        }
        // A field-level problem is shown under its field; anything else here.
        _error = e.errors == null ? e.message : null;
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
    final name = widget.host.marketplaceName;

    return Scaffold(
      appBar: AppBar(title: Text('Sell on $name')),
      body: ListView(
        padding: const EdgeInsets.all(DsSpace.s4),
        children: [
          Text(
            'Reach shoppers across India',
            style: TextStyle(fontSize: DsText.xl, fontWeight: DsWeight.black, color: c.ink),
          ),
          const SizedBox(height: DsSpace.s2),
          Text(
            'Open a shop in a few minutes. You will need your PAN, bank account details '
            'and a couple of documents — you can save and come back at any point.',
            style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
          ),
          const SizedBox(height: DsSpace.s4),
          const _Bullet(Icons.verified_user_outlined, 'We verify every seller before a shop goes live.'),
          const _Bullet(Icons.account_balance_outlined, 'Earnings are paid out to your bank account.'),
          const _Bullet(Icons.percent, 'A platform commission is taken on each sale; you will see the rate before you sell.'),
          const SizedBox(height: DsSpace.s5),
          if (_error != null) ...[
            BxAlert(_error!, title: 'Could not start your application', tone: BxTone.danger),
            const SizedBox(height: DsSpace.s4),
          ],
          BxField(
            label: 'Shop name',
            hint: 'The name shoppers will see',
            controller: _name,
            error: _fieldErrors['display_name'],
            enabled: !_busy,
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Support email (optional)',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            error: _fieldErrors['support_email'],
            enabled: !_busy,
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Support phone (optional)',
            controller: _phone,
            keyboardType: TextInputType.phone,
            error: _fieldErrors['support_phone'],
            enabled: !_busy,
          ),
          const SizedBox(height: DsSpace.s6),
          BxButton(
            label: 'Start application',
            onPressed: _busy ? null : _apply,
            loading: _busy,
            fullWidth: true,
            size: BxButtonSize.lg,
          ),
          const SizedBox(height: DsSpace.s3),
          Text(
            'Applying does not make your shop live. It opens the next step, where you add your details for review.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Bullet(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(width: DsSpace.s3),
          Expanded(child: Text(text, style: TextStyle(fontSize: DsText.base, color: c.ink))),
        ],
      ),
    );
  }
}
