import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/store_config.dart';
import 'package:marketplace_app/data/vendor_app_link.dart';
import 'package:marketplace_app/screens/account_screen.dart';
import 'package:marketplace_app/state/app_state.dart';

import 'support.dart';

const hybrid = StoreConfig(
  mode: 'hybrid',
  vendorsEnabled: true,
  houseVisible: true,
  shopsFirst: false,
  showsShops: true,
  oneShopPerCart: true,
);

const single = StoreConfig(
  mode: 'single', vendorsEnabled: false, houseVisible: true,
  shopsFirst: false, showsShops: false, oneShopPerCart: false,
  storeName: 'My Store',
);

/// Selling is its own app. The shopping app only points to it.
void main() {
  setUp(() {
    resetState();
    VendorAppLink.open = () async => true;
  });

  final requests = <String>[];

  /// The account screen for a signed-in [role] in a store of kind [config].
  Future<void> accountAs(WidgetTester tester, StoreConfig config, {String role = 'CUSTOMER'}) async {
    phone(tester, height: 2200);
    requests.clear();
    AppState.instance.useStoreConfig(config);
    await http.runWithClient(() async {
      await AppState.instance.signIn('s@example.com', 'pw');
      await tester.pumpWidget(app(const AccountScreen()));
      await finishLoad(tester);
    }, () => MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path.endsWith('/auth/login')) return response({'token': 't', 'user': {...user, 'role': role}});
          if (request.url.path.endsWith('/auth/me')) return response({...user, 'role': role});
          return response([]);
        }));
    await tester.pumpAndSettle();
  }

  group('the link to the seller app in the account menu', () {
    testWidgets('a shopper in a marketplace is invited to sell, in the seller app', (tester) async {
      await accountAs(tester, hybrid);

      expect(find.textContaining('Sell on'), findsOneWidget);
      expect(find.textContaining('Seller app'), findsOneWidget);
    });

    testWidgets('tapping it opens the seller app, not a screen inside this one', (tester) async {
      var opened = 0;
      await accountAs(tester, hybrid);
      VendorAppLink.open = () async {
        opened++;
        return true;
      };

      await tester.tap(find.byKey(const Key('vendor-app-link')));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('if the store cannot be opened, it says so', (tester) async {
      await accountAs(tester, hybrid);
      VendorAppLink.open = () async => false;

      await tester.tap(find.byKey(const Key('vendor-app-link')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not open the store'), findsOneWidget);
    });

    testWidgets('the owner of a single-business store is told to manage it there', (tester) async {
      await accountAs(tester, single, role: 'ADMIN');

      expect(find.text('Manage store'), findsOneWidget);
      expect(find.textContaining('Sell on'), findsNothing);
    });

    testWidgets('a single-business store has nothing to sell on for a shopper', (tester) async {
      await accountAs(tester, single);

      expect(find.byKey(const Key('vendor-app-link')), findsNothing);
    });

    testWidgets('this app never asks the seller API where an account stands', (tester) async {
      await accountAs(tester, hybrid);

      expect(requests.where((p) => p.contains('/seller')), isEmpty);
    });
  });
}
