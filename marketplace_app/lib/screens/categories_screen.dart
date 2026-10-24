import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../widgets/category_shortcuts.dart';
import '../widgets/home_sections.dart';
import '../widgets/product_rail.dart';
import 'category_screen.dart';
import 'product_detail_screen.dart';
import 'search_screen.dart';

/// Every category as a picture, with what is new underneath.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Category> _categories = [];
  List<Product> _newArrivals = [];
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
      final results = await Future.wait([
        ApiClient.request('/categories'),
        ApiClient.request('/products', query: {'sort': 'newest', 'per_page': '10'})
            .catchError((_) => <dynamic>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _newArrivals =
            (results[1] as List).map((p) => Product.fromJson(p)).toList();
        _categories = Category.withCoverPhotos(
          (results[0] as List).map((c) => Category.fromJson(c)).toList(),
          _newArrivals,
        );
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

  void _openCategory(Category category) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CategoryScreen(category: category, siblings: _categories)),
      );

  void _openProduct(Product p) => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => ProductDetailScreen(productId: p.id)),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: BxSkeleton(height: 200, radius: DsRadius.cardAll),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Could not load categories',
                  description: _error,
                  action: BxButton(label: 'Try again', onPressed: _load),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: c.accent,
                  child: ListView(
                    padding: const EdgeInsets.only(
                        top: DsSpace.s4, bottom: DsSpace.s10),
                    children: [
                      CategoryShortcuts(
                        categories: _categories,
                        onSelected: _openCategory,
                      ),
                      if (_newArrivals.isNotEmpty) ...[
                        const SectionTitle(
                          title: 'New arrivals',
                          subtitle: 'Fresh in this week',
                        ),
                        ProductRail(
                            products: _newArrivals, onTap: _openProduct),
                      ],
                    ],
                  ),
                ),
    );
  }
}
