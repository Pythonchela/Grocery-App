import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import '../data/order_alerts.dart';
import '../design/brand.g.dart';
import '../design/theme_overrides.dart';

/// Who is signed in to the seller app.
class VendorUser {
  final String id;
  final String name;
  final String email;
  final String role;

  const VendorUser({required this.id, required this.name, required this.email, required this.role});

  /// Marketplace staff, as opposed to a shop's owner. Staff run the marketplace from
  /// the website; the only shop they operate from a phone is a single-business
  /// store's own.
  bool get isStaff => const ['ADMIN', 'SUPER_ADMIN', 'SUB_ADMIN'].contains(role);

  factory VendorUser.fromJson(Map<String, dynamic> json) => VendorUser(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        email: '${json['email'] ?? ''}',
        role: '${json['role'] ?? 'CUSTOMER'}',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email, 'role': role};
}

/// The seller app's session: a token and a user, kept on the phone.
///
/// Deliberately not the shopping app's `AppState`: that one carries a cart, a
/// wishlist and a home feed, none of which a shop's owner needs. The token is
/// stored under the same key the background order check reads
/// (`OrderAlerts.tokenKey`), so a closed app can still raise "new order" alerts.
class VendorSession extends ChangeNotifier {
  VendorSession._();

  static final VendorSession instance = VendorSession._();

  static const _userKey = 'auth_user';
  static const _themeKey = 'theme_overrides';

  SharedPreferences? _prefs;
  String? _token;
  VendorUser? _user;

  /// `single`, `hybrid` or `multi`: whether this marketplace has vendors or one business.
  String? _storeMode;
  String _storeName = '';
  String? _logoUrl;
  bool _platformLoaded = false;

  VoidCallback? onStarted;
  void Function(String token)? onEnding;

  String? get token => _token;
  VendorUser? get user => _user;
  bool get isSignedIn => _token != null && _user != null;
  String? get storeMode => _storeMode;
  String get storeName => _storeName;
  String? get logoUrl => _logoUrl;

  /// Whether the store kind has been read yet (staff need it to know where to land).
  bool get platformLoaded => _platformLoaded;

  String _key(String name) => DsBrand.storageKey(name);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs!.getString(_key(OrderAlerts.tokenKey));

    _user = null;
    final raw = _prefs!.getString(_key(_userKey));
    if (raw != null) {
      try {
        _user = VendorUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
      }
    }
    if (_user == null) _token = null;

    // A dead token ends the session instead of leaving empty screens behind.
    ApiClient.onUnauthorized = signOut;

    final cached = _prefs!.getString(_key(_themeKey));
    if (cached != null) {
      try {
        _applyTheme(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {
        DsPalette.reset();
      }
    }
    notifyListeners();
    if (_token != null) onStarted?.call();
  }

  void _applyTheme(Map<String, dynamic> theme) {
    DsPalette.applyFromApi(theme);
    final url = theme['logo_url'];
    _logoUrl = url is String && url.startsWith('http') ? url : null;
  }

  /// The marketplace's colours and logo, and what kind of store it is. Nice to
  /// have: a failure keeps whatever was known.
  Future<void> loadPlatform() async {
    try {
      final theme = await ApiClient.request('/theme');
      if (theme is Map<String, dynamic>) {
        _applyTheme(theme);
        await _prefs?.setString(_key(_themeKey), jsonEncode(theme));
      }
    } catch (_) {}

    try {
      final config = await ApiClient.request('/config');
      if (config is Map<String, dynamic>) {
        _storeMode = config['mode']?.toString();
        _storeName = config['store_name']?.toString() ?? '';
        _platformLoaded = true;
      }
    } catch (_) {}

    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final data = await ApiClient.request('/auth/login', method: 'POST', body: {'email': email, 'password': password});
    await _start(data as Map<String, dynamic>);
  }

  Future<void> register({required String name, required String email, required String password, String? phone}) async {
    final data = await ApiClient.request('/auth/register', method: 'POST', body: {
      'name': name,
      'email': email,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
    await _start(data as Map<String, dynamic>);
  }

  Future<void> _start(Map<String, dynamic> data) async {
    _token = data['token'] as String;
    _user = VendorUser.fromJson(data['user'] as Map<String, dynamic>);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key(OrderAlerts.tokenKey), _token!);
    await _prefs!.setString(_key(_userKey), jsonEncode(_user!.toJson()));
    notifyListeners();
    onStarted?.call();
  }

  /// Back to a launch with nothing known. For tests, which share one instance.
  @visibleForTesting
  void resetForTest() {
    _token = null;
    _user = null;
    _storeMode = null;
    _storeName = '';
    _logoUrl = null;
    _platformLoaded = false;
    onStarted = null;
    onEnding = null;
  }

  void signOut() {
    final ending = _token;
    if (ending != null) onEnding?.call(ending);
    _token = null;
    _user = null;
    _prefs?.remove(_key(OrderAlerts.tokenKey));
    _prefs?.remove(_key(_userKey));
    notifyListeners();
  }
}
