import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../design/brand.g.dart';
import 'api_client.dart';
import 'local_notifications.dart';
import 'push_notifications.dart';

/// One notification as the API sends it.
class AlertItem {
  final String id;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic> data;

  const AlertItem({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.data = const {},
  });

  static AlertItem? tryParse(dynamic raw) {
    if (raw is! Map<String, dynamic> || raw['id'] == null) return null;
    final data = raw['data'];
    return AlertItem(
      id: '${raw['id']}',
      type: '${raw['type'] ?? ''}',
      title: '${raw['title'] ?? ''}',
      body: raw['body']?.toString(),
      data: data is Map<String, dynamic> ? data : const {},
    );
  }
}

/// Finds order updates the shopper has not been told about yet, and tells them
/// exactly once.
///
/// "Told" is remembered on the phone (`alerted ids`), because the API only knows
/// whether something was *read*, not whether this phone has already pinged about
/// it. Without that memory every check would repeat the same alert.
class NotificationWatcher {
  /// Fetches unread notifications for a signed-in session.
  final Future<List<AlertItem>> Function(String token) fetch;

  /// Raises one alert. [summary] is true for the single "and N more" alert.
  final Future<void> Function(AlertItem item, {bool summary, int more}) show;

  final SharedPreferences prefs;

  /// How many to announce individually before collapsing the rest into one line.
  final int maxIndividual;

  NotificationWatcher({
    required this.fetch,
    required this.show,
    required this.prefs,
    this.maxIndividual = 3,
  });

  static const alertedKey = 'alerted_notification_ids';
  static const primedKey = 'alerted_notifications_primed';
  static const _memory = 300;

  /// Returns how many alerts were raised.
  Future<int> check(String token) async {
    final unread = await fetch(token);
    final alerted = (prefs.getStringList(alertedKey) ?? <String>[]).toList();
    final seen = alerted.toSet();

    // First ever run on this phone: everything unread is history, not news.
    // Remember it silently instead of burying the shopper in old alerts.
    if (prefs.getBool(primedKey) != true) {
      await prefs.setBool(primedKey, true);
      await _remember(alerted, unread.map((i) => i.id));
      return 0;
    }

    final fresh = unread.where((i) => !seen.contains(i.id)).toList();
    if (fresh.isEmpty) return 0;

    // The API lists newest first; announce oldest first so they read in order.
    final ordered = fresh.reversed.toList();
    final individually = ordered.length > maxIndividual
        ? ordered.sublist(ordered.length - maxIndividual)
        : ordered;
    final extra = ordered.length - individually.length;

    if (extra > 0) {
      await show(individually.first, summary: true, more: extra);
    }
    for (final item in individually) {
      await show(item, summary: false, more: 0);
    }

    await _remember(alerted, fresh.map((i) => i.id));
    return extra > 0 ? individually.length + 1 : individually.length;
  }

  Future<void> _remember(List<String> alerted, Iterable<String> ids) async {
    final merged = [...alerted, ...ids];
    final trimmed =
        merged.length > _memory ? merged.sublist(merged.length - _memory) : merged;
    await prefs.setStringList(alertedKey, trimmed);
  }

  /// Parses the API's list into [AlertItem]s, dropping anything malformed.
  static List<AlertItem> parse(dynamic data) => data is List
      ? data.map(AlertItem.tryParse).whereType<AlertItem>().toList()
      : const [];

  /// The real fetcher: unread notifications for [token].
  static Future<List<AlertItem>> fetchUnread(String token) async {
    final data = await ApiClient.request('/notifications',
        token: token, query: {'unread_only': '1'});
    return parse(data);
  }
}

// ─── Background ──────────────────────────────────────────────────────────────

/// Runs in its own isolate about every 15 minutes while the app is closed.
/// Android decides the exact moment (Doze and battery saver can delay it), which
/// is why this is "best effort" and real push is the proper answer.
@pragma('vm:entry-point')
void orderAlertsDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(DsBrand.storageKey(OrderAlerts.tokenKey));
      if (token == null) return true;

      await LocalNotifications.instance.init();
      await NotificationWatcher(
        fetch: NotificationWatcher.fetchUnread,
        show: OrderAlerts.showSystem,
        prefs: prefs,
      ).check(token);
    } catch (_) {
      // Try again next time; a failed check must not be retried in a tight loop.
    }
    return true;
  });
}

