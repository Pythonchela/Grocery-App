import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/shop_switch.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'product_detail_screen.dart';
import 'shared_wishlist_screen.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  List<_WishlistEntry> _items = [];
  String? _listId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data =
          await ApiClient.request('/wishlists', token: AppState.instance.token)
              as List;

      // The API returns lists, each holding items. The mobile app deliberately
      // flattens them: multiple named wishlists is a desktop-scale feature and
      // a phone screen is better served by one "saved" view.
      final entries = <_WishlistEntry>[];
      _listId = data.isEmpty ? null : data.first['id']?.toString();
      for (final list in data) {
        for (final item in (list['items'] as List? ?? [])) {
          final product = item['product'];
          if (product == null) continue;
          entries.add(_WishlistEntry(
            itemId: item['id'].toString(),
            product: Product.fromJson(product as Map<String, dynamic>),
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _items = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _remove(_WishlistEntry entry) async {
    // Optimistic: the row disappears immediately and comes back if the call
    // fails. A wishlist removal that waits on a round trip feels broken.
    setState(() => _items.remove(entry));

    try {
      await ApiClient.request(
        '/wishlist-items/${entry.itemId}',
        method: 'DELETE',
        token: AppState.instance.token,
      );
      AppState.instance.loadWishlist();
    } catch (e) {
      if (!mounted) return;
      setState(() => _items.add(entry));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: $e')),
      );
    }
  }

  Future<void> _share() async {
    final id = _listId;
    if (id == null || _items.isEmpty) return;
    try {
      final data = await ApiClient.request('/wishlists/$id/share',
          method: 'POST', token: AppState.instance.token) as Map<String, dynamic>;
      final link = '${ApiClient.webBase}/wishlist/${data['share_token']}';
      await SharePlus.instance
          .share(ShareParams(text: 'Take a look at my wishlist: $link'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not share: $e')));
    }
  }

  Future<void> _openShared() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open a shared wishlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Paste the link you received'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Open')),
        ],
      ),
    );
    controller.dispose();
    final token = value?.trim().split('/').where((s) => s.isNotEmpty).lastOrNull;
    if (token == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SharedWishlistScreen(token: token)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wishlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Open a shared wishlist',
            onPressed: _openShared,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share my wishlist',
            onPressed: _items.isEmpty ? null : _share,
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: Column(
                children: [
                  BxSkeleton(height: 96, radius: DsRadius.cardAll),
                  SizedBox(height: DsSpace.s3),
                  BxSkeleton(height: 96, radius: DsRadius.cardAll),
                ],
              ),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Could not load your wishlist',
                  description: _error,
                  action: BxButton(label: 'Retry', onPressed: _load),
                )
              : _items.isEmpty
                  ? const BxEmptyState(
                      icon: Icons.favorite_border,
                      title: 'Nothing saved yet',
                      description:
                          'Tap the heart on a product to keep it here.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: c.accent,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(DsSpace.s4),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: DsSpace.s3),
                        itemBuilder: (context, i) {
                          final entry = _items[i];
                          final p = entry.product;

                          return BxCard(
                            padding: const EdgeInsets.all(DsSpace.s3),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProductDetailScreen(productId: p.id),
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: DsRadius.controlAll,
                                  child: Image.network(
                                    p.image,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 72,
                                      height: 72,
                                      color: c.surfaceSunken,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: DsSpace.s3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: DsText.base,
                                          fontWeight: DsWeight.bold,
                                          color: c.ink,
                                        ),
                                      ),
                                      const SizedBox(height: DsSpace.s1),
                                      Row(
                                        children: [
                                          Text(
                                            formatMoney(p.price),
                                            style: TextStyle(
                                              fontSize: DsText.base,
                                              fontWeight: DsWeight.black,
                                              color: c.ink,
                                            ),
                                          ),
                                          const SizedBox(width: DsSpace.s2),
                                          if (!p.inStock)
                                            const BxBadge('Out of stock',
                                                tone: BxTone.warning),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18),
                                      tooltip: 'Remove from wishlist',
                                      color: c.inkSubtle,
                                      onPressed: () => _remove(entry),
                                    ),
                                    BxButton(
                                      label: 'Add',
                                      size: BxButtonSize.sm,
                                      onPressed: p.inStock
                                          ? () async {
                                              if (!await confirmShopSwitch(context, p)) return;
                                              if (!context.mounted) return;
                                              final added = AppState.instance
                                                  .addToCart(p);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(added
                                                        ? '${p.title} added to cart'
                                                        : 'Maximum available quantity reached')),
                                              );
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _WishlistEntry {
  final String itemId;
  final Product product;

  _WishlistEntry({required this.itemId, required this.product});
}
