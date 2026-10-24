import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/design/theme.dart';
import 'package:marketplace_app/seller/screens/order_desk.dart';
import 'package:marketplace_app/seller/seller_area.dart';
import 'package:marketplace_app/seller/seller_host.dart';
import 'package:marketplace_app/seller/seller_models.dart';

import 'support.dart';

/// The order desk: a new order waits for the shop to accept or decline it.
void main() {
  SellerOrderItem line({
    String id = 'i1',
    String response = 'ACCEPTED',
    String fulfilment = 'PENDING',
    String order = 'CONFIRMED',
    String title = 'Brass Lamp',
    DateTime? acceptBy,
    DateTime? readyBy,
    String payment = 'COD',
  }) =>
      SellerOrderItem(
        id: id, title: title, quantity: 1, price: 1000, earning: 900, orderNumber: 'ORD-AAA11111',
        orderStatus: order, fulfilmentStatus: fulfilment, sellerResponse: response,
        acceptBy: acceptBy, readyBy: readyBy, paymentMethod: payment,
        shipToName: 'Priya', shipToCity: 'Bengaluru', shipToPincode: '560038',
      );

  FakeSellerApi seller(List<SellerOrderItem> rows) =>
      FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))..orderRows = rows;

  Finder stage(String label) => find.descendant(of: find.byType(BxTabs), matching: find.text(label));

  Future<void> openNew(WidgetTester tester, FakeSellerApi api) async {
    await pumpSeller(tester, sellerApp(api));
    await tapAndSettle(tester, nav('Orders'));
    await tapAndSettle(tester, stage('New'));
  }

  group('model', () {
    test('a line waiting for an answer cannot be packed or shipped yet', () {
      final pending = line(response: 'PENDING');
      expect(pending.awaitingAnswer, isTrue);
      expect(pending.canPack, isFalse);
      expect(pending.canShip, isFalse);
      expect(pending.canCancel, isFalse);
    });

    test('an accepted line can be packed, shipped, or cancelled; a shipped one cannot be cancelled', () {
      expect(line().canPack, isTrue);
      expect(line().canCancel, isTrue);
      expect(line(fulfilment: 'SHIPPED').canCancel, isFalse);
      expect(line(response: 'REJECTED', fulfilment: 'CANCELLED').canCancel, isFalse);
    });

    test('a line past its promised time is late', () {
      expect(line(readyBy: DateTime.now().subtract(const Duration(minutes: 5))).isLate, isTrue);
      expect(line(readyBy: DateTime.now().add(const Duration(minutes: 5))).isLate, isFalse);
    });
  });

  group('new orders', () {
    testWidgets('shows the countdown, payment and accept / decline', (tester) async {
      final api = seller([line(response: 'PENDING', acceptBy: DateTime.now().add(const Duration(minutes: 10)))]);
      await openNew(tester, api);

      expect(find.text('Brass Lamp'), findsOneWidget);
      expect(find.byKey(const Key('desk-countdown')), findsOneWidget);
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('Mark packed'), findsNothing);
    });

    testWidgets('accepting asks how long it will take, then moves the order to To pack', (tester) async {
      final api = seller([line(response: 'PENDING', acceptBy: DateTime.now().add(const Duration(minutes: 10)))]);
      await openNew(tester, api);

      await tapAndSettle(tester, find.text('Accept'));
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, '30 min'));
      await tapAndSettle(tester, find.widgetWithText(BxButton, 'Accept order'));

      expect(api.calls, contains('accept:i1:30'));
      expect(find.text('Brass Lamp'), findsNothing);

      await tapAndSettle(tester, stage('To pack'));
      expect(find.text('Brass Lamp'), findsOneWidget);
      expect(find.text('Mark packed'), findsOneWidget);
    });

    testWidgets('declining asks for a reason and sends it', (tester) async {
      final api = seller([line(response: 'PENDING', acceptBy: DateTime.now().add(const Duration(minutes: 10)))]);
      await openNew(tester, api);

      await tapAndSettle(tester, find.text('Decline'));
      await tapAndSettle(tester, find.text('Item is damaged'));
      await tapAndSettle(tester, find.widgetWithText(BxButton, 'Decline order'));

      expect(api.calls, contains('reject:i1:DAMAGED'));
      expect(find.text('Brass Lamp'), findsNothing);
    });

    testWidgets('an unanswered order is not packable and the New tab says when it is empty', (tester) async {
      final api = seller([line()]);
      await openNew(tester, api);

      expect(find.text('No orders waiting'), findsOneWidget);
    });
  });

  group('accepted orders', () {
    testWidgets('can be cancelled before they ship, with a reason', (tester) async {
      final api = seller([line(readyBy: DateTime.now().add(const Duration(minutes: 20)))]);
      await pumpSeller(tester, sellerApp(api));
      await tapAndSettle(tester, nav('Orders'));

      expect(find.text('Cancel order'), findsOneWidget);
      await tapAndSettle(tester, find.text('Cancel order'));
      await tapAndSettle(tester, find.text('Shop is closed'));
      await tapAndSettle(tester, find.widgetWithText(BxButton, 'Cancel order').last);

      expect(api.calls, contains('reject:i1:SHOP_CLOSED'));
    });
  });

  group('dashboard', () {
    testWidgets('shows a banner for orders waiting and opens them', (tester) async {
      final api = seller([line(response: 'PENDING', acceptBy: DateTime.now().add(const Duration(minutes: 10)))]);
      await pumpSeller(tester, sellerApp(api));

      expect(find.byKey(const Key('new-orders-banner')), findsOneWidget);
      expect(find.textContaining('1 new order waiting'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('new-orders-banner')));
      expect(find.text('Accept'), findsOneWidget);
    });

    testWidgets('no banner when nothing is waiting', (tester) async {
      await pumpSeller(tester, sellerApp(seller([line()])));
      expect(find.byKey(const Key('new-orders-banner')), findsNothing);
    });
  });

  deskVisibilityTests();

  test('every decline reason the app offers is one the server accepts', () {
    expect(deskDeclineReasons.map((r) => r.$1).toSet(),
        {'OUT_OF_STOCK', 'SHOP_CLOSED', 'CANNOT_PREPARE', 'DAMAGED', 'OTHER'});
  });
}

/// While the order desk is open the app keeps its own pop-ups away from it (they
/// would cover Accept and Decline, and "View" would lead the seller out of the
/// screen); the host is told when the desk opens and closes.
void deskVisibilityTests() {
  testWidgets('the host is told when the order desk opens and closes', (tester) async {
    final log = <bool>[];
    final host = SellerHost(
      token: () => 'test-token',
      onSignOut: () {},
      marketplaceName: 'BazaarX',
      onDeskVisible: log.add,
    );
    final api = FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'));

    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildMaterialTheme(isDark: false),
      builder: (context, child) => DsThemeScope(isDark: false, child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SellerArea(host: host, api: api, picker: FakePicker()),
            )),
            child: const Text('Open desk'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open desk'));
    await tester.pumpAndSettle();
    expect(log, [true]);

    Navigator.of(tester.element(find.byType(SellerArea))).pop();
    await tester.pumpAndSettle();
    expect(log, [true, false]);
  });
}
