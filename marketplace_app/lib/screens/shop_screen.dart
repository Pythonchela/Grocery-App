import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/shop.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../widgets/cart_bar.dart';
import '../widgets/product_list_row.dart';
import '../widgets/shop_card.dart';
import 'product_detail_screen.dart';

/// One shop's page: a banner, who they are, when they are open, what they ask
/// of an order, and their items grouped by category with an ADD on each.
///
/// Opened from the shops list, so [shop] is already known and the page paints
/// at once; the full details (about, hours) and the items load behind it.
class ShopScreen extends StatefulWidget {
  final Shop shop;

  const ShopScreen({super.key, required this.shop});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late Shop _shop = widget.shop;
  List<Product>? _products;
  String? _error;
  String _category = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);

    // The shop's own details and its items are independent; one failing must not
    // blank the other.
    try {
      final shop = await ShopApi.one(widget.shop.id);
      if (mounted) setState(() => _shop = shop);
    } catch (_) {}

    try {
      final data = await ApiClient.request('/products', query: {
        'seller': widget.shop.id,
        'per_page': '100',
      });
      final products = (data as List)
          .whereType<Map<String, dynamic>>()
          .map(Product.fromJson)
          .toList();
      if (mounted) setState(() => _products = products);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<String> get _categories => {
        for (final p in _products ?? const <Product>[])
          if ((p.categoryName ?? '').isNotEmpty) p.categoryName!,
      }.toList();

  List<Product> get _visible {
    final words = _search.text.trim().toLowerCase();
    return (_products ?? const <Product>[])
        .where((p) => _category.isEmpty || p.categoryName == _category)
        .where((p) => words.isEmpty || p.title.toLowerCase().contains(words))
        .toList();
  }

  void _openProduct(Product p) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: p.id)),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final shop = _shop;
    final visible = _visible;
    final categories = _categories;

    // Group what is shown by category, in the order the categories first appear.
    final groups = <String, List<Product>>{};
    for (final p in visible) {
      groups.putIfAbsent(p.categoryName ?? '', () => []).add(p);
    }

    return Scaffold(
      bottomNavigationBar: const CartBar(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 150,
            flexibleSpace: FlexibleSpaceBar(
              background: ShopPicture(shop: shop, dimmed: !shop.isOpen, showInitial: false),
            ),
            title: Text(shop.name),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(DsSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(shop.name,
                            style: TextStyle(
                                fontSize: DsText.xl,
                                fontWeight: DsWeight.black,
                                color: c.ink)),
                      ),
                      if (shop.rating > 0) RatingChip(rating: shop.rating),
                    ],
                  ),
                  if (shop.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(shop.subtitle,
                          style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
                    ),
                  const SizedBox(height: DsSpace.s2),
                  Wrap(
                    spacing: DsSpace.s2,
                    runSpacing: DsSpace.s2,
                    children: [
                      if (shop.prepMinutes != null && shop.prepMinutes! > 0)
                        _Fact(Icons.schedule, 'Ready in ~${shop.prepMinutes} mins'),
                      if (shop.minOrder > 0)
                        _Fact(Icons.shopping_basket_outlined, 'Min ${formatMoney(shop.minOrder)}'),
                      if (shop.reviewsCount > 0)
                        _Fact(Icons.reviews_outlined, '${shop.reviewsCount} ratings'),
                    ],
                  ),
                  if (!shop.isOpen) ...[
                    const SizedBox(height: DsSpace.s3),
                    BxAlert(
                      '${shop.closedText ?? 'Closed right now'}. You can look around; '
                      'ordering opens when the shop does.',
                      title: 'Closed',
                      tone: BxTone.warning,
                    ),
                  ],
                  if (shop.hoursLines.isNotEmpty || shop.about != null)
                    _Details(shop: shop),
                ],
              ),
            ),
          ),
          if (_products == null && _error == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(DsSpace.s4),
                child: BxSkeleton(height: 96, radius: DsRadius.cardAll),
              ),
            )
          else if (_error != null && _products == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(DsSpace.s4),
                child: Column(
                  children: [
                    BxAlert(_error!, title: 'Could not load items', tone: BxTone.danger),
                    const SizedBox(height: DsSpace.s3),
                    BxButton(label: 'Try again', size: BxButtonSize.sm, onPressed: _load),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search in ${shop.name}',
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
            if (categories.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
                    children: [
                      for (final name in ['', ...categories])
                        Padding(
                          padding: const EdgeInsets.only(right: DsSpace.s2),
                          child: ChoiceChip(
                            label: Text(name.isEmpty ? 'All' : name),
                            selected: _category == name,
                            onSelected: (_) => setState(() => _category = name),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (visible.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: DsSpace.s8),
                  child: BxEmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing here',
                    description: _products!.isEmpty
                        ? 'This shop has nothing on sale yet.'
                        : 'No item matches that.',
                  ),
                ),
              )
            else
              SliverList.list(children: [
                for (final entry in groups.entries) ...[
                  if (entry.key.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s1),
                      child: Text(entry.key,
                          style: TextStyle(
                              fontSize: DsText.lg,
                              fontWeight: DsWeight.black,
                              color: c.ink)),
                    ),
                  for (final p in entry.value) ...[
                    ProductListRow(
                      product: p,
                      canAdd: shop.isOpen,
                      onTap: () => _openProduct(p),
                    ),
                    Divider(height: 1, indent: DsSpace.s4, endIndent: DsSpace.s4, color: c.line),
                  ],
                ],
                const SizedBox(height: DsSpace.s6),
              ]),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Fact(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c.inkMuted),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: DsText.sm, color: c.ink)),
        ],
      ),
    );
  }
}

/// Timings and the shop's own words, folded away until asked for.
class _Details extends StatelessWidget {
  final Shop shop;

  const _Details({required this.shop});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shop.hoursLines.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Timings',
                  style: TextStyle(
                      fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink)),
              children: [
                for (final (day, hours) in shop.hoursLines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(day,
                                style: TextStyle(fontSize: DsText.sm, color: c.inkMuted))),
                        Text(hours,
                            style: TextStyle(
                                fontSize: DsText.sm,
                                fontWeight: DsWeight.semibold,
                                color: hours == 'Closed' ? c.inkSubtle : c.ink)),
                      ],
                    ),
                  ),
              ],
            ),
          if (shop.about != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('About',
                  style: TextStyle(
                      fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink)),
              expandedAlignment: Alignment.centerLeft,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s2),
                  child: Text(shop.about!,
                      style: TextStyle(
                          fontSize: DsText.base, height: DsText.baseHeight, color: c.inkMuted)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
