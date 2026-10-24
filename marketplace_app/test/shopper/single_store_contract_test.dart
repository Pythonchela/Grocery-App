import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/store_config.dart';
import 'package:marketplace_app/main.dart' show AppShell;
import 'package:marketplace_app/state/app_state.dart';

import 'support.dart';

/// A store that sells only its own goods must show a shopper no trace of vendors,
/// on any screen. The tabs are walked one by one and the screen is searched for
/// the words that give vendors away, so a new screen that forgets to ask the store
/// what it is fails here instead of on a client's phone.
void main() {
  setUp(resetState);

  const single = StoreConfig(
    mode: 'single',
    vendorsEnabled: false,
    houseVisible: true,
    shopsFirst: false,
    showsShops: false,
    homeShowsShops: false,
    oneShopPerCart: false,
    storeName: 'My Store',
  );

  /// What gives a vendor away. "Sold by" is not here: it is only drawn when the store shows shops.
  final vendorWords = [
    'Sell on',
    'Seller app',
    'Shops near you',
    'Order from a shop',
    'All shops',
    'vendor',
    'Vendor',
  ];

  void expectNoVendors(String screen) {
    for (final word in vendorWords) {
      expect(find.textContaining(word), findsNothing, reason: '"$word" appears on $screen of a single-business store');
    }
  }

  testWidgets('no tab of a single-business store mentions vendors', (tester) async {
    phone(tester, width: 430, height: 2200);
    AppState.instance.useStoreConfig(single);

    await http.runWithClient(() async {
      await AppState.instance.signIn('s@example.com', 'pw');
      await tester.pumpWidget(app(const AppShell()));
      await finishLoad(tester);
      expectNoVendors('the home screen');

      for (final tab in ['Categories', 'Cart', 'Orders', 'Account']) {
        await tester.tap(find.byTooltip(tab));
        await finishLoad(tester);
        expectNoVendors('the $tab tab');
      }
    }, () => MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/auth/login')) return response({'token': 't', 'user': user});
          if (path.endsWith('/categories')) return response(categories);
          if (path.endsWith('/shops')) return response([]);
          return response([product()]);
        }));
  });

  testWidgets('the same store, as staff, is offered its own shop, not a seller application', (tester) async {
    phone(tester, width: 430, height: 2200);
    AppState.instance.useStoreConfig(single);

    await http.runWithClient(() async {
      await AppState.instance.signIn('admin@example.com', 'pw');
      await tester.pumpWidget(app(const AppShell()));
      await finishLoad(tester);
      await tester.tap(find.byTooltip('Account'));
      await finishLoad(tester);

      expect(find.text('Manage store'), findsOneWidget);
      expect(find.textContaining('Sell on'), findsNothing);
    }, () => MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/auth/login')) return response({'token': 't', 'user': {...user, 'role': 'ADMIN'}});
          if (path.endsWith('/categories')) return response(categories);
          return response([product()]);
        }));
  });
}
