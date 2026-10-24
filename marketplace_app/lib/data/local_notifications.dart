import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Notifications the phone raises itself - no Firebase, no push server.
///
/// Used two ways: the order-update watcher shows one when it finds news the
/// shopper has not seen yet, and the app schedules reminders (rate your order)
/// that Android delivers on time even if the app is closed.
///
/// What this cannot do is wake the phone the instant something happens on the
/// server. That needs real push (see `docs/PUSH_NOTIFICATIONS.md`); until it is
/// set up, the watcher checks whenever the app is open and about every 15
/// minutes in the background.
class LocalNotifications {
  LocalNotifications._();

  static final LocalNotifications instance = LocalNotifications._();

  static const _channelId = 'order_updates';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionAsked = false;

  /// Receives the decoded `data` of a tapped notification (e.g. `order_id`).
  void Function(Map<String, dynamic> data)? onOpen;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _handleTap(response.payload),
    );
    _initialized = true;
  }

  /// If the app was launched by tapping one of these notifications, open it.
  Future<void> handleLaunch() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      _handleTap(details?.notificationResponse?.payload);
    }
  }

  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      if (await android.areNotificationsEnabled() == true) return true;
      if (_permissionAsked) return false;
      _permissionAsked = true;
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Order updates',
          channelDescription: 'Orders, deliveries, refunds and reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
        iOS: DarwinNotificationDetails(),
      );

  Future<void> show({
    required String key,
    required String title,
    String? body,
    Map<String, dynamic> data = const {},
  }) async {
    await init();
    await _plugin.show(
      id: stableId(key),
      title: title,
      body: body,
      notificationDetails: _details,
      payload: jsonEncode(data),
    );
  }

  /// Schedules a one-off reminder [after] from now. Re-scheduling the same [key]
  /// replaces the earlier one.
  Future<void> remind({
    required String key,
    required String title,
    required String body,
    required Duration after,
    Map<String, dynamic> data = const {},
  }) async {
    await init();
    await _plugin.zonedSchedule(
      id: stableId(key),
      title: title,
      body: body,
      // UTC is enough: this is "N days from now", not "at 9am local".
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(after),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode(data),
    );
  }

  Future<void> cancel(String key) async {
    await init();
    await _plugin.cancel(id: stableId(key));
  }

  void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) onOpen?.call(decoded);
    } catch (_) {
      // A payload we did not write; nothing to open.
    }
  }

  /// A stable positive 31-bit id for a string key, so the same logical
  /// notification replaces itself instead of stacking.
  @visibleForTesting
  static int stableId(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    hash &= 0x7fffffff; // the seed alone exceeds 31 bits, so mask even when empty
    return hash == 0 ? 1 : hash;
  }
}
