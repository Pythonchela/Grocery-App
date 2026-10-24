import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/storefront.dart';
import '../design/brand.g.dart';
import '../design/brand_mark.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import '../widgets/product_list_row.dart';
import '../widgets/product_rail.dart';
import '../widgets/category_shortcuts.dart';
import '../widgets/home_sections.dart';
import 'category_screen.dart';
import 'product_detail_screen.dart';
import 'notifications_screen.dart';
import 'reels_screen.dart';
import 'search_screen.dart';
import 'shops_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Category> _categories = [];
  List<Product> _trending = [];
  List<Product> _featured = [];
  List<Product> _forYou = [];
  List<HomeSection> _sections = [];
  bool _hasReels = false;
  bool _loading = true;
  String? _error;

  bool _wasSignedIn = AppState.instance.isSignedIn;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onAuthChanged);
    _load();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final signedIn = AppState.instance.isSignedIn;
    if (signedIn == _wasSignedIn) return;
    _wasSignedIn = signedIn;
    if (signedIn) {
      _loadForYou();
    } else if (mounted) {
      setState(() => _forYou = []);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Fired together rather than awaited in sequence: three round trips at
      // 200ms each is a visibly slower first paint than one.
      final results = await Future.wait([
        ApiClient.request('/categories'),
        ApiClient.request('/recommendations/trending')
            .catchError((_) => <dynamic>[]),
        ApiClient.request('/products', query: {'per_page': '30'}),
        // The admin's Storefront Builder layout. Empty (or failing) means the
        // built-in layout below, so the home page is never blank.
        ApiClient.request('/storefront/sections')
            .catchError((_) => <dynamic>[]),
        ApiClient.request('/reels', query: {'per_page': '1'}, envelope: true)
            .catchError((_) => <String, dynamic>{}),
      ]);

      if (!mounted) return;
      setState(() {
        _trending =
            (results[1] as List).map((p) => Product.fromJson(p)).toList();
        _featured =
            (results[2] as List).map((p) => Product.fromJson(p)).toList();
        _categories = Category.withCoverPhotos(
          (results[0] as List).map((c) => Category.fromJson(c)).toList(),
          [..._featured, ..._trending],
        );
        _sections = HomeSection.parseList(results[3]);
        final reelsMeta = (results[4] as Map)['meta'];
        _hasReels = reelsMeta is Map && ((reelsMeta['total'] as num?) ?? 0) > 0;
        _loading = false;
      });
      _loadForYou();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Personalised picks need a signed-in shopper; for everyone else the
  /// trending rail already covers the slot.
  Future<void> _loadForYou() async {
    if (!AppState.instance.isSignedIn) return;
    try {
      final data = await ApiClient.request('/recommendations/personalized',
          token: AppState.instance.token) as List;
      if (!mounted) return;
      setState(() => _forYou = data
          .map((p) => Product.fromJson(p as Map<String, dynamic>))
          .toList());
    } catch (_) {}
  }

  void _openProduct(Product p) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: p.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    // The store's kind can arrive after the first paint (and changes when an
    // admin switches it), so the body listens to it.
    return Scaffold(
      body: AnimatedBuilder(
        animation: AppState.instance,
        builder: (context, _) => RefreshIndicator(
          onRefresh: _load,
          color: c.accent,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                titleSpacing: DsSpace.s4,
                title: Row(
                  children: [
                    BrandMark(logoUrl: AppState.instance.logoUrl),
                    const SizedBox(width: DsSpace.s2),
                    Flexible(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(text: DsBrand.nameDisplay),
                                  TextSpan(
                                      text: DsBrand.nameAccent,
                                      style: TextStyle(color: c.accent)),
                                ],
                              ),
                              style: TextStyle(
                                fontFamily: DsFont.display,
                                fontSize: DsText.lg,
                                fontWeight: DsWeight.black,
                                color: c.ink,
                              ),
                            ))),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    ),
                  ),
                  // Order and delivery news live behind the bell; the dot says
                  // there is something unread.
                  AnimatedBuilder(
                    animation: AppState.instance,
                    builder: (context, _) => IconButton(
                      tooltip: AppState.instance.unreadNotifications > 0
                          ? 'Notifications (${AppState.instance.unreadNotifications} unread)'
                          : 'Notifications',
                      icon: Badge(
                        isLabelVisible:
                            AppState.instance.unreadNotifications > 0,
                        smallSize: 8,
                        backgroundColor: c.danger,
                        child: const Icon(Icons.notifications_none),
                      ),
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()));
                        AppState.instance.refreshUnread();
                      },
                    ),
                  ),
                  const SizedBox(width: DsSpace.s2),
                ],
              ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(DsSpace.s4),
                    child: Column(
                      children: [
                        BxAlert(_error!,
                            title: 'Could not reach the store',
                            tone: BxTone.danger),
                        const SizedBox(height: DsSpace.s3),
                        BxButton(
                            label: 'Try again',
                            onPressed: _load,
                            size: BxButtonSize.sm),
                      ],
                    ),
                  ),
                ),
              if (AppState.instance.storeConfig.shopsFirst) ...[
                // A vendors-only store: shoppers pick a shop first, then its items.
                const _ShopsHeading(),
                const SliverToBoxAdapter(child: ShopsFeed()),
                const SliverToBoxAdapter(child: SizedBox(height: DsSpace.s10)),
              ] else ...[
                if (AppState.instance.storeConfig.showsShops &&
                    AppState.instance.storeConfig.homeShowsShops)
                  const SliverToBoxAdapter(child: ShopsRail()),
                if (_sections.isNotEmpty && !_loading)
                  ..._sectionSlivers()
                else ...[
                  SliverToBoxAdapter(
                      child: _Hero(
                          imageUrl:
                              _featured.isEmpty ? null : _featured.first.image,
                          onShopNow:
                              _categories.isEmpty ? null : _openCategoryList)),
                  if (_loading)
                    const SliverToBoxAdapter(child: _HomeSkeleton())
                  else ...[
                    const SliverToBoxAdapter(
                        child: SizedBox(height: DsSpace.s4)),
                    SliverToBoxAdapter(
                        child: CategoryShortcuts(
                            scrollable: true,
                            categories: _categories,
                            onSelected: (category) => Navigator.of(context)
                                .push(MaterialPageRoute(
                                    builder: (_) => CategoryScreen(
                                        category: category,
                                        siblings: _categories))))),
                    if (_trending.isNotEmpty) ...[
                      const _SectionHeader(
                        title: 'Trending now',
                      ),
                      SliverToBoxAdapter(
                        child: ProductRail(
                            products: _trending, onTap: _openProduct),
                      ),
                    ],
                    if (_hasReels)
                      SliverToBoxAdapter(
                        child: ReelsPromo(
                          section: const HomeSection(
                              id: 'reels', type: HomeSectionType.reels),
                          onOpen: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ReelsScreen()),
                          ),
                        ),
                      ),
                    if (_forYou.isNotEmpty) ...[
                      const _SectionHeader(
                        title: 'Recommended for you',
                      ),
                      SliverToBoxAdapter(
                        child:
                            ProductRail(products: _forYou, onTap: _openProduct),
                      ),
                    ],
                    _AllItems(
                      products: _featured,
                      onOpen: _openProduct,
                    ),
                    const SliverToBoxAdapter(
                        child: SizedBox(height: DsSpace.s10)),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The home page as the admin laid it out, section by section.
  List<Widget> _sectionSlivers() {
    final slivers = <Widget>[];

    for (final section in _sections) {
      final Widget? body = switch (section.type) {
        HomeSectionType.hero => PictureCard(
            title: section.title,
            subtitle: section.subtitle,
            imageUrl: section.imageUrl,
            aspectRatio: 4 / 3,
            large: true,
            onTap: _linkHandler(section.linkUrl),
          ),
        HomeSectionType.banner => PictureCard(
            title: section.title,
            subtitle: section.subtitle,
            imageUrl: section.imageUrl,
            aspectRatio: 16 / 7,
            onTap: _linkHandler(section.linkUrl),
          ),
        HomeSectionType.categoryGrid => _categories.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    title: section.title.isNotEmpty
                        ? section.title
                        : 'Shop by category',
                    subtitle: section.subtitle,
                  ),
                  CategoryShortcuts(
                    scrollable: true,
                    categories: _categories,
                    onSelected: (category) => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => CategoryScreen(
                                category: category, siblings: _categories))),
                  ),
                ],
              ),
        HomeSectionType.productRow => ProductRowSection(
            key: ValueKey(section.id),
            section: section,
            categories: _categories,
            onTap: _openProduct,
          ),
        HomeSectionType.reels => _hasReels
            ? ReelsPromo(
                section: section,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReelsScreen()),
                ),
              )
            : null,
        HomeSectionType.trust => TrustStrip(section: section),
      };

      if (body != null) slivers.add(SliverToBoxAdapter(child: body));
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: DsSpace.s10)));
    return slivers;
  }

  /// A tap handler for a section's `link_url`, or null when it is empty or not
  /// something the app can open.
  VoidCallback? _linkHandler(String? url) {
    final link = HomeLink.parse(url);
    if (link == null) return null;

    return () {
      final navigator = Navigator.of(context);
      switch (link) {
        case CategoryLink(:final slug):
          final category = _categories.where((c) => c.slug == slug).firstOrNull;
          if (category != null) {
            navigator.push(MaterialPageRoute(
                builder: (_) =>
                    CategoryScreen(category: category, siblings: _categories)));
          }
        case ProductLink(:final id):
          navigator.push(MaterialPageRoute(
              builder: (_) => ProductDetailScreen(productId: id)));
        case SearchLink(:final query):
          navigator.push(MaterialPageRoute(
              builder: (_) => SearchScreen(initialQuery: query)));
        case ReelsLink():
          navigator
              .push(MaterialPageRoute(builder: (_) => const ReelsScreen()));
      }
    };
  }

  void _openCategoryList() {
    if (_categories.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Shop by category')),
                body: SingleChildScrollView(
                    child: CategoryShortcuts(
                  categories: _categories,
                  onSelected: (category) => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => CategoryScreen(
                              category: category, siblings: _categories))),
                )),
              )),
    );
  }
}

