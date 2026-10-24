import 'package:flutter/material.dart';

import '../data/local_notifications.dart';
import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../seller/seller.dart';
import 'vendor_session.dart';
import 'vendor_sign_in.dart';

/// What the seller area needs from this app: the session's token, a way to sign
/// out, and a phone notification when an order arrives while the dashboard is open.
/// There is no shop to switch to, so no "shop as a customer".
SellerHost buildVendorHost() => SellerHost(
      token: () => VendorSession.instance.token,
      onSignOut: VendorSession.instance.signOut,
      marketplaceName: DsBrand.name,
      supportEmail: DsBrand.supportEmail,
      onAlert: _newOrderAlert,
    );

Future<void> _newOrderAlert(String title, String body) async {
  try {
    if (await LocalNotifications.instance.requestPermission()) {
      await LocalNotifications.instance.show(key: 'seller-new-order', title: title, body: body);
    }
  } catch (_) {
    // No permission, or no plugin (tests): the dashboard's own banner still shows.
  }
}

/// The seller app: a sign-in, then the seller area (apply, get approved, run the shop).
class VendorApp extends StatelessWidget {
  /// Injectable for tests; the real app talks to the API.
  final SellerApi? api;
  final DocumentPicker? picker;

  const VendorApp({super.key, this.api, this.picker});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VendorSession.instance,
      builder: (context, _) => MaterialApp(
        title: '${DsBrand.name} Seller',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: buildMaterialTheme(isDark: false),
        darkTheme: buildMaterialTheme(isDark: true),
        builder: (context, child) {
          final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
          return DsThemeScope(isDark: isDark, child: child ?? const SizedBox.shrink());
        },
        home: VendorGate(api: api, picker: picker),
      ),
    );
  }
}

/// Signed out → sign in. Signed in → the seller area. Marketplace staff land on
/// their own shop when the store is a single business, and are pointed to the
/// website otherwise (running a marketplace is not a phone job).
class VendorGate extends StatefulWidget {
  final SellerApi? api;
  final DocumentPicker? picker;

  const VendorGate({super.key, this.api, this.picker});

  @override
  State<VendorGate> createState() => _VendorGateState();
}

class _VendorGateState extends State<VendorGate> {
  bool _checking = false;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = VendorSession.instance.isSignedIn;
    VendorSession.instance.addListener(_onSession);
    _ensurePlatform();
  }

  void _onSession() {
    final now = VendorSession.instance.isSignedIn;
    final fresh = now && !_wasSignedIn;
    _wasSignedIn = now;
    if (fresh) _ensurePlatform();
  }

  /// Staff need to know what kind of store this is before they can be sent anywhere.
  Future<void> _ensurePlatform() async {
    final session = VendorSession.instance;
    if (!(session.user?.isStaff ?? false) || session.platformLoaded || _checking) return;
    setState(() => _checking = true);
    await session.loadPlatform();
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    VendorSession.instance.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VendorSession.instance,
      builder: (context, _) {
        final session = VendorSession.instance;
        final user = session.user;
        if (!session.isSignedIn || user == null) return const VendorSignInScreen();

        if (user.isStaff) {
          if (!session.platformLoaded) {
            return _checking
                ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                : _StaffNotice(message: 'Could not load the store details.', onRetry: _ensurePlatform);
          }
          if (session.storeMode == 'single') {
            return SellerArea.house(
              buildVendorHost(),
              session.storeName.isEmpty ? DsBrand.name : session.storeName,
              api: widget.api,
              picker: widget.picker,
            );
          }
          return const _StaffNotice();
        }

        return SellerArea(
          host: buildVendorHost(),
          api: widget.api,
          picker: widget.picker ?? const FilePickerDocumentPicker(),
        );
      },
    );
  }
}

class _StaffNotice extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _StaffNotice({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(DsSpace.s5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.admin_panel_settings_outlined, size: 48, color: c.inkMuted),
              const SizedBox(height: DsSpace.s3),
              Text('This is a staff account',
                  style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
              const SizedBox(height: DsSpace.s2),
              Text(
                message ?? 'Marketplace staff manage shops, orders and payouts from the website admin. The seller app is for shop owners.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkMuted),
              ),
              const SizedBox(height: DsSpace.s4),
              if (onRetry != null) ...[
                BxButton(key: const Key('staff-retry'), label: 'Try again', onPressed: onRetry),
                const SizedBox(height: DsSpace.s2),
              ],
              BxButton(
                key: const Key('staff-sign-out'),
                label: 'Sign out',
                variant: BxButtonVariant.secondary,
                onPressed: VendorSession.instance.signOut,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
