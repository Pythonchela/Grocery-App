import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/seller/seller_models.dart';

import 'support.dart';

/// Packing and shipping from the Orders tab: the seller's day-to-day job.
///
/// The screens are driven against a fake API that follows the server's stage
/// rules, so a line moves between tabs the way it does live.
void main() {
  SellerOrderItem line({
    String id = 'i1',
    String fulfilment = 'PENDING',
    String order = 'CONFIRMED',
    String title = 'Brass Lamp',
    String number = 'ORD-AAA11111',
    String? courier,
    String? tracking,
  }) =>
      SellerOrderItem(
        id: id, title: title, quantity: 1, price: 1000, earning: 900, orderNumber: number,
        orderStatus: order, fulfilmentStatus: fulfilment, courier: courier, trackingNo: tracking,
        shipToName: 'Priya', shipToCity: 'Bengaluru', shipToPincode: '560038',
      );

  FakeSellerApi seller(List<SellerOrderItem> rows) =>
      FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))..orderRows = rows;

  Finder stage(String label) => find.descendant(of: find.byType(BxTabs), matching: find.text(label));

  Future<void> openOrders(WidgetTester tester, FakeSellerApi api) async {
    await pumpSeller(tester, sellerApp(api));
    await tapAndSettle(tester, nav('Orders'));
  }

  Finder sheetButton(String label) => find.widgetWithText(BxButton, label);

  group('what each line offers', () {
    testWidgets('a line waiting to be packed offers both packing and shipping', (tester) async {
      await openOrders(tester, seller([line()]));

      expect(find.text('Mark packed'), findsOneWidget);
      expect(find.text('Mark shipped'), findsOneWidget);
      expect(find.text('To pack'), findsWidgets);
    });

    testWidgets('a packed line offers shipping only', (tester) async {
      await openOrders(tester, seller([line(fulfilment: 'PACKED')]));
      await tapAndSettle(tester, stage('Packed'));

      expect(find.text('Mark packed'), findsNothing);
      expect(find.text('Mark shipped'), findsOneWidget);
    });

    testWidgets('a shipped line shows the courier and tracking and offers a correction', (tester) async {
      await openOrders(tester, seller([line(fulfilment: 'SHIPPED', courier: 'Delhivery', tracking: 'DL123')]));
      await tapAndSettle(tester, stage('Shipped'));

      expect(find.text('Delhivery'), findsOneWidget);
      expect(find.text('DL123'), findsOneWidget);
      expect(find.text('Edit tracking'), findsOneWidget);
      expect(find.text('Mark packed'), findsNothing);
    });

    testWidgets('once the order is out for delivery the tracking is read-only', (tester) async {
      await openOrders(tester, seller([line(fulfilment: 'SHIPPED', order: 'OUT_FOR_DELIVERY', courier: 'Delhivery', tracking: 'DL123')]));
      await tapAndSettle(tester, stage('Shipped'));

      expect(find.text('DL123'), findsOneWidget);
      expect(find.text('Edit tracking'), findsNothing);
      expect(find.text('Out for delivery'), findsOneWidget);
    });

    testWidgets('delivered and cancelled lines offer no actions', (tester) async {
      await openOrders(tester, seller([
        line(id: 'd', order: 'DELIVERED', fulfilment: 'SHIPPED', title: 'Delivered Thing', courier: 'X', tracking: 'T1'),
        line(id: 'c', order: 'CANCELLED', title: 'Cancelled Thing'),
      ]));

      await tapAndSettle(tester, stage('Delivered'));
      expect(find.text('Delivered Thing'), findsOneWidget);
      expect(find.text('Edit tracking'), findsNothing);
      expect(find.text('Mark shipped'), findsNothing);

      await tapAndSettle(tester, stage('Cancelled'));
      expect(find.text('Cancelled Thing'), findsOneWidget);
      expect(find.text('Mark packed'), findsNothing);
      expect(find.text('Mark shipped'), findsNothing);
    });
  });

  group('packing', () {
    testWidgets('marking a line packed calls the API and moves it to Packed', (tester) async {
      final api = seller([line()]);
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark packed'));

      expect(api.calls, contains('pack:i1'));
      expect(find.text('Marked as packed.'), findsOneWidget);
      expect(find.text('Nothing to pack'), findsOneWidget, reason: 'it left the To pack list');

      await tapAndSettle(tester, stage('Packed'));
      expect(find.text('Brass Lamp'), findsOneWidget);
      expect(find.text('Mark packed'), findsNothing);
      expect(find.text('Mark shipped'), findsOneWidget);
    });

    testWidgets('if the server refuses (order cancelled meanwhile) the seller is told and the list refreshes', (tester) async {
      final api = seller([line()])
        ..fulfilmentError = ApiException(422, 'This order was cancelled, so there is nothing to pack or ship.',
            errors: {'fulfilment': ['This order was cancelled, so there is nothing to pack or ship.']});
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark packed'));

      expect(find.text('This order was cancelled, so there is nothing to pack or ship.'), findsOneWidget);
      expect(find.text('Marked as packed.'), findsNothing);
    });
  });

  group('shipping', () {
    testWidgets('by default one tap books the courier, with nothing to type', (tester) async {
      final api = seller([line()]);
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      expect(find.text('Ready for pickup'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'no courier or tracking number to type');
      expect(find.textContaining('book the courier for you'), findsOneWidget);

      await tapAndSettle(tester, sheetButton('Book courier'));

      expect(api.calls, contains('ship:i1:auto:auto'));
      expect(find.text('Marked as shipped.'), findsOneWidget);

      await tapAndSettle(tester, stage('Shipped'));
      expect(find.text('Delhivery Surface'), findsOneWidget, reason: 'the booking supplied the courier');
      expect(find.text('AWB-AUTO-1'), findsOneWidget, reason: 'and the tracking number');
    });

    testWidgets('if the courier cannot be booked the seller is told why and can enter it themselves', (tester) async {
      final api = seller([line()])
        ..fulfilmentError = ApiException(422, 'x', errors: {
          'fulfilment': ['The courier could not be booked automatically (Shiprocket could not assign a courier: wallet balance too low). You can enter the courier and tracking number yourself.']
        });
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, sheetButton('Book courier'));

      expect(find.textContaining('wallet balance too low'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2), reason: 'the form opened so they can carry on');
      expect(find.text('Marked as shipped.'), findsNothing);
    });

    testWidgets('with automatic booking switched off the form opens asking for the details', (tester) async {
      final api = seller([line()])
        ..fulfilmentError = ApiException(422, 'x', errors: {
          'courier': ['Choose or enter the courier.'],
          'tracking_no': ['Enter the tracking number.'],
        });
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, sheetButton('Book courier'));

      expect(find.text('Choose or enter the courier.'), findsOneWidget);
      expect(find.text('Enter the tracking number.'), findsOneWidget);
    });

    testWidgets('a seller who booked it themselves can still type the details instead', (tester) async {
      final api = seller([line()]);
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, find.text('Enter courier and tracking myself'));
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('the sheet asks for a courier and a tracking number, and sends nothing without them', (tester) async {
      final api = seller([line()]);
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, find.text('Enter courier and tracking myself'));
      expect(find.text('Mark as shipped'), findsWidgets);
      expect(find.textContaining('ORD-AAA11111'), findsWidgets);

      await tapAndSettle(tester, sheetButton('Mark as shipped'));

      expect(find.text('Choose or enter the courier.'), findsOneWidget);
      expect(find.text('Enter the tracking number.'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('ship')), isEmpty);
    });

    testWidgets('a courier can be chosen with one tap, and shipping moves the line to Shipped', (tester) async {
      final api = seller([line()]);
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, find.text('Enter courier and tracking myself'));
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Delhivery'));
      await tester.enterText(find.byType(TextField).at(1), '  DL12345  ');
      await tapAndSettle(tester, sheetButton('Mark as shipped'));

      expect(api.calls, contains('ship:i1:Delhivery:DL12345'), reason: 'tracking trimmed');
      expect(find.text('Marked as shipped.'), findsOneWidget);

      await tapAndSettle(tester, stage('Shipped'));
      expect(find.text('Delhivery'), findsOneWidget);
      expect(find.text('DL12345'), findsOneWidget);
      expect(find.text('Edit tracking'), findsOneWidget);
    });

    testWidgets('any other courier can be typed', (tester) async {
      final api = seller([line()]);
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, find.text('Enter courier and tracking myself'));
      await tester.enterText(find.byType(TextField).at(0), 'Local Express');
      await tester.enterText(find.byType(TextField).at(1), 'LE-99');
      await tapAndSettle(tester, sheetButton('Mark as shipped'));

      expect(api.calls, contains('ship:i1:Local Express:LE-99'));
    });

    testWidgets('a packed line can be shipped without being packed again', (tester) async {
      final api = seller([line(fulfilment: 'PACKED')]);
      await openOrders(tester, api);
      await tapAndSettle(tester, stage('Packed'));

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, find.text('Enter courier and tracking myself'));
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Blue Dart'));
      await tester.enterText(find.byType(TextField).at(1), 'BD1');
      await tapAndSettle(tester, sheetButton('Mark as shipped'));

      expect(api.calls, ['onboarding', 'ship:i1:Blue Dart:BD1']);
    });

    testWidgets('a tracking number can be corrected, with the current details filled in', (tester) async {
      final api = seller([line(fulfilment: 'SHIPPED', courier: 'Delhivery', tracking: 'WRONG')]);
      await openOrders(tester, api);
      await tapAndSettle(tester, stage('Shipped'));

      await tapAndSettle(tester, find.text('Edit tracking'));

      expect(find.text('Correct tracking details'), findsOneWidget);
      expect((tester.widget<TextField>(find.byType(TextField).at(0)).controller!).text, 'Delhivery');
      expect((tester.widget<TextField>(find.byType(TextField).at(1)).controller!).text, 'WRONG');

      await tester.enterText(find.byType(TextField).at(1), 'RIGHT');
      await tapAndSettle(tester, sheetButton('Save changes'));

      expect(api.calls, contains('ship:i1:Delhivery:RIGHT'));
      expect(find.text('Tracking details updated.'), findsOneWidget);
      expect(find.text('RIGHT'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown in the sheet, which stays open', (tester) async {
      final api = seller([line(fulfilment: 'SHIPPED', courier: 'Delhivery', tracking: 'T1')])
        ..fulfilmentError = ApiException(422, 'This order is already out for delivery, so the tracking details can no longer be changed.',
            errors: {'fulfilment': ['This order is already out for delivery, so the tracking details can no longer be changed.']});
      await openOrders(tester, api);
      await tapAndSettle(tester, stage('Shipped'));

      await tapAndSettle(tester, find.text('Edit tracking'));
      await tapAndSettle(tester, sheetButton('Save changes'));

      expect(find.textContaining('already out for delivery'), findsOneWidget);
      expect(find.text('Correct tracking details'), findsOneWidget, reason: 'the sheet is still there to read');
    });

    testWidgets('a field error from the server appears under its field', (tester) async {
      final api = seller([line()])
        ..fulfilmentError = ApiException(422, 'The tracking no field is too long.',
            errors: {'tracking_no': ['That tracking number is not accepted.']});
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, find.text('Enter courier and tracking myself'));
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'DTDC'));
      await tester.enterText(find.byType(TextField).at(1), 'BADNUMBER');
      await tapAndSettle(tester, sheetButton('Mark as shipped'));

      expect(find.text('That tracking number is not accepted.'), findsOneWidget);
    });

    testWidgets('over-long entries are caught before any request', (tester) async {
      final api = seller([line()]);
      await openOrders(tester, api);

      await tapAndSettle(tester, find.text('Mark shipped'));
      await tapAndSettle(tester, find.text('Enter courier and tracking myself'));
      await tester.enterText(find.byType(TextField).at(0), 'x' * 81);
      await tester.enterText(find.byType(TextField).at(1), 'y' * 81);
      await tapAndSettle(tester, sheetButton('Mark as shipped'));

      expect(find.text('That name is too long.'), findsOneWidget);
      expect(find.text('That tracking number is too long.'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('ship')), isEmpty);
    });
  });

  group('the overview follows', () {
    testWidgets('the "To pack" count drops after an item is packed', (tester) async {
      final api = seller([line(), line(id: 'i2', number: 'ORD-BBB22222', title: 'Second')]);
      await pumpSeller(tester, sellerApp(api));

      expect(find.text('2'), findsOneWidget, reason: 'two lines to pack');

      await tapAndSettle(tester, nav('Orders'));
      await tapAndSettle(tester, find.text('Mark packed').first);
      await tapAndSettle(tester, nav('Overview'));

      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsNothing);
    });
  });

  group('small screens', () {
    testWidgets('the order cards and the shipping sheet do not overflow at 320px', (tester) async {
      final api = seller([
        line(title: 'A rather long product title that needs to wrap onto more than one line', fulfilment: 'SHIPPED', order: 'OUT_FOR_DELIVERY', courier: 'India Post Speed Post', tracking: 'AB123456789IN'),
        line(id: 'i2', title: 'Another very long product title for the second line item'),
      ]);
      // Narrow, but tall enough that nothing has to scroll: this is about width.
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(sellerApp(api));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, nav('Orders'));

      await tapAndSettle(tester, find.text('Mark shipped'));
      // Both views must fit: the one-tap booking, then the typed-in form.
      await tapAndSettle(tester, find.text('Enter courier and tracking myself'));
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Delhivery'));
    });
  });
}