class _Hero extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback? onShopNow;

  const _Hero({required this.imageUrl, required this.onShopNow});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Padding(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s2, DsSpace.s4, 0),
      child: ClipRRect(
        borderRadius: DsRadius.cardAll,
        child: LayoutBuilder(builder: (context, box) {
          // The text decides the banner's height (it grows with the system
          // font); the picture fills whatever that turns out to be.
          final textWidth =
              imageUrl == null ? box.maxWidth : box.maxWidth * 0.58;
          return Container(
            constraints: const BoxConstraints(minHeight: 150),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.accent, c.accentHover],
              ),
            ),
            child: Stack(
              children: [
                if (imageUrl != null)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: box.maxWidth - textWidth,
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                SizedBox(
                  width: textWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(DsSpace.s4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'NEW ARRIVALS',
                          style: TextStyle(
                            fontSize: DsText.x2xs,
                            letterSpacing: 1,
                            fontWeight: DsWeight.semibold,
                            color: c.onAccent.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Festive season sale',
                          style: TextStyle(
                            fontFamily: DsFont.display,
                            fontSize: DsText.lg,
                            height: 1.2,
                            fontWeight: DsWeight.bold,
                            color: c.onAccent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Up to 60% off',
                          style: TextStyle(
                            fontSize: DsText.xs,
                            color: c.onAccent.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: DsSpace.s3),
                        Material(
                          color: c.onAccent,
                          borderRadius: DsRadius.controlAll,
                          child: InkWell(
                            borderRadius: DsRadius.controlAll,
                            onTap: onShopNow,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: DsSpace.s4, vertical: DsSpace.s2),
                              child: Text(
                                'Shop now',
                                style: TextStyle(
                                  fontSize: DsText.xs,
                                  fontWeight: DsWeight.bold,
                                  color: c.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            DsSpace.s4, DsSpace.s5, DsSpace.s4, DsSpace.s3),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: DsFont.display,
            fontSize: DsText.md,
            fontWeight: DsWeight.bold,
            color: c.ink,
          ),
        ),
      ),
    );
  }
}

/// What the item list can be narrowed to - the quick filters restaurant and
/// grocery apps put above a long list.
enum _Quick { all, offers, top, isNew, under500 }

extension on _Quick {
  String get label => switch (this) {
        _Quick.all => 'All',
        _Quick.offers => 'Offers',
        _Quick.top => 'Top rated',
        _Quick.isNew => 'New',
        _Quick.under500 => 'Under ₹500',
      };

  bool matches(Product p) => switch (this) {
        _Quick.all => true,
        _Quick.offers => p.discount > 0,
        _Quick.top => p.rating >= 4,
        _Quick.isNew => p.isNew,
        _Quick.under500 => p.price <= 500,
      };
}

/// Every item as a detailed row, under quick filters.
class _AllItems extends StatefulWidget {
  final List<Product> products;
  final void Function(Product) onOpen;

  const _AllItems({required this.products, required this.onOpen});

  @override
  State<_AllItems> createState() => _AllItemsState();
}

class _AllItemsState extends State<_AllItems> {
  _Quick _quick = _Quick.all;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final shown = widget.products.where(_quick.matches).toList();

    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              DsSpace.s4, DsSpace.s5, DsSpace.s4, DsSpace.s2),
          child: Text(
            'All items',
            style: TextStyle(
              fontFamily: DsFont.display,
              fontSize: DsText.md,
              fontWeight: DsWeight.bold,
              color: c.ink,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
            itemCount: _Quick.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: DsSpace.s2),
            itemBuilder: (context, i) {
              final q = _Quick.values[i];
              final selected = q == _quick;
              return Center(
                child: Material(
                  color: selected ? c.primary : c.surface,
                  borderRadius: DsRadius.controlAll,
                  child: InkWell(
                    borderRadius: DsRadius.controlAll,
                    onTap: () => setState(() => _quick = q),
                    child: Container(
                      height: 34,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: DsRadius.controlAll,
                        border:
                            Border.all(color: selected ? c.primary : c.line),
                      ),
                      child: Text(q.label,
                          style: TextStyle(
                            fontSize: DsText.sm,
                            fontWeight: DsWeight.semibold,
                            color: selected ? c.onPrimary : c.inkMuted,
                          )),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      if (shown.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(DsSpace.s8),
            child: Center(
              child: Text('Nothing matches "${_quick.label}" right now.',
                  style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
            ),
          ),
        )
      else
        SliverList.separated(
          itemCount: shown.length,
          separatorBuilder: (_, __) => const Divider(
              height: 1, indent: DsSpace.s4, endIndent: DsSpace.s4),
          itemBuilder: (context, i) => ProductListRow(
            product: shown[i],
            onTap: () => widget.onOpen(shown[i]),
          ),
        ),
    ]);
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BxSkeleton(width: 160, height: 20),
          const SizedBox(height: DsSpace.s4),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: DsSpace.s3),
              itemBuilder: (_, __) => const BxSkeleton(
                  width: 60, height: 60, radius: DsRadius.cardAll),
            ),
          ),
          const SizedBox(height: DsSpace.s5),
          const BxSkeleton(width: 200, height: 20),
          const SizedBox(height: DsSpace.s4),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: DsSpace.s3,
            crossAxisSpacing: DsSpace.s3,
            childAspectRatio: 0.62,
            children: List.generate(
              4,
              (_) => const BxSkeleton(
                  height: double.infinity, radius: DsRadius.cardAll),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Shops near you" over the shop list of a vendors-only store's home screen.
class _ShopsHeading extends StatelessWidget {
  const _ShopsHeading();

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s3),
        child: Text(
          'Order from a shop',
          style: TextStyle(
            fontFamily: DsFont.display,
            fontSize: DsText.xl,
            fontWeight: DsWeight.black,
            color: c.ink,
          ),
        ),
      ),
    );
  }
}
