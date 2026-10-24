import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:marketplace_app/data/cart_delivery.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/screens/cart_screen.dart';
import 'package:marketplace_app/screens/product_detail_screen.dart';
import 'package:marketplace_app/state/app_state.dart';

import 'support.dart';

DeliveryOption option(int minutes, {String level = 'STANDARD', String label = ''}) =>
    DeliveryOption.fromJson({
      'carrier': 'porter',
      'carrier_label': 'Porter',
      'service_level': level,
      'label': label.isEmpty ? level : label,
      'description': '',
      'price': 49,
      'eta_label': minutes < 90 ? '$minutes min' : '3 days',
      'eta_minutes': minutes,
      'cod_supported': true,
    });

/// What the delivery screens say has to match how long it really takes.
void main() {
  setUp(resetState);

  group('how long it takes, in words', () {
    final now = DateTime(2026, 10, 9, 10, 0);

    test('quick deliveries are in minutes', () {
      expect(etaPhrase(option(25), now: now), 'Delivery in 25 mins');
      expect(etaPhrase(option(74), now: now), 'Delivery in 74 mins');
    });

    test('a few hours reads as hours, not a rounded guess', () {
      expect(etaPhrase(option(90), now: now), 'Delivery in 1 hr 30 mins');
      expect(etaPhrase(option(120), now: now), 'Delivery in 2 hrs');
      expect(etaPhrase(option(185), now: now), 'Delivery in 3 hrs');
      expect(etaPhrase(option(235), now: now), 'Delivery in 4 hrs');
      expect(etaPhrase(option(500), now: now), 'Delivery in 8 hrs 20 mins');
    });

    test('a day or more is a date, never "in tomorrow"', () {
      expect(etaPhrase(option(24 * 60 + 90), now: now), 'Delivery tomorrow');

      final threeDays = now.add(const Duration(days: 3));
      expect(etaPhrase(option(3 * 24 * 60), now: now),
          'Delivery by ${DateFormat('EEE, d MMM').format(threeDays)}');
    });

    test('with no usable minutes it falls back to the server wording', () {
      expect(etaPhrase(option(0), now: now), 'Delivery 0 min');
    });
  });

  group('product page', () {
    Future<void> open(WidgetTester tester, Map<String, dynamic> extra) async {
      phone(tester, height: 1800);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/products/p1')) {
          return response({...product(), ...extra});
        }
        return response([]);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
        await finishLoad(tester);
      }, () => client);
    }

    testWidgets('food says it is quick, and how long it takes to make',
        (tester) async {
      await open(tester, {
        'delivery_info': {'profile': 'instant', 'prep_minutes': 25}
      });
      await tester.scrollUntilVisible(find.textContaining('Quick local delivery'), 300,
          scrollable: find.byType(Scrollable).first);

      expect(find.textContaining('ready in about 25 mins'), findsOneWidget);
      expect(find.textContaining('Free delivery above'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a parcel says courier, not minutes', (tester) async {
      await open(tester, {
        'delivery_info': {'profile': 'parcel', 'prep_minutes': 60}
      });
      await tester.scrollUntilVisible(find.textContaining('Courier delivery'), 300,
          scrollable: find.byType(Scrollable).first);

      expect(find.textContaining('track every step'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a product with no profile keeps the plain line', (tester) async {
      await open(tester, {});
      await tester.scrollUntilVisible(find.text('Free delivery above ₹1,999'), 300,
          scrollable: find.byType(Scrollable).first);

      expect(find.text('Free delivery above ₹1,999'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('cart', () {
    MockClient shop(Map<String, dynamic> quote) => MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/auth/login')) {
            return response({'token': 't', 'user': user});
          }
          if (path.endsWith('/addresses')) {
            return response([
              {
                'id': 'a1', 'tag': 'Home', 'name': 'S', 'phone': '9876543210',
                'line1': 'x', 'city': 'Delhi', 'state': 'Delhi', 'pincode': '110001',
                'is_default': true,
              }
            ]);
          }
          if (path.endsWith('/delivery/quote')) return response(quote);
          return response({}, status: 404);
        });

    Future<void> open(WidgetTester tester, MockClient client) async {
      phone(tester, height: 1400);
      await http.runWithClient(() async {
        await AppState.instance.signIn('s@example.com', 'pw');
        AppState.instance.addToCart(Product.fromJson(product()));
        await tester.pumpWidget(app(CartScreen(onStartShopping: () {})));
        await finishLoad(tester);
      }, () => client);
    }

    testWidgets('food mixed with a parcel says why it cannot ship together',
        (tester) async {
      await open(
          tester,
          shop({
            'options': [],
            'message': 'Some of these items are delivered by a local rider and some by courier, so they cannot ship together. Please order them separately.',
          }));

      expect(find.text('These items ship separately'), findsOneWidget);
      expect(find.textContaining('order them separately'), findsOneWidget);
      expect(find.text('Delivery not available here yet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a basket from two sellers says it ships as two parcels', (tester) async {
      await open(
          tester,
          shop({
            'options': [
              {
                'carrier': 'multiple', 'carrier_label': 'Several couriers',
                'service_level': 'STANDARD', 'label': 'Standard delivery',
                'description': '', 'price': 212, 'eta_label': '3 days',
                'eta_minutes': 3 * 24 * 60, 'cod_supported': true,
              }
            ],
            'parcels': [
              {'seller_id': 'a', 'seller_name': 'Shop A', 'pickup_pincode': '560034', 'pickup_city': 'Bengaluru', 'items': 1},
              {'seller_id': 'b', 'seller_name': 'Shop B', 'pickup_pincode': '400050', 'pickup_city': 'Mumbai', 'items': 1},
            ],
          }));

      expect(find.textContaining('in 2 parcels'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a parcel cart promises a date, not minutes', (tester) async {
      await open(
          tester,
          shop({
            'options': [
              {
                'carrier': 'delhivery', 'carrier_label': 'Delhivery',
                'service_level': 'STANDARD', 'label': 'Standard delivery',
                'description': '', 'price': 0, 'eta_label': '3 days',
                'eta_minutes': 3 * 24 * 60, 'cod_supported': true,
              }
            ],
          }));

      expect(find.textContaining('Delivery by'), findsOneWidget);
      expect(find.textContaining('mins'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
