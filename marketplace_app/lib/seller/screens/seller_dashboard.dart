import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/theme.dart';
import '../../data/api_client.dart';
import '../../support/support_api.dart';
import '../../support/support_screens.dart';
import '../document_picker.dart';
import '../seller_api.dart';
import '../seller_host.dart';
import '../seller_models.dart';
import 'bulk_import_screen.dart';
import 'earnings_tab.dart';
import 'orders_tab.dart';
import 'operations_tab.dart';
import 'overview_tab.dart';
import 'products_tab.dart';
import 'shop_profile_screen.dart';

/// The active seller's home: overview, orders, products and earnings.
class SellerDashboard extends StatefulWidget {
  final SellerApi api;
  final SellerHost host;
  final String shopName;
  final DocumentPicker picker;

  const SellerDashboard({
    super.key,
    required this.api,
    required this.host,
    required this.shopName,
    required this.picker,
  });

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> with WidgetsBindingObserver {
  int _index = 0;

  // Bumped whenever an item is packed or shipped, so the overview's counts follow.
  final _changes = ValueNotifier<int>(0);

  // Asks the orders tab to show a stage (the "new orders" banner).
  final _stageRequest = ValueNotifier<String?>(null);

  // Asks the More tab to show a section (Returns, Offers... from the menu).
  final _sectionRequest = ValueNotifier<String?>(null);

  // Bumped after a bulk import so the products list is rebuilt with the new items.
  int _productsEpoch = 0;

  // Order desk: how many orders wait for an answer, polled while the app is open.
  DeskCounts _desk = const DeskCounts();
  SellerProfile? _profile;
  Timer? _poll;
  Timer? _ring;
  bool _foreground = true;

  static const _pollEvery = Duration(seconds: 15);
  static const _ringEvery = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.host.onDeskVisible?.call(true);
    _refreshDesk();
    _loadProfile();
    _poll = Timer.periodic(_pollEvery, (_) => _refreshDesk());
    // An unanswered order keeps nagging, like a till, until it is dealt with.
    _ring = Timer.periodic(_ringEvery, (_) {
      if (_foreground && _desk.newOrders > 0) _alertSound();
    });
    _changes.addListener(_refreshDesk);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refreshDesk();
  }

  @override
  void dispose() {
    widget.host.onDeskVisible?.call(false);
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _ring?.cancel();
    _changes.removeListener(_refreshDesk);
    _changes.dispose();
    _stageRequest.dispose();
    _sectionRequest.dispose();
    super.dispose();
  }

