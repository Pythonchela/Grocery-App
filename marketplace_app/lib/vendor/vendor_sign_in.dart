import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../design/brand.g.dart';
import '../design/brand_mark.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import 'vendor_session.dart';

/// Sign in to the seller app, or create the account a shop will be attached to.
///
/// A new account is an ordinary account; what makes it a seller is the
/// application the seller area asks for next, and the marketplace's approval.
class VendorSignInScreen extends StatefulWidget {
  const VendorSignInScreen({super.key});

  @override
  State<VendorSignInScreen> createState() => _VendorSignInScreenState();
}

class _VendorSignInScreenState extends State<VendorSignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _creating = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _validate() {
    final errors = <String, String>{
      if (_creating && _name.text.trim().isEmpty) 'name': 'Enter your name.',
      if (!_emailShape.hasMatch(_email.text.trim())) 'email': 'Enter a valid email address.',
      if (_password.text.isEmpty) 'password': 'Enter your password.'
      else if (_creating && _password.text.length < 8) 'password': 'Use at least 8 characters.',
    };
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
      _error = null;
    });
    return errors.isEmpty;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    setState(() => _busy = true);
    try {
      final session = VendorSession.instance;
      if (_creating) {
        await session.register(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          phone: _phone.text.trim(),
        );
      } else {
        await session.signIn(_email.text.trim(), _password.text);
      }
      // The gate takes over now that there is a session.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.errors == null ? e.message : null;
        for (final field in ['name', 'email', 'phone', 'password']) {
          final message = e.fieldError(field);
          if (message != null) _fieldErrors[field] = message;
        }
        if (_error == null && _fieldErrors.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  void _switchMode() => setState(() {
        _creating = !_creating;
        _error = null;
        _fieldErrors.clear();
      });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DsSpace.s5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: BrandMark(logoUrl: VendorSession.instance.logoUrl, size: 56)),
                const SizedBox(height: DsSpace.s4),
                Text(
                  '${DsBrand.name} Seller',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: DsFont.display, fontSize: DsText.xl, fontWeight: DsWeight.black, color: c.ink),
                ),
                const SizedBox(height: DsSpace.s1),
                Text(
                  _creating ? 'Create an account to start selling.' : 'Sign in to run your shop: orders, products and payouts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.inkMuted),
                ),
                const SizedBox(height: DsSpace.s5),
                if (_error != null) ...[
                  BxAlert(_error!, tone: BxTone.danger),
                  const SizedBox(height: DsSpace.s3),
                ],
                if (_creating) ...[
                  BxField(key: const Key('vendor-name'), label: 'Your name', controller: _name, error: _fieldErrors['name'], enabled: !_busy),
                  const SizedBox(height: DsSpace.s3),
                ],
                BxField(
                  key: const Key('vendor-email'),
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  error: _fieldErrors['email'],
                  enabled: !_busy,
                ),
                const SizedBox(height: DsSpace.s3),
                if (_creating) ...[
                  BxField(
                    key: const Key('vendor-phone'),
                    label: 'Phone (optional)',
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    error: _fieldErrors['phone'],
                    enabled: !_busy,
                  ),
                  const SizedBox(height: DsSpace.s3),
                ],
                BxField(
                  key: const Key('vendor-password'),
                  label: 'Password',
                  controller: _password,
                  obscureText: _obscure,
                  error: _fieldErrors['password'],
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  suffix: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: DsSpace.s5),
                BxButton(
                  key: const Key('vendor-submit'),
                  label: _creating ? 'Create account' : 'Sign in',
                  fullWidth: true,
                  loading: _busy,
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: DsSpace.s3),
                TextButton(
                  key: const Key('vendor-switch-mode'),
                  onPressed: _busy ? null : _switchMode,
                  child: Text(_creating ? 'I already have an account' : 'New here? Create a seller account'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
