import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/local_notifications.dart';
import 'data/order_alerts.dart';
import 'data/push_notifications.dart';
import 'design/brand.g.dart';
import 'design/mobile.dart';
import 'design/mobile_components.dart';
import 'design/theme.dart';
import 'design/tokens.g.dart';
import 'screens/account_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/order_tracking_screen.dart';
import 'state/app_state.dart';
import 'widgets/cart_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Dates are formatted for en_IN; without this a phone set to another
  // language throws on the first date it draws.
  await initializeDateFormatting('en_IN');
  await AppState.instance.load();

  // Cart lines are rehydrated from the API rather than from disk, so a cart
  // restored a week later can't quote a stale price. Not awaited: a slow or
  // unreachable API must not hold up first paint.
  unawaited(AppState.instance.restoreCart());

  _wirePush();

  runApp(const MarketplaceApp());
  // After first frame is scheduled: notifications are optional and must never
  // delay it.
  unawaited(OrderAlerts.initializeBackground());
  unawaited(PushNotifications.instance.init());
  unawaited(LocalNotifications.instance.handleLaunch());
}

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

void _wirePush() {
  final push = PushNotifications.instance;
  final state = AppState.instance;

  final alerts = OrderAlerts.instance;

  // Real push when Firebase is configured; otherwise the phone watches for order
  // updates itself. Whichever is active, the other stays quiet.
  state.onSessionStarted = () {
    final token = state.token;
    if (token == null) return;
    unawaited(push.register(token));
    unawaited(alerts.start(token));
  };
  state.onSessionEnding = (token) {
    unawaited(push.unregister(token));
    unawaited(alerts.stop());
  };

  push.onRegistered = alerts.syncBackground;
  alerts.onChecked = state.refreshUnread;
  alerts.showInApp = (item, {bool summary = false, int more = 0}) {
    PushNotifications.messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(summary
          ? '$more more updates on your orders'
          : [item.title, item.body]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' — ')),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'View',
        onPressed: () => push.onOpen?.call(summary ? const {} : item.data),
      ),
    ));
  };
  LocalNotifications.instance.onOpen = (data) => push.onOpen?.call(data);

  push.onForegroundMessage = state.refreshUnread;
  push.onOpen = (data) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final orderId = data['order_id']?.toString();
    navigator.push(MaterialPageRoute(
      builder: (_) => orderId != null && orderId.isNotEmpty
          ? OrderTrackingScreen(orderId: orderId)
          : const NotificationsScreen(),
    ));
    state.refreshUnread();
  };
}

/// A snackbar belongs to the screen that raised it. Without this one with an
/// action ("View cart") can outlive its screen - and on phones with an
/// accessibility service on, it never times out - and follow the shopper all
/// the way through checkout.
class _SnackBarClearer extends NavigatorObserver {
  void _clear() =>
      PushNotifications.messengerKey.currentState?.hideCurrentSnackBar();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _clear();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _clear();
}

class MarketplaceApp extends StatelessWidget {
  const MarketplaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final mode = AppState.instance.themeMode;

        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: PushNotifications.messengerKey,
          navigatorObservers: [_SnackBarClearer()],
          title: DsBrand.name,
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: buildMaterialTheme(isDark: false),
          darkTheme: buildMaterialTheme(isDark: true),
          // DsThemeScope is what the CSS custom properties are on the web: the
          // single place that decides which set of token values the tree below
          // resolves against. No widget branches on brightness itself.
          builder: (context, child) {
            final isDark = switch (mode) {
              ThemeMode.dark => true,
              ThemeMode.light => false,
              ThemeMode.system =>
                MediaQuery.platformBrightnessOf(context) == Brightness.dark,
            };
            return DsThemeScope(
                isDark: isDark, child: child ?? const SizedBox.shrink());
          },
          home: const AppShell(),
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // IndexedStack rather than swapping the body: switching to Cart and back must
  // not refetch the home feed or lose its scroll position.
  final List<Widget?> _tabs = [
    const HomeScreen(),
    null,
    null,
    null,
    null,
  ];

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    PushNotifications.messengerKey.currentState?.hideCurrentSnackBar();
    setState(() {
      _index = index;
      _tabs[index] ??= switch (index) {
        1 => const CategoriesScreen(),
        2 => CartScreen(onStartShopping: () => _selectTab(0)),
        3 => const OrdersScreen(),
        4 => const AccountScreen(),
        _ => const HomeScreen(),
      };
    });
  }

  static const _labels = ['Home', 'Categories', 'Cart', 'Order again', 'Account'];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final cartCount = AppState.instance.cartCount;
        final window = context.dsWindow;
        final showCartBar = _index <= 1;

        final icons = <(Widget, Widget)>[
          (const Icon(Icons.home_outlined), const Icon(Icons.home)),
          (const Icon(Icons.grid_view_outlined), const Icon(Icons.grid_view)),
          (
            _CartIcon(count: cartCount, filled: false),
            _CartIcon(count: cartCount, filled: true)
          ),
          (
            const Icon(Icons.receipt_long_outlined),
            const Icon(Icons.receipt_long)
          ),
          (const Icon(Icons.person_outline), const Icon(Icons.person)),
        ];

        final items = [
          const BxNavItem(
              icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
          const BxNavItem(
              icon: Icons.grid_view_outlined,
              activeIcon: Icons.grid_view,
              label: 'Categories'),
          BxNavItem(
              icon: Icons.shopping_bag_outlined,
              activeIcon: Icons.shopping_bag,
              label: 'Cart',
              badge: cartCount),
          const BxNavItem(
              icon: Icons.replay_outlined,
              activeIcon: Icons.replay,
              label: 'Order again'),
          const BxNavItem(
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              label: 'Account'),
        ];

        final stack = IndexedStack(
          index: _index,
          children: _tabs.map((tab) => tab ?? const SizedBox.shrink()).toList(),
        );

        // Phones get the bottom bar, where a thumb rests. Anything wider (a
        // tablet, a foldable, a phone in landscape) gets a rail down the side
        // and content held to a readable width, instead of a stretched phone UI.
        if (window.usesRail) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) {
                      DsHaptics.select();
                      _selectTab(i);
                    },
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (var i = 0; i < _labels.length; i++)
                        NavigationRailDestination(
                          icon: icons[i].$1,
                          selectedIcon: icons[i].$2,
                          label: Text(_labels[i]),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: BxAdaptiveBody(child: stack)),
                      if (showCartBar) CartBar(onOpen: () => _selectTab(2)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: stack,
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Browsing tabs only: Cart already is the cart.
              if (showCartBar) CartBar(onOpen: () => _selectTab(2)),
              BxBottomNav(
                items: items,
                selectedIndex: _index,
                onSelected: _selectTab,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CartIcon extends StatelessWidget {
  final int count;
  final bool filled;

  const _CartIcon({required this.count, required this.filled});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(filled ? Icons.shopping_bag : Icons.shopping_bag_outlined),
        if (count > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Semantics(
              label: '$count items in cart',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                    color: c.danger, borderRadius: DsRadius.pillAll),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: DsWeight.black,
                    color: c.inkInverse,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
