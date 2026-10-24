import 'package:url_launcher/url_launcher.dart';

/// The way from the shopping app to the seller app. Selling is a separate app:
/// the shopping app has no seller screens, only this link.
class VendorAppLink {
  VendorAppLink._();

  /// Where the seller app is published. Override per build with
  /// `--dart-define=VENDOR_APP_URL=...` (a different store, or a web page that
  /// explains how to get it).
  static const url = String.fromEnvironment(
    'VENDOR_APP_URL',
    defaultValue: 'https://play.google.com/store/apps/details?id=in.bazaarx.seller',
  );

  /// Opens the link. Replaceable in tests, which must not leave the app.
  static Future<bool> Function() open = _launch;

  static Future<bool> _launch() async {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
