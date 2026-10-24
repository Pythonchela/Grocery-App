import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/tokens.g.dart';
import '../widgets/product_card.dart';
import '../widgets/product_grid.dart';
import 'product_detail_screen.dart';

/// Read-only view of someone else's shared wishlist.
class SharedWishlistScreen extends StatefulWidget {
  final String token;
  const SharedWishlistScreen({super.key, required this.token});

  @override
  State<SharedWishlistScreen> createState() => _SharedWishlistScreenState();
}

class _SharedWishlistScreenState extends State<SharedWishlistScreen> {
  List<Product> _products = [];
  String _owner = '';
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
      final data = await ApiClient.request('/wishlists/shared/${widget.token}')
          as Map<String, dynamic>;
      final products = <Product>[];
      for (final item in (data['items'] as List? ?? [])) {
        final product = item['product'];
        if (product is Map<String, dynamic>) {
          products.add(Product.fromJson(product));
        }
      }
      final user = data['user'];
      if (!mounted) return;
      setState(() {
        _products = products;
        _owner = user is Map ? '${user['name']}' : '';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_owner.isEmpty ? 'Shared wishlist' : "$_owner's wishlist")),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: BxSkeleton(height: 200, radius: DsRadius.cardAll),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.link_off,
                  title: 'Could not open this wishlist',
                  description: _error,
                  action: BxButton(label: 'Try again', onPressed: _load),
                )
              : _products.isEmpty
                  ? const BxEmptyState(
                      icon: Icons.favorite_border,
                      title: 'This wishlist is empty',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(DsSpace.s4),
                      gridDelegate: productGridDelegate(context),
                      itemCount: _products.length,
                      itemBuilder: (context, i) => ProductCardTile(
                        product: _products[i],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProductDetailScreen(
                                productId: _products[i].id),
                          ),
                        ),
                      ),
                    ),
    );
  }
}
