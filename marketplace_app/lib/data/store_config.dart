/// What kind of store this app is talking to, as the server states it.
///
/// One app serves three kinds of business: a single business selling its own
/// goods (`single`), the owner's shop selling next to vendors (`hybrid`), and
/// vendors only (`multi`). The server decides; the app hides or shows shops, the
/// "become a seller" entry and the one-shop-per-basket rule to match.
class StoreConfig {
  final String mode;
  final bool vendorsEnabled;
  final bool houseVisible;

  /// Shoppers choose a shop first, then its items (vendors-only stores).
  final bool shopsFirst;

  /// Whether shops are shown to shoppers at all.
  final bool showsShops;

  /// Whether the home screen carries a row of shops among its products. A store
  /// can choose to list products directly and keep shops on their own page.
  final bool homeShowsShops;

  /// A basket holds one shop's goods at a time.
  final bool oneShopPerCart;
  final String storeName;

  const StoreConfig({
    required this.mode,
    required this.vendorsEnabled,
    required this.houseVisible,
    required this.shopsFirst,
    required this.showsShops,
    required this.oneShopPerCart,
    this.homeShowsShops = true,
    this.storeName = '',
  });

  /// Used until the server answers, and when it cannot (an older server has no
  /// such endpoint): the app behaves exactly as it did before shops existed.
  static const fallback = StoreConfig(
    mode: 'hybrid',
    vendorsEnabled: true,
    houseVisible: true,
    shopsFirst: false,
    showsShops: false,
    oneShopPerCart: false,
  );

  factory StoreConfig.fromJson(Map<String, dynamic> j) => StoreConfig(
        mode: '${j['mode'] ?? 'hybrid'}',
        vendorsEnabled: j['vendors_enabled'] != false,
        houseVisible: j['house_visible'] != false,
        shopsFirst: j['shops_first'] == true,
        showsShops: j['shows_shops'] == true,
        homeShowsShops: j['home_shows_shops'] != false,
        oneShopPerCart: j['one_shop_per_cart'] == true,
        storeName: '${j['store_name'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'vendors_enabled': vendorsEnabled,
        'house_visible': houseVisible,
        'shops_first': shopsFirst,
        'shows_shops': showsShops,
        'home_shows_shops': homeShowsShops,
        'one_shop_per_cart': oneShopPerCart,
        'store_name': storeName,
      };
}
