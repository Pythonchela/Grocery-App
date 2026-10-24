import 'package:flutter/material.dart';

import '../data/google_auth.dart';
import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'google_sign_in_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _referral = TextEditingController();

  bool _obscure = true;
  bool _saving = false;
  bool _acceptedTerms = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm, _referral]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    _fieldErrors.clear();

    if (_name.text.trim().isEmpty) {
      _fieldErrors['name'] = 'Tell us what to call you.';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      _fieldErrors['email'] = 'Enter a valid email address.';
    }
    if (_phone.text.trim().isNotEmpty &&
        !RegExp(r'^[0-9]{10}$').hasMatch(_phone.text.trim())) {
      _fieldErrors['phone'] = 'Enter a 10-digit mobile number, or leave it blank.';
    }
    // Matches the server's `min:8`. Validating client-side too means the error
    // lands next to the field instead of arriving as a generic API failure.
    if (_password.text.length < 8) {
      _fieldErrors['password'] = 'Use at least 8 characters.';
    }
    if (_confirm.text != _password.text) {
      _fieldErrors['confirm'] = 'Passwords do not match.';
    }

    setState(() {});
    return _fieldErrors.isEmpty;
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    if (!_acceptedTerms) {
      setState(() => _error = 'Please accept the terms to continue.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await AppState.instance.register(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        phone: _phone.text.trim(),
        referralCode: _referral.text.trim(),
      );

      // The account screen switches itself on the signed-in state, so popping
      // back to it is enough — no explicit navigation to a "home" needed.
      if (mounted) Navigator.of(context).pop();
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

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: ListView(
        padding: const EdgeInsets.all(DsSpace.s4),
        children: [
          Text(
            'Join ${DsBrand.name}',
            style: TextStyle(
              fontFamily: DsFont.display,
              fontSize: DsText.x2xl,
              fontWeight: DsWeight.black,
              color: c.ink,
            ),
          ),
          const SizedBox(height: DsSpace.s1),
          Text(
            'One account for orders, wallet, wishlist and returns.',
            style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
          ),
          const SizedBox(height: DsSpace.s5),

          if (GoogleAuth.isConfigured) ...[
            GoogleSignInButton(
              referralCode: _referral.text.trim(),
              onSignedIn: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: DsSpace.s5),
            Row(
              children: [
                Expanded(child: Divider(color: c.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
                  child: Text(
                    'or sign up with email',
                    style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
                  ),
                ),
                Expanded(child: Divider(color: c.line)),
              ],
            ),
            const SizedBox(height: DsSpace.s5),
          ],

          if (_error != null) ...[
            BxAlert(_error!, tone: BxTone.danger),
            const SizedBox(height: DsSpace.s4),
          ],

          BxField(
            label: 'Full name',
            hint: 'Priya Sharma',
            controller: _name,
            error: _fieldErrors['name'],
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Email address',
            hint: 'you@example.com',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            error: _fieldErrors['email'],
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Mobile number',
            hint: '10 digits (optional)',
            helper: 'Lets you sign in with an OTP later.',
            controller: _phone,
            keyboardType: TextInputType.phone,
            error: _fieldErrors['phone'],
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Password',
            hint: 'At least 8 characters',
            controller: _password,
            obscureText: _obscure,
            error: _fieldErrors['password'],
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18,
                color: c.inkSubtle,
              ),
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Confirm password',
            controller: _confirm,
            obscureText: _obscure,
            error: _fieldErrors['confirm'],
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Referral code',
            hint: 'Optional',
            helper: 'Both of you earn wallet credit on your first order.',
            controller: _referral,
          ),

          const SizedBox(height: DsSpace.s5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _acceptedTerms,
                activeColor: c.accent,
                onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'I agree to the Terms of Service and Privacy Policy.',
                    style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: DsSpace.s4),
          BxButton(
            label: 'Create account',
            size: BxButtonSize.lg,
            fullWidth: true,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
          const SizedBox(height: DsSpace.s3),
          Center(
            child: BxButton(
              label: 'Already have an account? Sign in',
              variant: BxButtonVariant.link,
              size: BxButtonSize.sm,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
