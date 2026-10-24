import 'models.dart';

/// A two-product "buy together and save" deal, as listed by `/deals/bundles`.
class Bundle {
  final String id;
  final String name;
  final String description;
  final double price;
  final double compareAt;
  final double savings;
  final Product primary;
  final Product secondary;

  Bundle({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.compareAt,
    required this.savings,
    required this.primary,
    required this.secondary,
  });

  /// Null when the payload is not a complete two-product bundle, so one bad row
  /// from the API never blanks the whole list.
  static Bundle? tryParse(Map<String, dynamic> j) {
    final products = j['products'];
    if (products is! List || products.length != 2) return null;
    double num0(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;
    try {
      return Bundle(
        id: '${j['id']}',
        name: '${j['name'] ?? 'Bundle deal'}',
        description: '${j['description'] ?? ''}',
        price: num0(j['bundle_price']),
        compareAt: num0(j['compare_at_price']),
        savings: num0(j['savings']),
        primary: Product.fromJson(products[0] as Map<String, dynamic>),
        secondary: Product.fromJson(products[1] as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }

  bool includes(String productId) =>
      primary.id == productId || secondary.id == productId;

  Product partnerOf(String productId) =>
      primary.id == productId ? secondary : primary;
}

/// One bundle applied to a cart, for display.
class AppliedBundle {
  final Bundle bundle;
  final int pairs;
  final double discount;
  const AppliedBundle(this.bundle, this.pairs, this.discount);
}

/// The cart-side mirror of the server's `BundleDiscounts`.
///
/// Display only: the API re-prices every order from its own database and its
/// number is the one that bills. The rules are kept identical so the two agree —
/// whole pairs only, the cheapest variant of a product sets the saving, and the
/// best saving claims a shared product first.
class BundlePricing {
  const BundlePricing._();

  static List<AppliedBundle> apply(List<CartLine> cart, List<Bundle> bundles) {
    if (cart.isEmpty || bundles.isEmpty) return const [];

    final remaining = <String, int>{};
    final unitPrice = <String, double>{};
    for (final line in cart) {
      final id = line.product.id;
      remaining[id] = (remaining[id] ?? 0) + line.quantity;
      final price = line.unitPrice;
      unitPrice[id] = unitPrice.containsKey(id)
          ? (price < unitPrice[id]! ? price : unitPrice[id]!)
          : price;
    }

    final candidates = <(Bundle, double)>[];
    for (final b in bundles) {
      final a = b.primary.id;
      final c = b.secondary.id;
      if (a == c || !remaining.containsKey(a) || !remaining.containsKey(c)) {
        continue;
      }
      final saving = _round(unitPrice[a]! + unitPrice[c]! - b.price);
      if (saving > 0) candidates.add((b, saving));
    }
    candidates.sort((x, y) => y.$2.compareTo(x.$2));

    final applied = <AppliedBundle>[];
    for (final (bundle, saving) in candidates) {
      final a = bundle.primary.id;
      final c = bundle.secondary.id;
      final pairs =
          remaining[a]! < remaining[c]! ? remaining[a]! : remaining[c]!;
      if (pairs <= 0) continue;
      remaining[a] = remaining[a]! - pairs;
      remaining[c] = remaining[c]! - pairs;
      applied.add(AppliedBundle(bundle, pairs, _round(pairs * saving)));
    }
    return applied;
  }

  static double discount(List<CartLine> cart, List<Bundle> bundles) =>
      apply(cart, bundles).fold(0.0, (sum, a) => _round(sum + a.discount));

  /// Bundles where the cart holds exactly one of the two products — a nudge to
  /// complete the pair.
  static List<Bundle> suggestions(List<CartLine> cart, List<Bundle> bundles) {
    final inCart = cart.map((l) => l.product.id).toSet();
    return bundles
        .where((b) =>
            inCart.contains(b.primary.id) != inCart.contains(b.secondary.id))
        .toList();
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}
