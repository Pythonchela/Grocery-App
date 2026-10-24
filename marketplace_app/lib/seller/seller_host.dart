import 'package:flutter/foundation.dart';

/// Everything the seller area needs from the app that hosts it.
///
/// This is the whole seam between the seller code and the rest of the app. The
/// shopper app fills it from its own session; a standalone seller app would fill
/// it from its own login. Nothing in `lib/seller/` reaches past it.
class SellerHost {
  /// The signed-in user's API token, read fresh on every request.
  final String? Function() token;

  /// Called when the seller area wants the host to end the session.
  final VoidCallback onSignOut;

  /// The marketplace's name, for headings ("Sell on BazaarX").
  final String marketplaceName;

  /// Shown wherever a seller is told to contact support.
  final String? supportEmail;

  /// Raises a notification on the phone (the host owns notifications), used
  /// when a new order arrives while the app is open.
  final void Function(String title, String body)? onAlert;

  /// Told when the order desk (the seller dashboard) opens and closes. While it
  /// is open the host should keep its own pop-ups away: the desk has its own
  /// banner, badge and sound, and a pop-up would cover the Accept and Decline
  /// buttons or lead the seller out of the screen they are working in.
  final void Function(bool open)? onDeskVisible;

  /// Lets the seller step out to shop as a customer. Null where there is no shop
  /// to switch to (a standalone seller app).
  final VoidCallback? onSwitchToShopping;

  const SellerHost({
    required this.token,
    required this.onSignOut,
    required this.marketplaceName,
    this.supportEmail,
    this.onAlert,
    this.onDeskVisible,
    this.onSwitchToShopping,
  });
}
