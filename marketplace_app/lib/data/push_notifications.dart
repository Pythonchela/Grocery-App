import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

/// Push notifications through Firebase Cloud Messaging.
///
/// The app builds and runs without any Firebase project: until
/// `android/app/google-services.json` exists, [init] fails quietly, [isAvailable]
/// stays false and nothing else in the app notices. Add the file and push turns
/// on with no code change. Every notification is also stored by the API, so the
/// in-app Notifications screen is complete either way — push only adds the nudge
/// when the app is closed.
class PushNotifications {
  PushNotifications._();

  static final PushNotifications instance = PushNotifications._();

  /// Lets a foreground message show a banner from outside the widget tree.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Set by the app shell: opens the screen a tapped notification points at.
  /// [data] is the `data` map the API attached (for example `order_id`).
  void Function(Map<String, dynamic> data)? onOpen;

  /// Called when a message arrives while the app is open, so counters refresh.
  VoidCallback? onForegroundMessage;

  /// Called once this phone is registered for real push, so the Firebase-free
  /// fallback can stand down and nobody is told twice.
  VoidCallback? onRegistered;

  bool _ready = false;
  bool _registered = false;
  bool _listening = false;
  String? _deviceToken;
  String? _authToken;

  bool get isAvailable => _ready;

  /// True when this phone has told the API where to send push. While true, the
  /// local order-alert watcher stays quiet.
  bool get isRegistered => _registered;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (_) {
      // No Firebase config in this build. Expected until the project exists.
      _ready = false;
      return;
    }

    if (!_listening) {
      _listening = true;
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _deviceToken = token;
        unawaited(_send(token));
      });

      // The app was launched by tapping a notification.
      try {
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _open(initial.data));
        }
      } catch (_) {}
    }

    if (_authToken != null) await register(_authToken!);
  }

  /// Ask permission and tell the API where to send this phone's notifications.
  /// Safe to call repeatedly, and before [init] has finished.
  Future<void> register(String authToken) async {
    _authToken = authToken;
    if (!_ready) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _deviceToken = token;
      await _send(token);
    } catch (_) {
      // Push is a nicety; a failure here must never reach the shopper.
    }
  }

  /// Stop sending to this phone for [authToken]'s account (sign-out).
  Future<void> unregister(String authToken) async {
    _authToken = null;
    _registered = false;
    final device = _deviceToken;
    if (!_ready || device == null) return;
    try {
      await ApiClient.request('/devices',
          method: 'DELETE', token: authToken, body: {'token': device});
    } catch (_) {}
  }

  Future<void> _send(String deviceToken) async {
    final auth = _authToken;
    if (auth == null) return;
    try {
      await ApiClient.request('/devices',
          method: 'POST',
          token: auth,
          body: {
            'token': deviceToken,
            'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          });
      if (!_registered) {
        _registered = true;
        onRegistered?.call();
      }
    } catch (_) {}
  }

  void _showForeground(RemoteMessage message) {
    onForegroundMessage?.call();

    final notification = message.notification;
    final text = [notification?.title, notification?.body]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' — ');
    if (text.isEmpty) return;

    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'View', onPressed: () => _open(message.data)),
    ));
  }

  void _open(Map<String, dynamic> data) => onOpen?.call(data);
}
