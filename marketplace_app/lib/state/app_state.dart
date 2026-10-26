import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import '../data/bundles.dart';
import '../data/order_alerts.dart';
import '../data/models.dart';
import '../data/product_options.dart';
import '../data/google_auth.dart';
import '../data/store_config.dart';
import '../design/brand.g.dart';
import '../design/theme_overrides.dart';

/// Cart, session and theme, in one ChangeNotifier.
///
/// The web app splits this across StoreProvider / ThemeProvider / localStorage;
/// keeping it in one place here avoids pulling in a state-management package
/// for what is, in the end, three pieces of state and a persistence call.
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const _cartKey = 'cart';
  static const _tokenKey = OrderAlerts.tokenKey;
  static const _userKey = 'auth_user';
  static const _themeKey = 'theme_mode';
  static const _themeOverridesKey = 'theme_overrides';
  static const _storeConfigKey = 'store_config';

  SharedPreferences? _prefs;

  final List<CartLine> _cart = [];
  String? _token;
  AuthUser? _user;
  ThemeMode _themeMode = ThemeMode.system;

  /// Wishlist membership, product id -> wishlist item id. Lets every product
  /// card and detail screen show the right heart without its own request.
  final Map<String, String> _wishlist = {};
  List<Bundle> _bundles = [];
  int _unreadNotifications = 0;

  /// Fired once a session exists (sign-in or restored from disk), and just
  /// before one ends. The shell wires push registration to these so this class
  /// stays free of any Firebase dependency.
  VoidCallback? onSessionStarted;
  void Function(String token)? onSessionEnding;

  // ── What kind of store this is ─────────────────────────────────────────────

  StoreConfig _storeConfig = StoreConfig.fallback;

  /// The store this app belongs to.
  StoreConfig get storeConfig => _storeConfig;

  /// Reads the store's kind from the server and remembers it, so the next launch
  /// opens in the right shape before the network answers.
  Future<void> loadStoreConfig() async {
    try {
      final data = await ApiClient.request('/config');
      if (data is! Map<String, dynamic>) return;
      _storeConfig = StoreConfig.fromJson(data);
      GoogleAuth.configure(_storeConfig.googleServerClientId);
      await _prefs?.setString(DsBrand.storageKey(_storeConfigKey), jsonEncode(data));
      notifyListeners();
    } catch (_) {
      // An older server has no such endpoint; keep what we had.
    }
  }

  /// For tests: act as a store of a given kind without a server.
  @visibleForTesting
  void useStoreConfig(StoreConfig config) {
    _storeConfig = config;
    GoogleAuth.configure(config.googleServerClientId);
    notifyListeners();
  }

  void _applyCachedStoreConfig() {
    final raw = _prefs?.getString(DsBrand.storageKey(_storeConfigKey));
    if (raw == null) return;
    try {
      _storeConfig = StoreConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      GoogleAuth.configure(_storeConfig.googleServerClientId);
    } catch (_) {
      _storeConfig = StoreConfig.fallback;
    }
  }

  bool isWishlisted(String productId) => _wishlist.containsKey(productId);
  int get unreadNotifications => _unreadNotifications;

  List<CartLine> get cart => List.unmodifiable(_cart);
  int get cartCount => _cart.fold(0, (sum, l) => sum + l.quantity);
  double get cartSubtotal => _cart.fold(0, (sum, l) => sum + l.lineTotal);

  /// The order value above which delivery is free, as the store has configured
  /// it (default until the store answers). The API applies the same figure at
  /// checkout; this one only drives the cart's progress bar and estimate.
  double _freeShippingThreshold = 1999;
  double get freeShippingThreshold => _freeShippingThreshold;

  Future<void> loadStoreSettings() async {
    try {
      final data = await ApiClient.request('/settings');
      final value = data is Map ? data['free_shipping_threshold'] : null;
      if (value is num && value >= 0) {
        _freeShippingThreshold = value.toDouble();
        notifyListeners();
      }
    } catch (_) {
      // The default is a sensible estimate; the server decides the real fee.
    }
  }

  /// Shown as an estimate only - the server recomputes it and its number is the
  /// one that bills.
  double get estimatedShipping =>
      cartNetSubtotal >= _freeShippingThreshold || cartNetSubtotal == 0 ? 0 : 79;

  /// What the shopper saves against the listed prices (MRP), plus bundle deals.
  double get cartMrpTotal => _cart.fold(
      0.0,
      (sum, l) =>
          sum + l.unitMrp * l.quantity);
  double get cartTotalSavings =>
      (cartMrpTotal - cartSubtotal).clamp(0, double.infinity) + cartBundleDiscount;
  double get estimatedTotal => cartNetSubtotal + estimatedShipping;

  // ── Bundle deals ───────────────────────────────────────────────────────────

  List<Bundle> get bundles => List.unmodifiable(_bundles);

  /// Bundles the cart currently qualifies for. An estimate: the API re-prices
  /// the order and its figure is the one charged.
  List<AppliedBundle> get cartBundles => BundlePricing.apply(_cart, _bundles);
  double get cartBundleDiscount => BundlePricing.discount(_cart, _bundles);
  double get cartNetSubtotal => cartSubtotal - cartBundleDiscount;

  /// Bundles featuring [productId], for its product page.
  List<Bundle> bundlesFor(String productId) =>
      _bundles.where((b) => b.includes(productId)).toList();

  Future<void> loadBundles() async {
    try {
      final data = await ApiClient.request('/deals/bundles');
      _bundles = (data as List)
          .whereType<Map<String, dynamic>>()
          .map(Bundle.tryParse)
          .whereType<Bundle>()
          .toList();
      notifyListeners();
    } catch (_) {
      // No bundles is the normal state; a failed read just leaves it that way.
    }
  }

  // ── Admin colours ──────────────────────────────────────────────────────────

  /// The store logo the admin uploaded in the web panel, or null while the
  /// shipped initials mark is in use.
  String? _logoUrl;
  String? get logoUrl => _logoUrl;

  static String? _logoFrom(Map<String, dynamic> theme) {
    final url = theme['logo_url'];
    return url is String && url.startsWith('http') ? url : null;
  }

  /// Applies the colours the admin chose in the web panel. The last good answer
  /// is cached, so the app opens in the right colours before the network
  /// answers and keeps them when it is offline.
  Future<void> loadThemeOverrides() async {
    try {
      final data = await ApiClient.request('/theme');
      if (data is! Map<String, dynamic>) return;
      DsPalette.applyFromApi(data);
      _logoUrl = _logoFrom(data);
      await _prefs?.setString(
          DsBrand.storageKey(_themeOverridesKey), jsonEncode(data));
      notifyListeners();
    } catch (_) {
      // Keep whatever palette is already in use.
    }
  }

  void _applyCachedThemeOverrides() {
    final raw = _prefs?.getString(DsBrand.storageKey(_themeOverridesKey));
    if (raw == null) return;
    try {
      final cached = jsonDecode(raw) as Map<String, dynamic>;
      DsPalette.applyFromApi(cached);
      _logoUrl = _logoFrom(cached);
    } catch (_) {
      DsPalette.reset();
    }
  }

  String? get token => _token;
  AuthUser? get user => _user;
  bool get isSignedIn => _token != null;
  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    _token = _prefs!.getString(DsBrand.storageKey(_tokenKey));

    final rawUser = _prefs!.getString(DsBrand.storageKey(_userKey));
    _user = null;
    if (rawUser != null) {
      try {
        _user = AuthUser.fromJson(jsonDecode(rawUser) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
      }
    }
    if (_user == null) _token = null;

    // Earlier builds kept a "seller mode" here; selling is its own app now.
    _prefs!.remove(DsBrand.storageKey('seller_active'));
    _prefs!.remove(DsBrand.storageKey('seller_mode'));

    switch (_prefs!.getString(DsBrand.storageKey(_themeKey))) {
      case 'light':
        _themeMode = ThemeMode.light;
      case 'dark':
        _themeMode = ThemeMode.dark;
      default:
        _themeMode = ThemeMode.system;
    }

    // A dead token must clear the session rather than leave the app rendering
    // empty lists as though the account had no data — the same bug the web
    // client was fixed for.
    ApiClient.onUnauthorized = signOut;

    _applyCachedThemeOverrides();
    _applyCachedStoreConfig();
    notifyListeners();
    // First of the startup reads: the home screen's shape depends on it.
    unawaited(loadStoreConfig());
    unawaited(_loadSecondary());
    if (_token != null) _refreshAccountExtras();
  }

  /// Colours, bundles and store settings are nice to have, not needed to paint
  /// the first screen. They wait a moment and go one at a time, so launching the
  /// app is a handful of requests rather than a burst a small server can trip on.
  /// Off in tests, where a pending timer would fail the test.
  static bool staggerStartup = true;

  static Future<void> _wait(int milliseconds) => staggerStartup
      ? Future<void>.delayed(Duration(milliseconds: milliseconds))
      : Future<void>.value();

  Future<void> _loadSecondary() async {
    await _wait(1500);
    await loadThemeOverrides();
    await loadStoreSettings();
    await loadBundles();
  }

  void _refreshAccountExtras() {
    unawaited(() async {
      await _wait(2500);
      await loadWishlist();
      await refreshUnread();
    }());
    onSessionStarted?.call();
  }

  // ── Wishlist ───────────────────────────────────────────────────────────────

  Future<void> loadWishlist() async {
    if (_token == null) return;
    try {
      final data = await ApiClient.request('/wishlists', token: _token) as List;
      _wishlist.clear();
      for (final list in data) {
        for (final item in (list['items'] as List? ?? [])) {
          final productId = item['product_id']?.toString();
          if (productId != null) _wishlist[productId] = item['id'].toString();
        }
      }
      notifyListeners();
    } catch (_) {
      // Hearts are cosmetic until tapped; a failed read must not surface.
    }
  }

  /// Adds or removes [product]. Returns the new saved state. Throws
  /// [ApiException] on failure so the caller can tell the shopper.
  Future<bool> toggleWishlist(Product product, {Variant? variant}) async {
    final existing = _wishlist[product.id];
    if (existing != null) {
      await ApiClient.request('/wishlist-items/$existing',
          method: 'DELETE', token: _token);
      _wishlist.remove(product.id);
      notifyListeners();
      return false;
    }
    final data = await ApiClient.request(
      '/wishlist-items',
      method: 'POST',
      token: _token,
      body: {
        'product_id': product.id,
        if (variant != null) 'variant_id': variant.id,
      },
    ) as Map<String, dynamic>;
    _wishlist[product.id] = data['id'].toString();
    notifyListeners();
    return true;
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  Future<void> refreshUnread() async {
    if (_token == null) return;
    try {
      final body = await ApiClient.request('/notifications',
          token: _token, envelope: true, query: {'unread_only': '1'});
      _unreadNotifications = (body['unread_count'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  void setUnread(int count) {
    _unreadNotifications = count;
    notifyListeners();
  }

  /// Applies a freshly saved profile without a second round trip.
  void updateUser(AuthUser user) {
    _user = user;
    _prefs?.setString(DsBrand.storageKey(_userKey), jsonEncode(user.toJson()));
    notifyListeners();
  }

  // ── Theme ──────────────────────────────────────────────────────────────────

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs?.setString(DsBrand.storageKey(_themeKey), mode.name);
    notifyListeners();
  }

  void toggleTheme(BuildContext context) {
    final effectiveDark = _themeMode == ThemeMode.system
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : _themeMode == ThemeMode.dark;
    setThemeMode(effectiveDark ? ThemeMode.light : ThemeMode.dark);
  }

  // ── Cart ───────────────────────────────────────────────────────────────────

  bool addToCart(Product product,
      {Variant? variant,
      int quantity = 1,
      OptionSelection selection = OptionSelection.empty}) {
    variant ??= product.variants.where((v) => v.stock > 0).firstOrNull;
    // A product with required options can't be added until they're chosen.
    if (ProductOptionMath.problem(product.optionGroups, selection) != null) {
      return false;
    }
    if (!product.inStock ||
        quantity <= 0 ||
        variant == null ||
        variant.stock <= 0 ||
        !product.variants.any((v) => v.id == variant!.id)) {
      return false;
    }
    final line = CartLine(
        product: product,
        variant: variant,
        quantity: quantity,
        selection: selection);
    final existing = _cart.indexWhere((l) => l.key == line.key);
    final total = quantity + (existing >= 0 ? _cart[existing].quantity : 0);
    // Stock belongs to the variant, so "pizza, no onion" and "pizza, extra
    // cheese" draw on the same pool.
    final sameVariant = _cart
        .where((l) => l.product.id == product.id && l.variant?.id == variant!.id)
        .fold<int>(0, (sum, l) => sum + l.quantity);
    final others = sameVariant - (existing >= 0 ? _cart[existing].quantity : 0);
    if (total + others > variant.stock || total > 20) return false;
    if (existing >= 0) {
      _cart[existing].quantity += quantity;
    } else {
      _cart.add(line);
    }
    _persistCart();
    notifyListeners();
    return true;
  }

  void updateQuantity(String key, int quantity) {
    final i = _cart.indexWhere((l) => l.key == key);
    if (i < 0) return;
    if (quantity <= 0) {
      _cart.removeAt(i);
    } else {
      final stock = _cart[i].variant?.stock ?? 0;
      if (stock <= 0) return;
      _cart[i].quantity = quantity.clamp(1, stock.clamp(1, 20));
    }
    _persistCart();
    notifyListeners();
  }

  void removeFromCart(String key) => updateQuantity(key, 0);

  /// Puts a removed line back where it was (the Undo on the cart's snackbar).
  void restoreLine(CartLine line, int quantity, int index) {
    if (_cart.any((l) => l.key == line.key)) return;
    line.quantity = quantity;
    _cart.insert(index.clamp(0, _cart.length), line);
    _persistCart();
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _persistCart();
    notifyListeners();
  }

  /// Only ids and quantities are persisted. Prices and stock are re-read from
  /// the API on the next launch, so a cart restored a week later can't quote a
  /// stale price back to the user.
  void _persistCart() {
    final payload = _cart
        .map((l) => {
              'product_id': l.product.id,
              'variant_id': l.variant?.id,
              'quantity': l.quantity,
              if (!l.selection.isEmpty) 'options': l.selection.toJson(),
            })
        .toList();
    _prefs?.setString(DsBrand.storageKey(_cartKey), jsonEncode(payload));
  }

  Future<void> restoreCart() async {
    final raw = _prefs?.getString(DsBrand.storageKey(_cartKey));
    if (raw == null || raw.isEmpty) return;

    try {
      final entries = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      var unavailable = false;
      for (final e in entries) {
        try {
          final data = await ApiClient.request('/products/${e['product_id']}');
          final product = Product.fromJson(data as Map<String, dynamic>);
          final variant = product.variants
              .where((v) => v.id == e['variant_id'])
              .firstOrNull;
          if (!product.inStock || variant == null || variant.stock <= 0) {
            continue;
          }
          final selection = OptionSelection.fromJson(e['options']);
          // A choice withdrawn since the cart was saved drops the line rather
          // than quoting a price the server would refuse.
          if (ProductOptionMath.problem(product.optionGroups, selection) != null) {
            continue;
          }
          final line = CartLine(
              product: product,
              variant: variant,
              selection: selection,
              quantity: (e['quantity'] as int? ?? 1)
                  .clamp(1, variant.stock.clamp(1, 20)));
          if (!_cart.any((current) => current.key == line.key)) _cart.add(line);
        } on ApiException catch (error) {
          // One removed product must not prevent restoring the remaining items.
          if (error.status != 404 && error.status != 410) unavailable = true;
        } catch (_) {
          unavailable = true;
        }
      }
      if (!unavailable) _persistCart();
      notifyListeners();
    } catch (_) {
      // A product that has since been delisted shouldn't block app start.
    }
  }

  // ── Session ────────────────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) async {
    final data = await ApiClient.request(
      '/auth/login',
      method: 'POST',
      body: {'email': email, 'password': password},
    ) as Map<String, dynamic>;

    _token = data['token'] as String;
    _user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persistSession();
    notifyListeners();
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? referralCode,
  }) async {
    final data = await ApiClient.request(
      '/auth/register',
      method: 'POST',
      body: {
        'name': name,
        'email': email,
        'password': password,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
      },
    ) as Map<String, dynamic>;

    _token = data['token'] as String;
    _user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persistSession();
    notifyListeners();
  }

  /// Exchanges a Google ID token for a session.
  ///
  /// The app never sees a password and never decides who the user is — it hands
  /// the ID token over and the server verifies it with Google, including that
  /// the token was issued for *this* app. See GoogleIdentityService.
  Future<void> signInWithGoogleIdToken(String idToken,
      {String? referralCode}) async {
    final data = await ApiClient.request(
      '/auth/google',
      method: 'POST',
      body: {
        'id_token': idToken,
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
      },
    ) as Map<String, dynamic>;

    _token = data['token'] as String;
    _user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persistSession();
    notifyListeners();
  }

  Future<void> sendOtp(String phone) => ApiClient.request('/auth/otp/send',
      method: 'POST', body: {'phone': phone});

  Future<void> verifyOtp(String phone, String otp) async {
    final data = await ApiClient.request(
      '/auth/otp/verify',
      method: 'POST',
      body: {'phone': phone, 'otp': otp},
    ) as Map<String, dynamic>;

    _token = data['token'] as String;
    _user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persistSession();
    notifyListeners();
  }

  /// Re-read the profile after anything that moves the wallet or points —
  /// placing an order, cancelling one, a refund landing. Without this the
  /// checkout screen keeps offering a wallet balance that has already been spent.
  Future<void> refreshUser() async {
    if (_token == null) return;

    try {
      final data = await ApiClient.request('/auth/me', token: _token)
          as Map<String, dynamic>;
      _user = AuthUser.fromJson(data['user'] as Map<String, dynamic>? ?? data);
      await _prefs?.setString(
          DsBrand.storageKey(_userKey), jsonEncode(_user!.toJson()));
      notifyListeners();
    } catch (_) {
      // A stale balance is better than a broken screen; the next successful
      // call corrects it.
    }
  }

  Future<void> _persistSession() async {
    await _prefs?.setString(DsBrand.storageKey(_tokenKey), _token!);
    await _prefs?.setString(
        DsBrand.storageKey(_userKey), jsonEncode(_user!.toJson()));
    _refreshAccountExtras();
  }

  void signOut() {
    final ending = _token;
    if (ending != null) onSessionEnding?.call(ending);
    _token = null;
    _user = null;
    _wishlist.clear();
    _unreadNotifications = 0;
    _prefs?.remove(DsBrand.storageKey(_tokenKey));
    _prefs?.remove(DsBrand.storageKey(_userKey));
    notifyListeners();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
