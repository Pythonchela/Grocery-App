import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Wraps Google Sign-In so the rest of the app deals in "an ID token or an
/// error", never in plugin types.
///
/// The ID token is the whole point. An *access* token only proves the app
/// talked to Google; an ID token is a signed assertion about who the user is,
/// which is the thing the server can independently verify. On Android that
/// requires passing the **web** OAuth client id as `serverClientId` — without
/// it the plugin returns an access token, `idToken` is null, and sign-in fails
/// with nothing useful to show the user.
class GoogleAuth {
  /// The Web OAuth client id, from the store (the owner sets it in Settings, so no
  /// rebuild is needed), or from the build for local work:
  ///
  ///     flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=…apps.googleusercontent.com
  ///
  /// There is no default: a store without its own Google setup does not offer
  /// "Continue with Google" rather than borrowing another business's project.
  static const _buildClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Web builds identify the app by the client id in a meta tag rather than by
  /// package name, so the plugin needs it passed explicitly there too.
  static const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static String _storeClientId = '';
  static GoogleSignIn? _client;
  static String? _clientFor;

  /// Called with what the store's config says. Safe to call again when it changes.
  static void configure(String serverClientId) {
    _storeClientId = serverClientId.trim();
  }

  static String get _serverClientId => _storeClientId.isNotEmpty ? _storeClientId : _buildClientId;

  static bool get isConfigured =>
      kIsWeb ? _webClientId.isNotEmpty : _serverClientId.isNotEmpty;

  /// Built on first use and again if the id changed, so a new id applies without a restart.
  static GoogleSignIn get _google {
    if (_client == null || _clientFor != _serverClientId) {
      _clientFor = _serverClientId;
      _client = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: !kIsWeb && _serverClientId.isNotEmpty ? _serverClientId : null,
        clientId: kIsWeb && _webClientId.isNotEmpty ? _webClientId : null,
      );
    }
    return _client!;
  }

  /// Returns the ID token, or null when the user backs out of the sheet.
  ///
  /// Cancellation is a normal outcome, not an error — showing "sign-in failed"
  /// because somebody changed their mind is the classic version of this bug.
  static Future<String?> signIn() async {
    if (!isConfigured) {
      throw StateError(
        'Google sign-in is not set up for this store yet. Set '
        'the Google client id in the admin Settings (or '
        '--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>).',
      );
    }

    // Sign out first so the account chooser always appears. Otherwise the
    // plugin silently reuses the last account and a shared device gives the
    // second person the first person's order history.
    await _google.signOut();

    final account = await _google.signIn();
    if (account == null) return null;

    final auth = await account.authentication;
    final idToken = auth.idToken;

    if (idToken == null) {
      throw StateError(
        'Google returned no ID token. On Android this almost always means '
        'serverClientId is missing or is not the Web client id.',
      );
    }

    return idToken;
  }

  static Future<void> signOut() => _google.signOut();
}
