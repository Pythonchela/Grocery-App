import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/shop.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import '../widgets/cart_bar.dart';
import '../widgets/shop_card.dart';
import 'shop_screen.dart';

/// The pincode of the shopper's default address, so shops that cannot deliver
/// there are left out of the list. Null when signed out or with no address.
/// Remembered for the session: it is read once, not on every list.
abstract final class ShopArea {
  static String? _pincode;
  static bool _read = false;

  static void forget() {
    _pincode = null;
    _read = false;
  }

  static Future<String?> pincode() async {
    if (_read) return _pincode;
    final token = AppState.instance.token;
    if (token == null) return null;

    try {
      final list = await ApiClient.request('/addresses', token: token) as List;
      final all = list.whereType<Map<String, dynamic>>().map(Address.fromJson).toList();
      _pincode = (all.where((a) => a.isDefault).firstOrNull ?? all.firstOrNull)?.pincode;
      _read = true;
    } catch (_) {
      // Unfiltered is better than empty.
    }
    return _pincode;
  }
}

/// The shops, as a list of cards. Handles its own loading, failure and
/// "nothing matches" states so a screen can drop it in anywhere.
class ShopsFeed extends StatefulWidget {
  final String search;
  final bool openOnly;

  const ShopsFeed({super.key, this.search = '', this.openOnly = false});

  @override
  State<ShopsFeed> createState() => _ShopsFeedState();
}

class _ShopsFeedState extends State<ShopsFeed> {
  List<Shop>? _shops;
  List<ShopCategory> _categories = const [];

  /// The category chosen as a filter; empty for all.
  String _category = '';
  String? _pincode;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ShopsFeed old) {
    super.didUpdateWidget(old);
    if (old.search != widget.search || old.openOnly != widget.openOnly) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final pincode = await ShopArea.pincode();
      final listing = await ShopApi.browse(
        search: widget.search,
        pincode: pincode,
        category: _category,
        openOnly: widget.openOnly,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _pincode = pincode;
        _shops = listing.shops;
        // Keep the chips once seen: choosing one must not make the rest vanish.
        if (listing.categories.isNotEmpty) _categories = listing.categories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _open(Shop shop) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ShopScreen(shop: shop)));

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    if (_loading && _shops == null) {
      return const Padding(
        padding: EdgeInsets.all(DsSpace.s4),
        child: Column(
          children: [
            BxSkeleton(height: 170, radius: DsRadius.cardAll),
            SizedBox(height: DsSpace.s3),
            BxSkeleton(height: 170, radius: DsRadius.cardAll),
          ],
        ),
      );
    }

    if (_error != null && _shops == null) {
      return Padding(
        padding: const EdgeInsets.all(DsSpace.s4),
        child: Column(
          children: [
            BxAlert(_error!, title: 'Could not load shops', tone: BxTone.danger),
            const SizedBox(height: DsSpace.s3),
            BxButton(label: 'Try again', size: BxButtonSize.sm, onPressed: _load),
          ],
        ),
      );
    }

    final shops = _shops ?? const [];

    final chips = _categories.length > 1
        ? SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
              children: [
                for (final cat in [const ShopCategory('', 'All', 0), ..._categories])
                  Padding(
                    padding: const EdgeInsets.only(right: DsSpace.s2),
                    child: ChoiceChip(
                      label: Text(cat.name),
                      selected: _category == cat.slug,
                      onSelected: (_) {
                        setState(() => _category = cat.slug);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    if (shops.isEmpty) {
      return Column(
        children: [
          chips,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s8),
            child: BxEmptyState(
              icon: Icons.storefront_outlined,
              title: 'No shops found',
              description: widget.search.isNotEmpty || widget.openOnly || _category.isNotEmpty
                  ? 'Try a different search or filter, or show shops that are closed too.'
                  : (_pincode == null
                      ? 'Shops will appear here as they join.'
                      : 'No shop delivers to $_pincode yet.'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chips,
        if (_pincode != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, 0, DsSpace.s4, DsSpace.s1),
            child: Text('Shops delivering to $_pincode',
                style: TextStyle(fontSize: DsText.sm, color: c.inkSubtle)),
          ),
        for (final shop in shops) ShopCard(shop: shop, onTap: () => _open(shop)),
      ],
    );
  }
}

/// All the shops, with a search box and an "Open now" filter.
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _openOnly = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shops')),
      bottomNavigationBar: const CartBar(),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s2, DsSpace.s4, DsSpace.s2),
            child: TextField(
              controller: _search,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search shops',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Open now'),
                selected: _openOnly,
                onSelected: (v) => setState(() => _openOnly = v),
              ),
            ),
          ),
          const SizedBox(height: DsSpace.s2),
          ShopsFeed(search: _query, openOnly: _openOnly),
          const SizedBox(height: DsSpace.s6),
        ],
      ),
    );
  }
}

/// A row of shops with "See all", for the home screen of a store that sells
/// from the owner's shop and vendors alike.
class ShopsRail extends StatefulWidget {
  const ShopsRail({super.key});

  @override
  State<ShopsRail> createState() => _ShopsRailState();
}

class _ShopsRailState extends State<ShopsRail> {
  List<Shop> _shops = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pincode = await ShopArea.pincode();
      final shops = await ShopApi.list(pincode: pincode);
      if (mounted) setState(() => _shops = shops.take(10).toList());
    } catch (_) {
      // A rail that fails to load is simply absent.
    }
  }

  @override
  Widget build(BuildContext context) {
    // One shop is not worth a rail; the products below already say whose they are.
    if (_shops.length < 2) return const SizedBox.shrink();
    final c = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s2, DsSpace.s2),
          child: Row(
            children: [
              Expanded(
                child: Text('Shops',
                    style: TextStyle(
                        fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ShopsScreen())),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
            scrollDirection: Axis.horizontal,
            itemCount: _shops.length,
            separatorBuilder: (_, __) => const SizedBox(width: DsSpace.s3),
            itemBuilder: (_, i) => ShopRailCard(
              shop: _shops[i],
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ShopScreen(shop: _shops[i]))),
            ),
          ),
        ),
      ],
    );
  }
}
