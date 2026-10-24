import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/delivery_eta.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/screens/cart_screen.dart';
import 'package:marketplace_app/screens/checkout_screen.dart';
import 'package:marketplace_app/screens/order_tracking_screen.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/delivery_route.dart';
import 'package:marketplace_app/widgets/delivery_widgets.dart';

import 'support.dart';

const _address = {
  'id': 'a1',
  'tag': 'Home',
  'name': 'Shopper',
  'phone': '9876543210',
  'line1': '42 Test street',
  'city': 'Delhi',
  'state': 'Delhi',
  'pincode': '110001',
  'is_default': true,
};

Map<String, dynamic> _option(String level, int minutes, num price,
        {String label = '', String? free}) =>
    {
      'carrier': 'porter',
      'carrier_label': 'Porter',
      'service_level': level,
      'label': label.isEmpty ? level : label,
      'description': '',
      'price': price,
      'eta_label': minutes < 90 ? '$minutes min' : '3–5 days',
      'eta_minutes': minutes,
      'cod_supported': true,
      if (free != null) 'free_reason': free,
    };

void main() {
  setUp(resetState);

  group('arrival wording', () {
    final now = DateTime(2026, 10, 9, 18, 0);

    test('a courier estimate beats the checkout promise', () {
      final eta = describeEta(
          status: 'OUT_FOR_DELIVERY',
          etaMinutes: 18,
          promisedBy: now.add(const Duration(hours: 3)),
          now: now);
      expect(eta.headline, 'Arriving in 18 mins');
    });

    test('with no estimate the promise is used', () {
      expect(
          describeEta(
                  status: 'CONFIRMED',
                  promisedBy: now.add(const Duration(minutes: 40)),
                  now: now)
              .headline,
          'Arriving in 40 mins');
    });

    test('a promise a few hours out is a clock time', () {
      final eta = describeEta(
          status: 'PACKED',
          promisedBy: now.add(const Duration(hours: 4)),
          now: now);
      expect(eta.headline, startsWith('Arriving by '));
      expect(eta.headline, contains('10:00'));
    });

    test('a promise on another day is a date', () {
      final eta = describeEta(
          status: 'CONFIRMED',
          promisedBy: now.add(const Duration(days: 3)),
          now: now);
      expect(eta.headline, startsWith('Arriving by '));
      expect(eta.headline, contains('Oct'));
    });

    test('overdue is said plainly', () {
      expect(
          describeEta(
                  status: 'SHIPPED',
                  promisedBy: now.subtract(const Duration(minutes: 5)),
                  now: now)
              .headline,
          'Running a little late');
    });

    test('final states do not talk about arrival', () {
      expect(describeEta(status: 'DELIVERED').headline, 'Delivered');
      expect(describeEta(status: 'CANCELLED').headline, 'Order cancelled');
    });

    test('with nothing to go on it says it is preparing', () {
      expect(describeEta(status: 'PENDING').headline, 'Preparing your order');
    });

    test('status headlines name the partner when known', () {
      expect(statusHeadline('SHIPPED', riderName: 'Ravi'), 'Ravi is on the way');
      expect(statusHeadline('SHIPPED'), 'On its way');
      expect(statusHeadline('PACKED'), 'Packed and ready to go');
    });
  });

  group('delivery progress', () {
    final placed = DateTime(2026, 10, 9, 18, 0);
    final promised = placed.add(const Duration(minutes: 60));

    test('each status starts further along than the last', () {
      final steps = [
        for (final s in [
          'PENDING',
          'CONFIRMED',
          'PACKED',
          'SHIPPED',
          'OUT_FOR_DELIVERY',
          'DELIVERED'
        ])
          DeliveryProgress.of(s)
      ];
      expect(steps, orderedEquals([...steps]..sort()));
      expect(steps.first, 0);
      expect(steps.last, 1);
    });

    test('on the road it follows the clock', () {
      final early = DeliveryProgress.of('OUT_FOR_DELIVERY',
          placedAt: placed, promisedBy: promised, now: placed.add(const Duration(minutes: 20)));
      final late = DeliveryProgress.of('OUT_FOR_DELIVERY',
          placedAt: placed, promisedBy: promised, now: placed.add(const Duration(minutes: 50)));
      expect(late, greaterThan(early));
    });

    test('it never claims arrival before the order says delivered', () {
      final overdue = DeliveryProgress.of('OUT_FOR_DELIVERY',
          placedAt: placed, promisedBy: promised, now: placed.add(const Duration(hours: 5)));
      expect(overdue, lessThan(1));
    });

    test('it never goes behind where the status already puts it', () {
      final justDispatched = DeliveryProgress.of('OUT_FOR_DELIVERY',
          placedAt: placed, promisedBy: promised, now: placed);
      expect(justDispatched, greaterThanOrEqualTo(0.55));
    });

    test('before dispatch the clock does not move it', () {
      final waiting = DeliveryProgress.of('CONFIRMED',
          placedAt: placed, promisedBy: promised, now: placed.add(const Duration(minutes: 55)));
      expect(waiting, DeliveryProgress.of('CONFIRMED'));
    });
  });

  group('cart', () {
    MockClient shop({List<Map<String, dynamic>>? options, bool address = true}) =>
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/auth/login')) {
            return response({'token': 't', 'user': user});
          }
          if (path.endsWith('/addresses')) {
            return response(address ? [_address] : []);
          }
          if (path.endsWith('/delivery/quote')) {
            return response({
              'options': options ??
                  [
                    _option('INSTANT', 25, 49, label: 'Instant delivery'),
                    _option('STANDARD', 4320, 0, label: 'Standard delivery'),
                  ],
            });
          }
          return response({}, status: 404);
        });

    Future<void> openCart(WidgetTester tester, MockClient client,
        {double mrpGap = 0, int qty = 1}) async {
      phone(tester, height: 1400);
      await http.runWithClient(() async {
        await AppState.instance.signIn('shopper@example.com', 'pw');
        final p = product();
        p['mrp'] = (p['price'] as num) + mrpGap;
        AppState.instance.addToCart(Product.fromJson(p), quantity: qty);
        await tester.pumpWidget(app(CartScreen(onStartShopping: () {})));
        await finishLoad(tester);
      }, () => client);
    }

    testWidgets('leads with the delivery promise and the shipment size',
        (tester) async {
      await openCart(tester, shop());

      expect(find.text('Delivery in 25 mins'), findsOneWidget);
      expect(find.textContaining('Shipment of 1 item'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('asks for an address when there is none', (tester) async {
      await openCart(tester, shop(address: false));

      expect(find.text('Where should we deliver?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('says so when nothing can be delivered there', (tester) async {
      await openCart(tester, shop(options: []));

      expect(find.text('Delivery not available here yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows how much more is needed for free delivery',
        (tester) async {
      await openCart(tester, shop());

      // One ₹999 item against the ₹1,999 default threshold.
      expect(find.textContaining('more for free delivery'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('celebrates once free delivery is unlocked', (tester) async {
      await openCart(tester, shop(), qty: 3);

      expect(find.text('You have unlocked free delivery'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows what the shopper saves against the listed price',
        (tester) async {
      await openCart(tester, shop(), mrpGap: 500);

      expect(find.textContaining("You're saving"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('does not boast about savings that do not exist', (tester) async {
      await openCart(tester, shop());

      expect(find.textContaining("You're saving"), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lays out a bill and a single action', (tester) async {
      await openCart(tester, shop());

      expect(find.text('Bill details'), findsOneWidget);
      expect(find.text('Item total'), findsOneWidget);
      expect(find.text('Delivery fee'), findsOneWidget);
      expect(find.text('To pay'), findsOneWidget);
      expect(find.text('Proceed to checkout'), findsOneWidget);
      expect(find.textContaining('Delivering to'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('signed out it invites sign-in instead of quoting', (tester) async {
      phone(tester, height: 1400);
      await http.runWithClient(() async {
        AppState.instance.addToCart(Product.fromJson(product()));
        await tester.pumpWidget(app(CartScreen(onStartShopping: () {})));
        await finishLoad(tester);

        expect(find.text('See your delivery time'), findsOneWidget);
        expect(find.text('Sign in to checkout'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => shop());
    });
  });

  group('speed cards', () {
    testWidgets('lead with the time and badge the fastest', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Column(children: [
          DeliverySpeedCard(
            option: DeliveryOption.fromJson(_option('INSTANT', 25, 49, label: 'Instant delivery')),
            selected: true,
            fastest: true,
            onTap: () {},
          ),
          DeliverySpeedCard(
            option: DeliveryOption.fromJson(_option('STANDARD', 4320, 0, label: 'Standard delivery')),
            selected: false,
            cheapest: true,
            onTap: () {},
          ),
        ]),
      )));

      expect(find.text('25 mins'), findsOneWidget);
      expect(find.text('Fastest'), findsOneWidget);
      expect(find.text('Best price'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
    });
  });

  group('checkout', () {
    testWidgets('sends the delivery instructions with the address', (tester) async {
      phone(tester, height: 1600);
      Map<String, dynamic>? checkout;
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login')) {
          return response({'token': 't', 'user': user});
        }
        if (path.endsWith('/addresses')) return response([_address]);
        if (path.endsWith('/delivery/quote')) {
          return response({
            'options': [_option('STANDARD', 4320, 79, label: 'Standard delivery')]
          });
        }
        if (path.endsWith('/orders/checkout')) {
          checkout = jsonDecode(request.body) as Map<String, dynamic>;
          return response({'id': 'o1'});
        }
        if (path.endsWith('/auth/me')) return response(user);
        return response({}, status: 404);
      });

      await http.runWithClient(() async {
        await AppState.instance.signIn('shopper@example.com', 'pw');
        AppState.instance.addToCart(Product.fromJson(product()));
        await tester.pumpWidget(app(const CheckoutScreen()));
        await finishLoad(tester);

        final scroll = find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(find.text('Leave at the door'), 300,
            scrollable: scroll);
        await tester.tap(find.text('Leave at the door'));
        await tester.tap(find.text('Call on arrival'));
        await tester.pump();
        await tester.enterText(
            find.descendant(
              of: find.byWidgetPredicate((w) =>
                  w is BxField && w.label.startsWith('Anything else')),
              matching: find.byType(TextField),
            ),
            'Gate code 4821');
        await tester.scrollUntilVisible(find.text('Cash'), 300, scrollable: scroll);
        await tester.tap(find.text('Cash'));
        await finishLoad(tester);
        await tester.tap(find.text('Place order'));
        await finishLoad(tester);

        final sent = (checkout?['shipping_address'] as Map)['instructions'] as String;
        expect(sent, contains('Leave at the door'));
        expect(sent, contains('Call on arrival'));
        expect(sent, contains('Gate code 4821'));
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });

    testWidgets('sends no instructions when none were given', (tester) async {
      phone(tester, height: 1600);
      Map<String, dynamic>? checkout;
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login')) {
          return response({'token': 't', 'user': user});
        }
        if (path.endsWith('/addresses')) return response([_address]);
        if (path.endsWith('/delivery/quote')) {
          return response({
            'options': [_option('STANDARD', 4320, 79, label: 'Standard delivery')]
          });
        }
        if (path.endsWith('/orders/checkout')) {
          checkout = jsonDecode(request.body) as Map<String, dynamic>;
          return response({'id': 'o1'});
        }
        if (path.endsWith('/auth/me')) return response(user);
        return response({}, status: 404);
      });

      await http.runWithClient(() async {
        await AppState.instance.signIn('shopper@example.com', 'pw');
        AppState.instance.addToCart(Product.fromJson(product()));
        await tester.pumpWidget(app(const CheckoutScreen()));
        await finishLoad(tester);
        final scroll = find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(find.text('Cash'), 300, scrollable: scroll);
        await tester.tap(find.text('Cash'));
        await finishLoad(tester);
        await tester.tap(find.text('Place order'));
        await finishLoad(tester);

        expect((checkout?['shipping_address'] as Map).containsKey('instructions'), isFalse);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });
  });

  group('tracking screen', () {
    Map<String, dynamic> order(String status, {String? promised}) => {
          'id': 'o1',
          'order_number': 'BX-1',
          'status': status,
          'payment_method': 'UPI',
          'total_amount': 1048,
          'created_at': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
          'promised_by': promised ?? DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
          'shipping_address': {
            'line1': '42 Test street',
            'city': 'Delhi',
            'pincode': '110001',
            'instructions': 'Leave at the door',
          },
          'items': [
            {
              'id': 'i1',
              'product_id': 'p1',
              'quantity': 1,
              'price': 999,
              'product': {'title': 'Cotton shirt', 'images': []},
            }
          ],
        };

    MockClient server(Map<String, dynamic> orderJson, Map<String, dynamic> tracking) =>
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/delivery/orders/o1/track')) return response(tracking);
          if (path.endsWith('/orders/o1')) return response(orderJson);
          return response({}, status: 404);
        });

    Future<void> open(WidgetTester tester, MockClient client, {bool placed = false}) async {
      phone(tester, height: 1000);
      await http.runWithClient(() async {
        await tester.pumpWidget(
            app(OrderTrackingScreen(orderId: 'o1', justPlaced: placed)));
        await finishLoad(tester);
      }, () => client);
    }

    testWidgets('shows the live arrival time, the partner and the address',
        (tester) async {
      await open(
          tester,
          server(order('OUT_FOR_DELIVERY'), {
            'tracking_no': 'TRK1',
            'current_status': 'OUT_FOR_DELIVERY',
            'eta_minutes': 18,
            'courier': 'Porter',
            'rider': {'name': 'Ravi', 'phone': '9999999999'},
          }));

      expect(find.text('Arriving in 18 mins'), findsOneWidget);
      expect(find.textContaining('Ravi is nearby'), findsOneWidget);
      expect(find.text('Ravi'), findsOneWidget);
      expect(find.byTooltip('Call Ravi'), findsOneWidget);
      expect(find.textContaining('42 Test street'), findsOneWidget);
      expect(find.textContaining('Leave at the door'), findsOneWidget);
      expect(find.byType(DeliveryStages), findsOneWidget);
      expect(find.byType(DeliveryRouteMap), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('before dispatch it falls back to the checkout promise',
        (tester) async {
      await open(
          tester,
          server(order('CONFIRMED'), {
            'tracking_no': null,
            'current_status': 'CONFIRMED',
            'message': 'Not dispatched yet.',
          }));

      expect(find.textContaining('Arriving in'), findsOneWidget);
      expect(find.textContaining('Order confirmed'), findsWidgets);
      expect(find.byTooltip('Call Ravi'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a delivered order says so and stops claiming an arrival time',
        (tester) async {
      await open(tester, server(order('DELIVERED'), {'tracking_no': 'T', 'current_status': 'DELIVERED'}));

      expect(find.text('Delivered'), findsWidgets);
      expect(find.textContaining('Arriving'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a cancelled order shows as cancelled', (tester) async {
      await open(tester, server(order('CANCELLED'), {'tracking_no': null, 'current_status': 'CANCELLED'}));

      expect(find.text('This order was cancelled.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('straight after checkout it confirms the order', (tester) async {
      await open(
          tester,
          server(order('CONFIRMED'), {'tracking_no': null, 'current_status': 'CONFIRMED'}),
          placed: true);

      expect(find.text('Order placed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a courier feed that fails does not blank the order', (tester) async {
      phone(tester, height: 1000);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/track')) return http.Response('boom', 500);
        return response(order('PACKED'));
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const OrderTrackingScreen(orderId: 'o1')));
        await finishLoad(tester);

        expect(find.textContaining('Packed and ready to go'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });

    testWidgets('an order that cannot be loaded offers a retry', (tester) async {
      phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const OrderTrackingScreen(orderId: 'o1')));
        await finishLoad(tester);

        expect(find.text('Could not load this order'), findsOneWidget);
        expect(find.widgetWithText(BxButton, 'Try again'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((_) async => http.Response('nope', 500)));
    });
  });

  group('small screens and large text', () {
    final signedInShop = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/login')) return response({'token': 't', 'user': user});
      if (path.endsWith('/addresses')) return response([_address]);
      if (path.endsWith('/delivery/quote')) {
        return response({
          'options': [
            _option('INSTANT', 25, 49, label: 'Instant delivery'),
            _option('STANDARD', 4320, 0, label: 'Standard delivery', free: 'Free on orders over ₹1999'),
          ]
        });
      }
      if (path.endsWith('/delivery/orders/o1/track')) {
        return response({
          'tracking_no': 'TRK1',
          'current_status': 'OUT_FOR_DELIVERY',
          'eta_minutes': 18,
          'courier': 'Porter with a rather long carrier name',
          'rider': {'name': 'Ravindranath Venkataraghavan', 'phone': '9999999999'},
        });
      }
      if (path.endsWith('/orders/o1')) {
        return response({
          'id': 'o1',
          'order_number': 'BX-1',
          'status': 'OUT_FOR_DELIVERY',
          'payment_method': 'UPI',
          'total_amount': 1048,
          'created_at': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
          'promised_by': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
          'shipping_address': {'line1': 'Flat 1204, Tower B, A very long society name', 'city': 'Delhi', 'pincode': '110001'},
          'items': [
            {'id': 'i1', 'product_id': 'p1', 'quantity': 1, 'price': 999,
             'product': {'title': 'Cotton everyday shirt with a long product name', 'images': []}}
          ],
        });
      }
      return response({}, status: 404);
    });

    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('the cart does not overflow at $width / $scale', (tester) async {
          phone(tester, width: width, height: 900);
          await http.runWithClient(() async {
            await AppState.instance.signIn('shopper@example.com', 'pw');
            final p = product();
            p['mrp'] = 1999;
            AppState.instance.addToCart(Product.fromJson(p));
            await tester.pumpWidget(app(CartScreen(onStartShopping: () {}), scale: scale));
            await finishLoad(tester);
            for (var i = 0; i < 5; i++) {
              await tester.drag(find.byType(ListView).first, const Offset(0, -400));
              await tester.pump();
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }, () => signedInShop);
        });

        testWidgets('tracking does not overflow at $width / $scale', (tester) async {
          phone(tester, width: width, height: 900);
          await http.runWithClient(() async {
            await tester.pumpWidget(app(const OrderTrackingScreen(orderId: 'o1'), scale: scale));
            await finishLoad(tester);
            expect(tester.takeException(), isNull);
            await tester.drag(find.byType(ListView).first, const Offset(0, -500));
            await tester.pump();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }, () => signedInShop);
        });
      }
    }
  });
}
