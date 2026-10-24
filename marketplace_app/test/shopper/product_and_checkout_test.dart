import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/screens/checkout_screen.dart';
import 'package:marketplace_app/screens/product_detail_screen.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/product_card.dart';
import 'support.dart';

void main() {
  setUp(resetState);
  testWidgets(
      'multi-variant card asks for the variant in a sheet instead of adding a guess',
      (tester) async {
    phone(tester, height: 1200);
    var opened = false;
    var added = false;
    await tester.pumpWidget(app(Scaffold(
        body: SizedBox(
            width: 172,
            child: ProductCardTile(
              product: Product.fromJson(product(options: true)),
              onTap: () => opened = true,
              onAddToCart: () => added = true,
            )))));
    await tester.tap(find.byTooltip('Choose options'));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    expect(added, isFalse);
    expect(find.textContaining('Add item'), findsOneWidget);
  });

  testWidgets('product selection adds correct variant and price',
      (tester) async {
    phone(tester);
    final client = MockClient((request) async => response(
          request.url.path.endsWith('/reviews') ? [] : product(options: true),
        ));
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
      await finishLoad(tester);
      await tester.scrollUntilVisible(find.bySemanticsLabel('Red'), 250,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.bySemanticsLabel('Red'));
      await tester.pump();
      await tester.tap(find.text('Add to cart'));
      await tester.pump();
      expect(AppState.instance.cart.single.variant?.id, 'v2');
      expect(AppState.instance.cartSubtotal, 1099);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('out-of-stock product cannot enter cart', (tester) async {
    phone(tester);
    final client = MockClient((request) async => response(
          request.url.path.endsWith('/reviews') ? [] : product(stock: 0),
        ));
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
      await finishLoad(tester);
      final button = tester.widget<BxButton>(find.byWidgetPredicate(
          (w) => w is BxButton && w.label == 'Out of stock'));
      expect(button.onPressed, isNull);
      expect(AppState.instance.cart, isEmpty);
    }, () => client);
  });

  for (final failure in [false, true]) {
    testWidgets(
        'COD checkout ${failure ? 'retains cart on failure' : 'submits address and variant then clears cart'}',
        (tester) async {
      phone(tester, height: 1100);
      Map<String, dynamic>? checkout;
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login')) {
          return response({'token': 'test-token', 'user': user});
        }
        if (path.endsWith('/addresses')) {
          return response([
            {
              'id': 'a1',
              'name': 'Shopper',
              'phone': '9876543210',
              'line1': '42 Test street',
              'city': 'Delhi',
              'state': 'Delhi',
              'pincode': '110001',
              'is_default': true,
            }
          ]);
        }
        if (path.endsWith('/delivery/quote')) {
          return response({
            'options': [
              {
                'service_level': 'standard',
                'label': 'Standard delivery',
                'price': 79,
                'eta_label': '3–5 days',
                'cod_supported': true,
              }
            ]
          });
        }
        if (path.endsWith('/orders/checkout')) {
          checkout = jsonDecode(request.body) as Map<String, dynamic>;
          if (failure) {
            return http.Response(
                jsonEncode(
                    {'message': 'Stock changed. Please review your cart.'}),
                422);
          }
          return response({'id': 'order1'});
        }
        if (path.endsWith('/auth/me')) return response(user);
        if (path.endsWith('/orders/order1')) {
          return response({
            'id': 'order1',
            'order_number': 'BX-1',
            'status': 'PENDING',
            'payment_method': 'COD',
            'total_amount': 1078,
            'items': [],
          });
        }
        return response({}, status: 404);
      });
      await http.runWithClient(() async {
        await AppState.instance.signIn('shopper@example.com', 'test-password');
        AppState.instance.addToCart(Product.fromJson(product()));
        await tester.pumpWidget(app(const CheckoutScreen()));
        await finishLoad(tester);
        await tester.scrollUntilVisible(find.text('Cash'), 300,
            scrollable: find
                .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable))
                .first);
        await tester.tap(find.text('Cash'));
        await finishLoad(tester);
        await tester.tap(find.text('Place order'));
        await finishLoad(tester);
        expect(checkout?['payment_method'], 'COD');
        expect((checkout?['shipping_address'] as Map)['pincode'], '110001');
        expect(checkout?['items'], [
          {'product_id': 'p1', 'variant_id': 'v1', 'quantity': 1}
        ]);
        expect(AppState.instance.cart.isEmpty, !failure);
        if (failure) {
          await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
          await tester.pump();
          expect(find.text('Stock changed. Please review your cart.'),
              findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });
  }

  testWidgets('checkout stays disabled without an address', (tester) async {
    phone(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const CheckoutScreen()));
      await finishLoad(tester);
      final place = tester.widget<BxButton>(find
          .byWidgetPredicate((w) => w is BxButton && w.label == 'Place order'));
      expect(place.onPressed, isNull);
    }, () => MockClient((_) async => response([])));
  });
}