// ─── Coordinator ─────────────────────────────────────────────────────────────

/// Keeps the shopper informed about their orders without a push service:
///
/// * while the app is open, checks every minute and whenever it comes back to
///   the foreground, and shows a banner inside the app;
/// * while it is closed, asks Android to wake a background check about every
///   15 minutes and raises a system notification;
/// * schedules a reminder to review a delivered order.
///
/// All of it steps aside once real push is registered, so nobody is told twice.
class OrderAlerts with WidgetsBindingObserver {
  OrderAlerts._();

  static final OrderAlerts instance = OrderAlerts._();

  /// The storage key AppState keeps the session token under.
  static const tokenKey = 'auth_token';

  static const _taskName = 'order-alerts';
  static const _reviewReminderDelay = Duration(days: 2);

  /// Shows an in-app banner (foreground). Set by the shell.
  void Function(AlertItem item, {bool summary, int more})? showInApp;

  /// Called after each check so the unread badge can refresh.
  VoidCallback? onChecked;

  String? _token;
  Timer? _timer;
  bool _observing = false;
  bool _checking = false;

  bool get _pushHandlesIt => PushNotifications.instance.isRegistered;

  Future<void> start(String token) async {
    _token = token;

    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => checkNow());
    unawaited(checkNow());

    await syncBackground();
  }

  Future<void> stop() async {
    _token = null;
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
    try {
      await Workmanager().cancelByUniqueName(_taskName);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(checkNow());
  }

  /// Checks once, now. Safe to call from anywhere (after placing an order, on
  /// pull-to-refresh); overlapping calls collapse into one.
  Future<void> checkNow() async {
    final token = _token;
    if (token == null || _checking || _pushHandlesIt) return;
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await NotificationWatcher(
        fetch: NotificationWatcher.fetchUnread,
        show: (item, {bool summary = false, int more = 0}) async =>
            showInApp?.call(item, summary: summary, more: more),
        prefs: prefs,
      ).check(token);
      onChecked?.call();
    } catch (_) {
      // Offline or the API is down: try again on the next tick.
    } finally {
      _checking = false;
    }
  }

  /// Registers (or removes) the background check depending on whether push is
  /// already doing the job.
  Future<void> syncBackground() async {
    try {
      if (_pushHandlesIt) {
        await Workmanager().cancelByUniqueName(_taskName);
        return;
      }
      await LocalNotifications.instance.requestPermission();
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {
      // Platforms without background work (tests, web) just stay foreground-only.
    }
  }

  /// Asks Android to schedule the periodic check. Call once at startup.
  static Future<void> initializeBackground() async {
    try {
      await Workmanager().initialize(orderAlertsDispatcher);
    } catch (_) {}
  }

  /// The system notification used by the background check.
  static Future<void> showSystem(AlertItem item,
      {bool summary = false, int more = 0}) {
    return LocalNotifications.instance.show(
      key: summary ? 'summary' : 'n:${item.id}',
      title: summary ? '$more more updates on your orders' : item.title,
      body: summary ? 'Open ${DsBrand.name} to see them.' : item.body,
      data: summary ? const {} : {...item.data, 'notification_id': item.id},
    );
  }

  // ── Review reminder ────────────────────────────────────────────────────────

  /// Once an order is delivered, nudge the shopper to review it two days later.
  /// Scheduled at most once per order.
  Future<void> scheduleReviewReminder(String orderId, String orderNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'review_reminder_$orderId';
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);

      await LocalNotifications.instance.requestPermission();
      await LocalNotifications.instance.remind(
        key: key,
        title: 'How was your order?',
        body: 'Tell other shoppers what you thought of order $orderNumber.',
        after: _reviewReminderDelay,
        data: {'order_id': orderId},
      );
    } catch (_) {}
  }

  Future<void> cancelReviewReminder(String orderId) async {
    try {
      await LocalNotifications.instance.cancel('review_reminder_$orderId');
    } catch (_) {}
  }
}

