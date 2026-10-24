import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/design/theme.dart';
import 'package:marketplace_app/seller/seller_area.dart';
import 'package:marketplace_app/seller/seller_host.dart';

import 'support.dart';

/// The seller's menu: the same groups as the website's sidebar, one tap from anywhere.
void main() {
  var switched = 0;
  var signedOut = 0;

  setUp(() {
    switched = 0;
    signedOut = 0;
  });

  Widget app(FakeSellerApi api) => MaterialApp(
        theme: buildMaterialTheme(isDark: false),
        builder: (context, child) => DsThemeScope(isDark: false, child: child ?? const SizedBox.shrink()),
        home: SellerArea(
          host: SellerHost(
            token: () => 'test-token',
            onSignOut: () => signedOut++,
            onSwitchToShopping: () => switched++,
            marketplaceName: 'BazaarX',
            supportEmail: 'support@bazaarx.in',
          ),
          api: api,
          picker: FakePicker(),
        ),
      );

  Future<http.Response> server(http.Request request) async =>
      http.Response('{"data": []}', 200, headers: {'content-type': 'application/json'});

  Future<void> open(WidgetTester tester) async {
    await pumpSeller(tester, app(FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
  }

  testWidgets('the menu lists every part of the shop, in groups', (tester) async {
    await http.runWithClient(() async {
      await open(tester);

      for (final label in ['ORDERS', 'CATALOGUE', 'CUSTOMERS', 'MONEY', 'SHOP']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final key in [
        'today', 'insights', 'new-orders', 'orders', 'returns', 'products', 'bulk-import', 'offers',
        'reviews', 'earnings', 'my-shop', 'help', 'shop-as-customer', 'sign-out',
      ]) {
        expect(find.byKey(Key('menu-$key')), findsOneWidget, reason: key);
      }
    }, () => MockClient(server));
  });

  testWidgets('an item takes the seller there and closes the menu', (tester) async {
    await http.runWithClient(() async {
      await open(tester);

      await tester.tap(find.byKey(const Key('menu-earnings')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('seller-menu')), findsNothing);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 3);
    }, () => MockClient(server));
  });

  testWidgets('Returns opens the More tab on its Returns section', (tester) async {
    await http.runWithClient(() async {
      await open(tester);

      await tester.tap(find.byKey(const Key('menu-returns')));
      await tester.pumpAndSettle();

      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 4);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Returns')).selected, isTrue);
    }, () => MockClient(server));
  });

  testWidgets('asking for another section while More is open switches it', (tester) async {
    await http.runWithClient(() async {
      await open(tester);
      await tester.tap(find.byKey(const Key('menu-returns')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-offers')));
      await tester.pumpAndSettle();

      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Offers')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Returns')).selected, isFalse);
    }, () => MockClient(server));
  });

  testWidgets('My shop, Bulk import and Help each open their own screen', (tester) async {
    await http.runWithClient(() async {
      for (final (key, title) in [('my-shop', 'Shop page'), ('bulk-import', 'Bulk import'), ('help', 'Help & support')]) {
        await open(tester);
        await tester.tap(find.byKey(Key('menu-$key')));
        await tester.pumpAndSettle();

        expect(find.text(title), findsWidgets, reason: key);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    }, () => MockClient(server));
  });

  testWidgets('Shop as a customer and Sign out reach the app', (tester) async {
    await http.runWithClient(() async {
      await open(tester);
      await tester.tap(find.byKey(const Key('menu-shop-as-customer')));
      await tester.pumpAndSettle();
      expect(switched, 1);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-sign-out')));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    }, () => MockClient(server));
  });
}
