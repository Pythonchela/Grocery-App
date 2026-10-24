import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/local_notifications.dart';
import 'data/order_alerts.dart';
import 'data/push_notifications.dart';
import 'vendor/vendor_app.dart';
import 'vendor/vendor_session.dart';

/// The seller app: `flutter run --flavor vendor -t lib/main_vendor.dart`.
///
/// It shares the design system, the API client and the seller area with the
/// shopping app, and nothing else. In particular it has no cart, wishlist or
/// home feed, and the shopping app has no seller screens.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_IN');

  final session = VendorSession.instance;
  final push = PushNotifications.instance;
  final alerts = OrderAlerts.instance;

  // Push when Firebase is configured for this app. Otherwise a background check
  // about every 15 minutes raises a notification for a new order while the app is
  // closed; while it is open the dashboard watches for orders itself.
  session.onStarted = () {
    final token = session.token;
    if (token == null) return;
    unawaited(push.register(token));
    unawaited(alerts.syncBackground());
  };
  session.onEnding = (token) {
    unawaited(push.unregister(token));
    unawaited(alerts.stop());
  };
  push.onRegistered = alerts.syncBackground;

  await session.load();

  runApp(const VendorApp());
  // Colours and logo for the sign-in screen; a failure keeps what was cached.
  unawaited(session.loadPlatform());
  unawaited(OrderAlerts.initializeBackground());
  unawaited(push.init());
  unawaited(LocalNotifications.instance.handleLaunch());
}
