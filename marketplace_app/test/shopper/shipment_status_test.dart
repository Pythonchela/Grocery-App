import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/screens/order_tracking_screen.dart';
import 'package:marketplace_app/widgets/delivery_route.dart';
import 'package:marketplace_app/widgets/shipment_status_view.dart';

import 'support.dart';

/// Slow deliveries show where the parcel is and when it is due, not a map.
void main() {
  setUp(resetState);

  Map<String, dynamic> order(String status, {String mode = 'status_updates', int days = 3}) => {
        'id': 'o1',
        'order_number': 'BX-7',
        'status': status,
        'payment_method': 'UPI',
        'total_amount': 1048,
        'tracking_mode': mode,
        'created_at': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
        'promised_by': DateTime.now().add(Duration(days: days)).toIso8601String(),
        'shipping_address': {'line1': '42 Test street', 'city': 'Delhi', 'pincode': '110001'},
        'items': [
          {
            'id': 'i1',
            'product_id': 'p1',
            'quantity': 2,
            'price': 499,
            'product': {'title': 'Cotton shirt', 'images': []},
          }
        ],
      };

  Map<String, dynamic> tracking({String status = 'IN_TRANSIT', List<Map<String, dynamic>>? events, String? description}) => {
        'mode': 'status_updates',
        'status': status,
        'status_label': status == 'DELAYED' ? 'Delayed' : 'In transit',
        'tracking_no': 'AWB123',
        'courier': 'Delhivery',
        'carrier_label': 'Delhivery',
        'track_url': 'https://www.delhivery.com/track/package/AWB123',
        'expected_by': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        'events': events ??
            [
              {'status': 'IN_TRANSIT', 'label': 'In transit', 'description': description, 'location': 'Mumbai Hub', 'at': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String()},
              {'status': 'PICKED_UP', 'label': 'Picked up by courier', 'location': 'Bengaluru', 'at': DateTime.now().subtract(const Duration(hours: 4)).toIso8601String()},
              {'status': 'CONFIRMED', 'label': 'Order confirmed', 'location': null, 'at': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String()},
            ],
      };

  MockClient server(Map<String, dynamic> orderJson, Map<String, dynamic>? track) =>
      MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/delivery/orders/o1/track')) {
          return track == null ? response({}, status: 500) : response(track);
        }
        if (path.endsWith('/orders/o1')) return response(orderJson);
        return response({}, status: 404);
      });

  Future<void> open(WidgetTester tester, MockClient client, {double width = 390, double scale = 1}) async {
    phone(tester, width: width, height: 1000);
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const OrderTrackingScreen(orderId: 'o1'), scale: scale));
      await finishLoad(tester);
    }, () => client);
  }

  testWidgets('a parcel in transit shows its timeline and a due date, not a map', (tester) async {
    await open(tester, server(order('SHIPPED'), tracking()));

    expect(find.byType(DeliveryRouteMap), findsNothing);
    expect(find.byType(ShipmentStatusView), findsOneWidget);
    expect(find.textContaining('Arriving by'), findsOneWidget);
    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Mumbai Hub'), findsNWidgets(2)); // last seen + the timeline step
    expect(find.text('Picked up by courier'), findsOneWidget);
    expect(find.text('Order confirmed'), findsOneWidget);
    expect(find.byType(DeliveryStages), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('says who is carrying it and offers their own tracking page', (tester) async {
    await open(tester, server(order('SHIPPED'), tracking()));
    await tester.scrollUntilVisible(find.textContaining('Tracking no. AWB123'), 200,
        scrollable: find.byType(Scrollable).first);

    expect(find.textContaining('Tracking no. AWB123'), findsOneWidget);
    expect(find.text('Track on Delhivery'), findsOneWidget);
    expect(find.byTooltip('Copy tracking number'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a delay is called out, with the courier\'s words', (tester) async {
    await open(
        tester,
        server(order('SHIPPED'), tracking(status: 'DELAYED', description: 'Held due to heavy rain')));

    expect(find.text('Delayed'), findsWidgets);
    expect(find.text('Held due to heavy rain'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('before dispatch there is a friendly line instead of an empty list', (tester) async {
    await open(tester, server(order('CONFIRMED'), tracking(events: const [])));

    expect(find.textContaining('Updates appear here'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the order record alone picks the view when tracking is unreachable', (tester) async {
    await open(tester, server(order('SHIPPED'), null));

    expect(find.byType(DeliveryRouteMap), findsNothing);
    expect(find.byType(ShipmentStatusView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a fast rider delivery still gets the live map', (tester) async {
    await open(
        tester,
        server(order('OUT_FOR_DELIVERY', mode: 'live_map', days: 0), {
          'mode': 'live_map',
          'tracking_no': 'T',
          'current_status': 'OUT_FOR_DELIVERY',
          'eta_minutes': 18,
        }));

    expect(find.byType(DeliveryRouteMap), findsOneWidget);
    expect(find.byType(ShipmentStatusView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('delivered shows as delivered, with no "last seen"', (tester) async {
    await open(tester, server(order('DELIVERED'), tracking(status: 'DELIVERED')));

    expect(find.text('Delivered'), findsWidgets);
    expect(find.text('Last seen'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('tracking JSON is read into events', () {
    final info = TrackingInfo.fromJson(tracking());
    expect(info.showsMap, isFalse);
    expect(info.events.first.label, 'In transit');
    expect(info.events.first.location, 'Mumbai Hub');
    expect(info.trackUrl, contains('AWB123'));
    expect(TrackingInfo.fromJson({'current_status': 'X'}).showsMap, isTrue);
  });

  for (final (width, scale) in [(320.0, 1.0), (360.0, 1.5), (390.0, 2.0)]) {
    testWidgets('status view does not overflow at $width / $scale', (tester) async {
      await open(tester, server(order('SHIPPED'), tracking()), width: width, scale: scale);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
