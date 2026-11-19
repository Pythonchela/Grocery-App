import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/product_filters.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../widgets/cart_bar.dart';
import '../widgets/category_shortcuts.dart';
import '../widgets/product_card.dart';
import '../widgets/product_filter_sheet.dart';
import '../widgets/product_grid.dart';
import 'product_detail_screen.dart';

/// Sort modes the API accepts. Same five the web category page offers, so a
/// shopper switching devices sees the same ordering options.
const _sorts = [
  BxTab('relevance', 'Relevant'),
  BxTab('price_asc', 'Price ↑'),
  BxTab('price_desc', 'Price ↓'),
  BxTab('rating', 'Top rated'),
  BxTab('newest', 'Newest'),
];

class CategoryScreen extends StatefulWidget {
  final Category category;

  /// The other categories, when the caller already has them (with their
  /// pictures), so the strip is there on the first frame instead of popping in.
  final List<Category> siblings;

  const CategoryScreen(
      {super.key, required this.category, this.siblings = const []});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<Product> _products = [];
  bool _loading = true;
  String? _error;
  String _sort = 'relevance';
  int _requestId = 0;
  ProductFilters _filters = ProductFilters.none;

  /// Brands and the dearest price seen so far; they keep the filter sheet useful
  /// after a narrow filter has shrunk the visible list.
  final Set<String> _brands = {};
  double _priceCeiling = 0;

  /// The category being shown. Switching changes this in place - the strip
  /// stays exactly where it is and only the products below change - rather than
  /// replacing the whole page, which made the row flash and jump.
  late Category _category = widget.category;

  /// Every category, for the strip that switches between them.
  late List<Category> _siblings = widget.siblings;

  @override
  void initState() {
    super.initState();
    _load();
    if (_siblings.length < 2) _loadSiblings();
  }

  Future<void> _loadSiblings() async {
    try {
      final data = await ApiClient.request('/categories');
      if (!mounted) return;
      setState(() => _siblings = Category.withCoverPhotos(
          (data as List).map((c) => Category.fromJson(c)).toList(),
          _products));
    } catch (_) {
      // The strip is a convenience; the products below matter more.
    }
  }

  void _switchTo(Category category) {
    if (category.slug == _category.slug) return;
    setState(() {
      _category = category;
      // Filters, brands and prices belong to the category they were set in.
      _filters = ProductFilters.none;
      _brands.clear();
      _priceCeiling = 0;
      _products = [];
    });
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiClient.request('/products',
          query: _filters.toQuery({
            'category': _category.slug,
            'sort': _sort,
            'per_page': '40',
          }));
      if (!mounted || requestId != _requestId) return;
      final products = (data as List).map((p) => Product.fromJson(p)).toList();
      setState(() {
        _products = products;
        for (final p in products) {
          if (p.brand.isNotEmpty) _brands.add(p.brand);
          if (p.price > _priceCeiling) _priceCeiling = p.price;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openFilters() async {
    final result = await showProductFilterSheet(
      context,
      current: _filters,
      priceCeiling: _priceCeiling,
      brands: _brands.toList()..sort(),
      groups: FilterGroup.parse(_category.filterConfig),
    );
    if (result == null || !mounted) return;
    setState(() => _filters = result);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      bottomNavigationBar: const CartBar(),
      appBar: AppBar(
        title: Text(_category.name),
        actions: [
          IconButton(
            tooltip: _filters.isActive
                ? 'Filters (${_filters.count} applied)'
                : 'Filters',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _filters.isActive,
              label: Text('${_filters.count}'),
              backgroundColor: c.accent,
              textColor: c.onAccent,
              child: const Icon(Icons.tune),
            ),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_siblings.length > 1)
            _CategoryRail(
              categories: Category.withCoverPhotos(_siblings, _products),
              selectedSlug: _category.slug,
              onSelected: _switchTo,
            ),
          Expanded(
            child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s3),
            child: BxTabs(
              tabs: _sorts,
              value: _sort,
              onChanged: (v) {
                setState(() => _sort = v);
                _load();
              },
            ),
          ),
          Divider(height: 1, color: c.line),
          if (_filters.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DsSpace.s4, DsSpace.s2, DsSpace.s2, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_products.length} result${_products.length == 1 ? '' : 's'} with ${_filters.count} '
                      'filter${_filters.count == 1 ? '' : 's'} applied',
                      style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                    ),
                  ),
                  BxButton(
                    label: 'Clear',
                    variant: BxButtonVariant.link,
                    size: BxButtonSize.sm,
                    onPressed: () {
                      setState(() => _filters = ProductFilters.none);
                      _load();
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.all(DsSpace.s4),
                    mainAxisSpacing: DsSpace.s3,
                    crossAxisSpacing: DsSpace.s3,
                    childAspectRatio: 0.58,
                    children: List.generate(
                      6,
                      (_) => const BxSkeleton(
                          height: double.infinity, radius: DsRadius.cardAll),
                    ),
                  )
                : _error != null
                    ? BxEmptyState(
                        icon: Icons.wifi_off_outlined,
                        title: 'Could not load this category',
                        description: _error,
                        action: BxButton(label: 'Try again', onPressed: _load),
                      )
                    : _products.isEmpty
                        ? BxEmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: _filters.isActive
                                ? 'No matches'
                                : 'Nothing here yet',
                            description: _filters.isActive
                                ? 'Nothing fits those filters. Try loosening them.'
                                : 'This category has no products right now.',
                            action: _filters.isActive
                                ? BxButton(
                                    label: 'Clear filters',
                                    onPressed: () {
                                      setState(
                                          () => _filters = ProductFilters.none);
                                      _load();
                                    })
                                : null,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: c.accent,
                            child: GridView.builder(
                              padding: const EdgeInsets.all(DsSpace.s4),
                              gridDelegate: productGridDelegate(context, reserved: _siblings.length > 1 ? _CategoryRail.width : 0),
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
                          ),
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }
}

/// The aisles down the left edge: tap one to switch category without leaving the page.
class _CategoryRail extends StatelessWidget {
  static const width = 84.0;

  final List<Category> categories;
  final String selectedSlug;
  final ValueChanged<Category> onSelected;

  const _CategoryRail({required this.categories, required this.selectedSlug, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      width: width,
      decoration: BoxDecoration(color: c.surface, border: Border(right: BorderSide(color: c.line))),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final category = categories[i];
          final on = category.slug == selectedSlug;
          return Semantics(
            button: true,
            selected: on,
            label: category.name,
            child: InkWell(
              key: ValueKey('strip-${category.slug}'),
              onTap: () => onSelected(category),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: DsSpace.s3, horizontal: DsSpace.s1),
                decoration: BoxDecoration(
                  color: on ? c.accentSoft : null,
                  border: Border(left: BorderSide(color: on ? c.accent : Colors.transparent, width: 4)),
                ),
                child: Column(
                  children: [
                    CategoryThumb(category: category, size: 48),
                    const SizedBox(height: DsSpace.s1),
                    Text(category.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: DsText.x2xs,
                            height: 1.2,
                            fontWeight: on ? DsWeight.black : DsWeight.semibold,
                            color: on ? c.accent : c.inkMuted)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
