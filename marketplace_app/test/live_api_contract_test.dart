import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/data/models.dart';

// Read-only production smoke check. Opt in with --dart-define=LIVE_API_TESTS=true.
// Normal CI stays independent of production uptime and never creates live orders.
void main() {
  const live = bool.fromEnvironment('LIVE_API_TESTS');
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'live category, product, search and details contracts match mobile models',
      () async {
    HttpOverrides.global = null;
    final categories = await ApiClient.request('/categories') as List;
    expect(categories.map((c) => Category.fromJson(c).slug),
        contains('electronics'));
    final products = await ApiClient.request('/products') as List;
    expect(products, isNotEmpty);
    final matches =
        await ApiClient.request('/products', query: {'search': 'headphones'})
            as List;
    expect(matches, isNotEmpty);
    expect(matches.length, lessThan(products.length));
    for (final match in matches) {
      final product = Product.fromJson(match);
      expect(product.title.toLowerCase(), contains('headphones'));
      final detail =
          Product.fromJson(await ApiClient.request('/products/${product.id}'));
      expect(detail.id, product.id);
      expect(detail.variants, isNotEmpty);
      expect(
          detail.inStock, detail.variants.any((variant) => variant.stock > 0));
    }
  }, skip: !live);
}
