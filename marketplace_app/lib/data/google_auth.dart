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
  /// This store's own Web OAuth client id (public by design: it ships inside the
  /// app). There is no default: a build without one does not offer "Continue with
  /// Google", rather than borrowing another business's Google project. Set it per
  /// client (and create the Android client for the app's package in Google Cloud):
  ///
  ///     flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=…apps.googleusercontent.com
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Web builds identify the app by the client id in a meta tag rather than by
  /// package name, so the plugin needs it passed explicitly there too.
  static const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static bool get isConfigured =>
      kIsWeb ? _webClientId.isNotEmpty : _serverClientId.isNotEmpty;

  static final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: !kIsWeb && _serverClientId.isNotEmpty ? _serverClientId : null,
    clientId: kIsWeb && _webClientId.isNotEmpty ? _webClientId : null,
  );

  /// Returns the ID token, or null when the user backs out of the sheet.
  ///
  /// Cancellation is a normal outcome, not an error — showing "sign-in failed"
  /// because somebody changed their mind is the classic version of this bug.
  static Future<String?> signIn() async {
    if (!isConfigured) {
      throw StateError(
        'Google sign-in is not configured in this build. Pass '
        '--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id> (and '
        'GOOGLE_WEB_CLIENT_ID for web builds).',
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
