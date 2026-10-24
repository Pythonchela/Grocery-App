import 'package:flutter/material.dart';

import '../data/google_auth.dart';
import '../data/models.dart';
import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import '../support/support_api.dart';
import '../support/support_screens.dart';
import '../widgets/theme_picker.dart';
import 'address_screen.dart';
import 'google_sign_in_button.dart';
import 'notifications_screen.dart';
import 'my_reviews_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'referrals_screen.dart';
import 'returns_screen.dart';
import 'wallet_screen.dart';
import 'register_screen.dart';
import 'wishlist_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) =>
          AppState.instance.isSignedIn ? const _AccountHome() : const _SignIn(),
    );
  }
}

// ─── Signed out ──────────────────────────────────────────────────────────────

class _SignIn extends StatefulWidget {
  const _SignIn();

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  bool _useOtp = false;
  bool _otpSent = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? notice}) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted) setState(() => _notice = notice);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in'),
        actions: const [ThemeModeButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(DsSpace.s4),
        children: [
          Text(
            'Welcome to ${DsBrand.name}',
            style: TextStyle(
              fontFamily: DsFont.display,
              fontSize: DsText.x2xl,
              fontWeight: DsWeight.black,
              color: c.ink,
            ),
          ),
          const SizedBox(height: DsSpace.s1),
          Text(
            'Sign in to see your orders, wallet and wishlist.',
            style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
          ),
          const SizedBox(height: DsSpace.s5),
          if (GoogleAuth.isConfigured) ...[
            const GoogleSignInButton(),
            const SizedBox(height: DsSpace.s5),
            Row(
              children: [
                Expanded(child: Divider(color: c.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
                  child: Text('or',
                      style:
                          TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                ),
                Expanded(child: Divider(color: c.line)),
              ],
            ),
            const SizedBox(height: DsSpace.s5),
          ],
          BxTabs(
            tabs: const [BxTab('password', 'Email'), BxTab('otp', 'Phone OTP')],
            value: _useOtp ? 'otp' : 'password',
            onChanged: (v) => setState(() {
              _useOtp = v == 'otp';
              _error = null;
              _notice = null;
            }),
          ),
          const SizedBox(height: DsSpace.s5),
          if (_error != null) ...[
            BxAlert(_error!, tone: BxTone.danger),
            const SizedBox(height: DsSpace.s4),
          ],
          if (_notice != null) ...[
            BxAlert(_notice!, tone: BxTone.success),
            const SizedBox(height: DsSpace.s4),
          ],
          if (!_useOtp) ...[
            BxField(
              label: 'Email address',
              hint: 'you@example.com',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: DsSpace.s4),
            BxField(
              label: 'Password',
              controller: _password,
              obscureText: true,
              onSubmitted: (_) => _signIn(),
            ),
            const SizedBox(height: DsSpace.s5),
            BxButton(
              label: 'Sign in',
              size: BxButtonSize.lg,
              fullWidth: true,
              loading: _busy,
              onPressed: _busy ? null : _signIn,
            ),
            const SizedBox(height: DsSpace.s4),
            Center(
              child: BxButton(
                label: 'New here? Create an account',
                variant: BxButtonVariant.link,
                size: BxButtonSize.sm,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
              ),
            ),
          ] else ...[
            BxField(
              label: 'Phone number',
              hint: '10-digit mobile number',
              controller: _phone,
              keyboardType: TextInputType.phone,
              enabled: !_otpSent,
            ),
            if (_otpSent) ...[
              const SizedBox(height: DsSpace.s4),
              BxField(
                label: 'One-time password',
                hint: '6-digit code',
                helper: 'Sent by SMS. Expires in 5 minutes.',
                controller: _otp,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _verifyOtp(),
              ),
            ],
            const SizedBox(height: DsSpace.s5),
            BxButton(
              label: _otpSent ? 'Verify and sign in' : 'Send OTP',
              size: BxButtonSize.lg,
              fullWidth: true,
              loading: _busy,
              onPressed: _busy ? null : (_otpSent ? _verifyOtp : _sendOtp),
            ),
            if (_otpSent) ...[
              const SizedBox(height: DsSpace.s2),
              BxButton(
                label: 'Use a different number',
                variant: BxButtonVariant.ghost,
                size: BxButtonSize.sm,
                fullWidth: true,
                onPressed: () => setState(() {
                  _otpSent = false;
                  _otp.clear();
                }),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _signIn() =>
      _run(() => AppState.instance.signIn(_email.text.trim(), _password.text));

  void _sendOtp() => _run(
        () async {
          await AppState.instance.sendOtp(_phone.text.trim());
          if (mounted) setState(() => _otpSent = true);
        },
        notice:
            'OTP sent. In this sandbox it is written to the API log rather than texted.',
      );

  void _verifyOtp() => _run(
      () => AppState.instance.verifyOtp(_phone.text.trim(), _otp.text.trim()));
}

// ─── Signed in ───────────────────────────────────────────────────────────────

class _AccountHome extends StatefulWidget {
  const _AccountHome();

  @override
  State<_AccountHome> createState() => _AccountHomeState();
}

class _AccountHomeState extends State<_AccountHome> {
  /// Pulling down refreshes the balances shown in the two tiles.
  Future<void> _load() => AppState.instance.refreshUser();

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final user = AppState.instance.user!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My account'),
        actions: [
          const ThemeModeButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: AppState.instance.signOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: c.accent,
        child: ListView(
          padding: const EdgeInsets.all(DsSpace.s4),
          children: [
            BxCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: c.accentSoft,
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: DsText.lg,
                        fontWeight: DsWeight.black,
                        color: c.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: DsSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: TextStyle(
                            fontSize: DsText.md,
                            fontWeight: DsWeight.black,
                            color: c.ink,
                          ),
                        ),
                        Text(user.email,
                            style: TextStyle(
                                fontSize: DsText.xs, color: c.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DsSpace.s3),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: DsBrand.walletName,
                    value: formatMoney(user.walletBalance),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: _StatCard(
                    label: DsBrand.loyaltyName,
                    value: '${user.loyaltyPoints}',
                    icon: Icons.stars_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DsSpace.s3),
            BxCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _AccountLink(
                    icon: Icons.receipt_long_outlined,
                    label: 'My orders',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OrdersScreen()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.person_outline,
                    label: 'Profile & settings',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '${DsBrand.walletName} & ${DsBrand.loyaltyName}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WalletScreen()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.card_giftcard_outlined,
                    label: 'Refer & earn',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ReferralsScreen()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.location_on_outlined,
                    label: 'Saved addresses',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddressScreen()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.favorite_border,
                    label: 'Wishlist',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WishlistScreen()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.assignment_return_outlined,
                    label: 'Returns & refunds',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReturnsScreen()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.rate_review_outlined,
                    label: 'My reviews',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MyReviewsScreen()),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.support_agent_outlined,
                    label: 'Help & support',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => SupportScreen(api: HttpSupportApi(() => AppState.instance.token))),
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  _AccountLink(
                    icon: Icons.notifications_none,
                    label: 'Notifications',
                    badge: AppState.instance.unreadNotifications,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()),
                      );
                      AppState.instance.refreshUnread();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return BxCard(
      padding: const EdgeInsets.all(DsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(height: DsSpace.s2),
          Text(value,
              style: TextStyle(
                  fontSize: DsText.lg,
                  fontWeight: DsWeight.black,
                  color: c.ink)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle)),
        ],
      ),
    );
  }
}

class _AccountLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  const _AccountLink(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return ListTile(
      leading: Icon(icon, size: 20, color: c.inkMuted),
      title: Text(
        label,
        style: TextStyle(
            fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge > 0) BxBadge('$badge', tone: BxTone.danger),
          Icon(Icons.chevron_right, color: c.inkSubtle),
        ],
      ),
      onTap: onTap,
    );
  }
}
