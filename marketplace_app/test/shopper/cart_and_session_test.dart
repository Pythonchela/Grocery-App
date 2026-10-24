import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/design/brand.g.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetState);
  test('cart selects valid variant and rejects unavailable or excess stock',
      () {
    final state = AppState.instance;
    final item = Product.fromJson(product());
    expect(state.addToCart(item, quantity: 2), isTrue);
    expect(state.cart.single.variant?.id, 'v1');
    expect(state.cartSubtotal, 1998);
    expect(state.addToCart(item, quantity: 2), isFalse);
    expect(state.cartCount, 2);
    state.updateQuantity(state.cart.single.key, 50);
    expect(state.cartCount, 3);
    expect(state.addToCart(Product.fromJson(product(id: 'empty', stock: 0))),
        isFalse);
    state.removeFromCart(state.cart.single.key);
    expect(state.cart, isEmpty);
  });
  test('cart respects backend twenty-item limit', () {
    final state = AppState.instance;
    final item = Product.fromJson(product(stock: 100));
    expect(state.addToCart(item, quantity: 20), isTrue);
    expect(state.addToCart(item), isFalse);
    state.updateQuantity(state.cart.single.key, 100);
    expect(state.cartCount, 20);
  });
  test(
      'restoring cart skips removed products, refreshes stock and avoids duplicates',
      () async {
    SharedPreferences.setMockInitialValues({
      DsBrand.storageKey('cart'): jsonEncode([
        {'product_id': 'removed', 'variant_id': 'v1', 'quantity': 1},
        {'product_id': 'good', 'variant_id': 'v1', 'quantity': 100},
        {
          'product_id': 'missing-variant',
          'variant_id': 'deleted',
          'quantity': 2
        },
      ])
    });
    await AppState.instance.load();
    final client = MockClient((request) async =>
        request.url.path.endsWith('/removed')
            ? response({}, status: 404)
            : response(product(id: request.url.pathSegments.last)));
    await http.runWithClient(() async {
      await AppState.instance.restoreCart();
      await AppState.instance.restoreCart();
    }, () => client);
    expect(AppState.instance.cart.length, 1);
    expect(AppState.instance.cart.single.product.id, 'good');
    expect(AppState.instance.cartCount, 3);
  });
  test('sign-in persists session and expired token clears it', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        expect(jsonDecode(request.body)['email'], 'shopper@example.com');
        return response({'token': 'test-token', 'user': user});
      }
      expect(request.headers['Authorization'], 'Bearer test-token');
      return response({}, status: 401);
    });
    await http.runWithClient(() async {
      await AppState.instance.signIn('shopper@example.com', 'test-password');
      expect(AppState.instance.user?.email, 'shopper@example.com');
      await expectLater(
          ApiClient.request('/orders/mine', token: AppState.instance.token),
          throwsA(isA<ApiException>()));
      expect(AppState.instance.isSignedIn, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DsBrand.storageKey('auth_token')), isNull);
    }, () => client);
  });
  test('offline restoration preserves saved cart for a later retry', () async {
    final saved = jsonEncode([
      {'product_id': 'p1', 'variant_id': 'v1', 'quantity': 1},
    ]);
    SharedPreferences.setMockInitialValues({DsBrand.storageKey('cart'): saved});
    await AppState.instance.load();
    await http.runWithClient(() => AppState.instance.restoreCart(),
        () => MockClient((_) async => throw http.ClientException('offline')));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DsBrand.storageKey('cart')), saved);
  });
  test('offline request returns a useful message', () async {
    await http.runWithClient(() async {
      await expectLater(
          ApiClient.request('/products'),
          throwsA(isA<ApiException>().having(
              (e) => e.message, 'message', contains('internet connection'))));
    },
        () => MockClient(
            (_) async => throw http.ClientException('socket error')));
  });
}
