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
import '../widgets/category_shortcuts.dart';
import '../widgets/home_sections.dart';
import '../widgets/quick_home.dart';
import 'category_screen.dart';
import 'product_detail_screen.dart';
import 'notifications_screen.dart';
import 'reels_screen.dart';
import 'search_screen.dart';

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
  HomeLayout _layout = HomeLayout.plan(const []);
  bool _hasReels = false;
  bool _vegOnly = false;
  bool _offersOnly = false;
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
        _layout = HomeLayout.plan(HomeSection.parseList(results[3]));
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
                pinned: true,
                backgroundColor: c.accentSoft,
                surfaceTintColor: Colors.transparent,
                toolbarHeight: 64,
                titleSpacing: DsSpace.s4,
                title: Row(
                  children: [
                    BrandMark(logoUrl: AppState.instance.logoUrl, size: 36),
                    const SizedBox(width: DsSpace.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            readyRange([..._featured, ..._trending]) == null
                                ? DsBrand.name
                                : 'Ready in ${readyRange([..._featured, ..._trending])}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: DsFont.display,
                              fontSize: DsText.xl,
                              height: 1.15,
                              fontWeight: DsWeight.black,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            'Delivered fresh by ${DsBrand.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: DsText.xs, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  // Order and delivery news live behind the bell; the dot says
                  // there is something unread.
                  AnimatedBuilder(
                    animation: AppState.instance,
                    builder: (context, _) => IconButton(
                      tooltip: AppState.instance.unreadNotifications > 0
                          ? 'Notifications (${AppState.instance.unreadNotifications} unread)'
                          : 'Notifications',
                      icon: Badge(
                        isLabelVisible: AppState.instance.unreadNotifications > 0,
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
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(64),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(DsSpace.s4, 0, DsSpace.s4, DsSpace.s3),
                    child: QuickSearchBar(
                      hint: _featured.isEmpty ? 'Search for products' : 'Search "${_featured.first.title.replaceFirst('Sample: ', '')}"',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      ),
                    ),
                  ),
                ),
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
              if (!_layout.isEmpty && !_loading) ...[
                ..._sectionSlivers(),
                if (_layout.needsCatalogue)
                  ..._catalogueSlivers(withReels: !_layout.hasReelsSection)
                else
                  const SliverToBoxAdapter(
                      child: SizedBox(height: DsSpace.s10)),
              ] else ...[
                if (_loading)
                  const SliverToBoxAdapter(child: _HomeSkeleton())
                else
                  ..._catalogueSlivers(withReels: true),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The app's own categories and product lists: the whole home page when the
  /// admin has no layout, and what follows a layout that shows no products.
  List<Widget> _catalogueSlivers({required bool withReels}) {
    bool keep(Product p) =>
        !(_vegOnly && (p.diet == 'non_veg' || p.diet == 'egg')) && !(_offersOnly && p.discount <= 0);

    final popular = _trending.where(keep).toList();
    final forYou = _forYou.where(keep).toList();
    final shown = _featured.where(keep).toList();
    final byCategory = <Category, List<Product>>{
      for (final category in _categories)
        category: shown.where((p) => p.categoryName == category.name).toList(),
    };
    void open(Category category) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CategoryScreen(category: category, siblings: _categories)));

    return [
      SliverToBoxAdapter(
        child: QuickToolbar(
          vegOnly: _vegOnly,
          offersOnly: _offersOnly,
          onVeg: (v) => setState(() => _vegOnly = v),
          onOffers: (v) => setState(() => _offersOnly = v),
        ),
      ),
      SliverToBoxAdapter(child: QuickCategoryGrid(categories: _categories, onSelected: open)),
      SliverToBoxAdapter(child: QuickSection(title: 'Popular right now', products: popular, onTap: _openProduct)),
      if (withReels && _hasReels)
        SliverToBoxAdapter(
          child: ReelsPromo(
            section: const HomeSection(id: 'reels', type: HomeSectionType.reels),
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReelsScreen()),
            ),
          ),
        ),
      SliverToBoxAdapter(child: QuickSection(title: 'Picked for you', products: forYou, onTap: _openProduct)),
      for (final entry in byCategory.entries)
        SliverToBoxAdapter(
          child: QuickSection(
            title: entry.key.name,
            products: entry.value.take(10).toList(),
            onTap: _openProduct,
            onSeeAll: () => open(entry.key),
          ),
        ),
      if (!_loading && _error == null && popular.isEmpty && shown.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(DsSpace.s8),
            child: Center(
              child: Text('Nothing matches those filters right now.',
                  style: TextStyle(fontSize: DsText.sm, color: context.ds.inkMuted)),
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: DsSpace.s10)),
    ];
  }
  /// The home page as the admin laid it out, section by section.
  List<Widget> _sectionSlivers() {
    final slivers = <Widget>[];

    for (final section in _layout.sections) {
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