  void _alertSound() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }

  Future<void> _refreshDesk() async {
    try {
      final next = await widget.api.deskCounts();
      if (!mounted) return;
      final more = next.newOrders > _desk.newOrders;
      setState(() => _desk = next);
      if (more) {
        _alertSound();
        widget.host.onAlert?.call(
          'New order',
          '${next.newOrders} ${next.newOrders == 1 ? 'order is' : 'orders are'} waiting for your answer.',
        );
      }
    } catch (_) {
      // A missed poll is fine; the next one catches up.
    }
  }

  /// The shop's own state (open, paused), shown beside its name.
  Future<void> _loadProfile() async {
    try {
      final profile = await widget.api.me();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // The chip simply stays hidden until the next try.
    }
  }

  Future<void> _pauseShop(int minutes) async {
    try {
      await widget.api.pauseShop(minutes);
      await _loadProfile();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach the server. Try again.')));
    }
  }

  Future<void> _openShopStatus() async {
    final shop = _profile?.shop;
    if (shop == null) return;
    final paused = !shop.acceptingOrders || (shop.pausedUntil?.isAfter(DateTime.now()) ?? false);
    final now = DateTime.now();
    final untilTomorrow = DateTime(now.year, now.month, now.day + 1, 9).difference(now).inMinutes.clamp(1, 10080);

    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(paused ? 'Orders are paused' : 'Taking orders'),
            subtitle: Text(paused ? 'Shoppers can look but not order.' : (shop.isOpen ? 'Open now.' : (shop.closedText ?? 'Closed by your opening hours.'))),
          ),
          if (paused)
            ListTile(leading: const Icon(Icons.play_arrow), title: const Text('Resume taking orders'), onTap: () => Navigator.pop(sheet, 0))
          else ...[
            ListTile(leading: const Icon(Icons.pause), title: const Text('Pause for 30 minutes'), onTap: () => Navigator.pop(sheet, 30)),
            ListTile(leading: const Icon(Icons.pause), title: const Text('Pause for 1 hour'), onTap: () => Navigator.pop(sheet, 60)),
            ListTile(leading: const Icon(Icons.bedtime_outlined), title: const Text('Pause until tomorrow 9 am'), onTap: () => Navigator.pop(sheet, untilTomorrow)),
          ],
        ]),
      ),
    );
    if (minutes != null && mounted) await _pauseShop(minutes);
  }

  Widget? _statusChip() {
    final shop = _profile?.shop;
    if (shop == null) return null;
    final c = context.ds;
    final paused = !shop.acceptingOrders || (shop.pausedUntil?.isAfter(DateTime.now()) ?? false);
    final open = !paused && shop.isOpen;
    final color = open ? c.success : c.warning;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: ActionChip(
        key: const Key('shop-status'),
        avatar: Icon(Icons.circle, size: 10, color: color),
        label: Text(paused ? 'Paused' : (open ? 'Open' : 'Closed')),
        onPressed: _openShopStatus,
      ),
    );
  }

  void _showNewOrders() {
    _open(1);
    _stageRequest.value = null;
    _stageRequest.value = 'new';
  }

  // Tabs are built the first time they are opened, not all at once: each one
  // makes its own requests, and the seller may only ever look at one.
  final Set<int> _opened = {0};

  void _open(int i) => setState(() {
        _index = i;
        _opened.add(i);
      });


  // ── Menu ───────────────────────────────────────────────────────────────────

  /// Closes the menu, then does [action]: a menu that stays open over the screen
  /// it just opened is in the way.
  void _fromMenu(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  void _showSection(String section) {
    _open(4);
    _sectionRequest.value = null;
    _sectionRequest.value = section;
  }

  Future<void> _openShopPage() async {
    final shop = _profile?.shop;
    if (shop == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ShopProfileScreen(api: widget.api, picker: widget.picker, shop: shop),
    ));
    if (saved == true && mounted) {
      _changes.value++;
      _loadProfile();
    }
  }

  Future<void> _openBulkImport() async {
    final count = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => BulkImportScreen(api: widget.api),
    ));
    if (count != null && mounted) {
      // Rebuilds the products list so the new items are in it.
      setState(() => _productsEpoch++);
      _open(2);
      _changes.value++;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count products imported.')));
    }
  }

  void _openHelp() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SupportScreen(api: HttpSupportApi(widget.host.token), seller: true),
      ));

  Widget _menuHeader(BuildContext context) {
    final c = context.ds;
    final shop = _profile?.shop;
    final paused = shop != null && (!shop.acceptingOrders || (shop.pausedUntil?.isAfter(DateTime.now()) ?? false));
    final open = shop != null && !paused && shop.isOpen;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 16, 16, 16),
      color: c.surfaceMuted,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.host.marketplaceName.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.inkMuted)),
        const SizedBox(height: 4),
        Text(widget.shopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.ink)),
        if (shop != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.circle, size: 10, color: open ? c.success : c.warning),
            const SizedBox(width: 6),
            Text(paused ? 'Paused' : (open ? 'Open' : 'Closed'), style: TextStyle(fontWeight: FontWeight.w700, color: c.inkMuted)),
          ]),
        ],
      ]),
    );
  }

  Widget _menuTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: context.ds.inkSubtle)),
      );

  Widget _menuItem(String key, IconData icon, String label, VoidCallback onTap, {bool selected = false, int badge = 0}) => ListTile(
        key: Key('menu-$key'),
        dense: true,
        selected: selected,
        selectedTileColor: context.ds.accentSoft,
        selectedColor: context.ds.accent,
        leading: Icon(icon),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: badge > 0 ? Badge(label: Text('$badge')) : null,
        onTap: () => _fromMenu(onTap),
      );

  /// The same groups as the website's sidebar, so the two read alike.
  Widget _menu(BuildContext context) {
    return Drawer(
      key: const Key('seller-menu'),
      child: Column(children: [
        _menuHeader(context),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            _menuItem('today', Icons.dashboard_outlined, 'Today', () => _open(0), selected: _index == 0),
            _menuItem('insights', Icons.insights_outlined, 'Insights', () => _showSection('Insights')),
            _menuTitle('Orders'),
            _menuItem('new-orders', Icons.notifications_active_outlined, 'New orders', _showNewOrders, badge: _desk.newOrders),
            _menuItem('orders', Icons.local_shipping_outlined, 'Orders', () => _open(1), selected: _index == 1),
            _menuItem('returns', Icons.assignment_return_outlined, 'Returns', () => _showSection('Returns')),
            _menuTitle('Catalogue'),
            _menuItem('products', Icons.inventory_2_outlined, 'Products', () => _open(2), selected: _index == 2),
            _menuItem('bulk-import', Icons.upload_file_outlined, 'Bulk import', _openBulkImport),
            _menuItem('offers', Icons.sell_outlined, 'Offers', () => _showSection('Offers')),
            _menuTitle('Customers'),
            _menuItem('reviews', Icons.rate_review_outlined, 'Reviews & Q&A', () => _showSection('Reviews & Q&A')),
            _menuTitle('Money'),
            _menuItem('earnings', Icons.account_balance_wallet_outlined, 'Earnings', () => _open(3), selected: _index == 3),
            _menuTitle('Shop'),
            _menuItem('my-shop', Icons.storefront_outlined, 'My shop', _openShopPage),
            _menuItem('help', Icons.support_agent_outlined, 'Help & support', _openHelp),
          ]),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Column(children: [
            if (widget.host.onSwitchToShopping != null)
              _menuItem('shop-as-customer', Icons.shopping_bag_outlined, 'Shop as a customer', widget.host.onSwitchToShopping!),
            _menuItem('sign-out', Icons.logout, 'Sign out', widget.host.onSignOut),
          ]),
        ),
      ]),
    );
  }

  Widget _tab(int i) {
    if (!_opened.contains(i)) return const SizedBox.shrink();
    return switch (i) {
      0 => OverviewTab(api: widget.api, picker: widget.picker, onOpenTab: _open, changes: _changes),
      1 => OrdersTab(api: widget.api, onChanged: () => _changes.value++, stageRequest: _stageRequest),
      2 => ProductsTab(key: ValueKey(_productsEpoch), api: widget.api, picker: widget.picker, onChanged: () => _changes.value++),
      3 => EarningsTab(api: widget.api),
      _ => OperationsTab(host: widget.host, sectionRequest: _sectionRequest),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _menu(context),
      appBar: AppBar(
        title: Text(widget.shopName, overflow: TextOverflow.ellipsis),
        actions: [if (_statusChip() case final chip?) chip],
      ),
      // IndexedStack keeps each tab's scroll position and loaded data when the
      // seller flips between them.
      body: Column(children: [
        if (_desk.newOrders > 0 && !(_index == 1 && _stageRequest.value == 'new'))
          Material(
            color: context.ds.warningSoft,
            child: InkWell(
              key: const Key('new-orders-banner'),
              onTap: _showNewOrders,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Icon(Icons.notifications_active, color: context.ds.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_desk.newOrders} new ${_desk.newOrders == 1 ? 'order' : 'orders'} waiting for your answer',
                      style: TextStyle(fontWeight: FontWeight.w800, color: context.ds.ink),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: context.ds.inkMuted),
                ]),
              ),
            ),
          ),
        // IndexedStack keeps each tab's scroll position and loaded data when
        // the seller flips between them.
        Expanded(child: IndexedStack(index: _index, children: [for (var i = 0; i < 5; i++) _tab(i)])),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _open,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
          NavigationDestination(
            icon: Badge(isLabelVisible: _desk.newOrders > 0, label: Text('${_desk.newOrders}'), child: const Icon(Icons.local_shipping_outlined)),
            selectedIcon: Badge(isLabelVisible: _desk.newOrders > 0, label: Text('${_desk.newOrders}'), child: const Icon(Icons.local_shipping)),
            label: 'Orders',
          ),
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Products'),
          const NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Earnings'),
          const NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more), label: 'More'),
        ],
      ),
    );
  }
}
