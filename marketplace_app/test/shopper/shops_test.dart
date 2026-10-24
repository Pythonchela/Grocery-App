import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/data/shop.dart';
import 'package:marketplace_app/data/store_config.dart';
import 'package:marketplace_app/screens/account_screen.dart';
import 'package:marketplace_app/screens/cart_screen.dart';
import 'package:marketplace_app/screens/home_screen.dart';
import 'package:marketplace_app/screens/shop_screen.dart';
import 'package:marketplace_app/screens/shops_screen.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/product_add_control.dart';
import 'package:marketplace_app/widgets/shop_card.dart';
import 'package:marketplace_app/widgets/shop_switch.dart';

import 'support.dart';

const multi = StoreConfig(
  mode: 'multi',
  vendorsEnabled: true,
  houseVisible: false,
  shopsFirst: true,
  showsShops: true,
  oneShopPerCart: true,
);

const hybrid = StoreConfig(
  mode: 'hybrid',
  vendorsEnabled: true,
  houseVisible: true,
  shopsFirst: false,
  showsShops: true,
  oneShopPerCart: true,
);

const single = StoreConfig(
  mode: 'single',
  vendorsEnabled: false,
  houseVisible: true,
  shopsFirst: false,
  showsShops: false,
  oneShopPerCart: false,
);

Map<String, dynamic> shopJson(String id, String name, {Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'name': name,
      'slug': name.toLowerCase().replaceAll(' ', '-'),
      'is_open': true,
      'min_order_amount': 0,
      'rating': 0,
      'reviews_count': 0,
      'product_count': 3,
      'categories': ['Groceries'],
      ...extra,
    };

/// An item sold by a shop.
Product itemOf(String id, String title, String shopId, String shopName,
        {int price = 100, String category = 'Groceries'}) =>
    Product.fromJson({
      ...product(id: id),
      'title': title,
      'price': price,
      'mrp': price,
      'variants': [
        {'id': 'v-$id', 'color': 'Std', 'size': 'One', 'price': price, 'stock': 20},
      ],
      'category': {'name': category},
      'seller': {'id': shopId, 'display_name': shopName, 'slug': shopName.toLowerCase().replaceAll(' ', '-')},
    });

Map<String, dynamic> itemJson(String id, String title, String shopId, String shopName,
        {int price = 100, String category = 'Groceries'}) =>
    {
      ...product(id: id),
      'title': title,
      'price': price,
      'mrp': price,
      'category': {'name': category},
      'seller': {'id': shopId, 'display_name': shopName, 'slug': shopName.toLowerCase().replaceAll(' ', '-')},
    };

void main() {
  setUp(resetState);

  group('what kind of store this is', () {
    test('is read from the server\'s answer', () {
      final cfg = StoreConfig.fromJson({
        'mode': 'multi', 'vendors_enabled': true, 'house_visible': false, 'shops_first': true,
        'shows_shops': true, 'one_shop_per_cart': true, 'store_name': 'BazaarX',
      });

      expect(cfg.mode, 'multi');
      expect(cfg.shopsFirst, isTrue);
      expect(cfg.houseVisible, isFalse);
      expect(cfg.oneShopPerCart, isTrue);
      expect(cfg.storeName, 'BazaarX');
    });

    test('until the server answers, or when it cannot, nothing about the app changes', () {
      expect(StoreConfig.fallback.showsShops, isFalse);
      expect(StoreConfig.fallback.shopsFirst, isFalse);
      expect(StoreConfig.fallback.oneShopPerCart, isFalse);
      expect(StoreConfig.fallback.vendorsEnabled, isTrue);
      expect(AppState.instance.storeConfig.showsShops, isFalse);
    });

    test('survives a round trip, which is how it is remembered between launches', () {
      final again = StoreConfig.fromJson(multi.toJson());

      expect(again.mode, 'multi');
      expect(again.shopsFirst, isTrue);
      expect(again.oneShopPerCart, isTrue);
    });
  });

  group('a shop', () {
    test('reads what the API gives', () {
      final shop = Shop.fromJson(shopJson('s1', 'Sharma Kirana', extra: {
        'tagline': 'Fresh every morning', 'prep_minutes': 20, 'min_order_amount': 149,
        'rating': 4.2, 'reviews_count': 18, 'is_open': false, 'closed_text': 'Opens tomorrow at 9:00 AM',
        'opening_hours': {'mon': {'open': '09:00', 'close': '21:00'}, 'tue': null},
        'service_pincodes': ['560038'],
      }));

      expect(shop.name, 'Sharma Kirana');
      expect(shop.subtitle, 'Fresh every morning');
      expect(shop.isOpen, isFalse);
      expect(shop.closedText, 'Opens tomorrow at 9:00 AM');
      expect(shop.metaLine(formatMoney), '20 mins · Min ₹149');
      expect(shop.servicePincodes, ['560038']);
    });

    test('says what it sells when it has no tagline', () {
      final shop = Shop.fromJson(shopJson('s1', 'Fresh Mart', extra: {'categories': ['Groceries', 'Dairy']}));

      expect(shop.subtitle, 'Groceries · Dairy');
    });

    test('the week is shown in 12-hour time, with closed days named', () {
      final shop = Shop.fromJson(shopJson('s1', 'X', extra: {
        'opening_hours': {'mon': {'open': '09:00', 'close': '21:30'}, 'tue': null, 'wed': {'open': '00:00', 'close': '12:00'}},
      }));

      final lines = Map.fromEntries(shop.hoursLines.map((l) => MapEntry(l.$1, l.$2)));
      expect(lines['Monday'], '9:00 AM – 9:30 PM');
      expect(lines['Tuesday'], 'Closed');
      expect(lines['Wednesday'], '12:00 AM – 12:00 PM');
      expect(shop.hoursLines, hasLength(7));
    });

    test('a shop with no hours is always open and lists none', () {
      expect(Shop.fromJson(shopJson('s1', 'X')).hoursLines, isEmpty);
    });

    test('a product knows which shop it is from', () {
      final p = itemOf('p1', 'Milk', 's1', 'Sharma Kirana');

      expect(p.shopId, 's1');
      expect(p.soldBy, 'Sharma Kirana');
      expect(p.shopSlug, 'sharma-kirana');
      expect(Product.fromJson({...product(), 'seller_id': 's9'}).shopId, 's9', reason: 'the plain column will do');
    });
  });

  group('one shop per basket', () {
    setUp(() => AppState.instance.useStoreConfig(multi));

    test('a second shop\'s item is flagged, the same shop\'s is not', () {
      final milk = itemOf('p1', 'Milk', 's1', 'Sharma Kirana');
      final bread = itemOf('p2', 'Bread', 's1', 'Sharma Kirana');
      final shampoo = itemOf('p3', 'Shampoo', 's2', 'Fresh Mart');

      expect(AppState.instance.shopConflictFor(milk), isNull, reason: 'empty basket');
      AppState.instance.addToCart(milk);
      expect(AppState.instance.shopConflictFor(bread), isNull);
      expect(AppState.instance.shopConflictFor(shampoo), 'Sharma Kirana');
    });

    test('the basket will not take another shop\'s item, whoever asks', () {
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));

      final added = AppState.instance.addToCart(itemOf('p3', 'Shampoo', 's2', 'Fresh Mart'));

      expect(added, isFalse);
      expect(AppState.instance.cart.map((l) => l.product.id), ['p1']);
    });

    test('with the mixed rule (or a single business) any shop may be added', () {
      AppState.instance.useStoreConfig(single);
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));

      expect(AppState.instance.addToCart(itemOf('p3', 'Shampoo', 's2', 'Fresh Mart')), isTrue);
    });

    test('an item whose shop is unknown never blocks anything', () {
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));

      expect(AppState.instance.shopConflictFor(Product.fromJson(product(id: 'x'))), isNull);
    });

    testWidgets('the shopper is asked first, and can keep their basket', (tester) async {
      phone(tester);
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));
      final shampoo = itemOf('p3', 'Shampoo', 's2', 'Fresh Mart');
      bool? answer;

      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => answer = await confirmShopSwitch(context, shampoo),
              child: const Text('go'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Start a new basket?'), findsOneWidget);
      expect(find.textContaining('items from Sharma Kirana'), findsOneWidget);
      expect(find.textContaining('Fresh Mart'), findsOneWidget);

      await tester.tap(find.text('Keep my basket'));
      await tester.pumpAndSettle();

      expect(answer, isFalse);
      expect(AppState.instance.cart.map((l) => l.product.id), ['p1'], reason: 'nothing changed');
    });

    testWidgets('or start a new one, which empties the old', (tester) async {
      phone(tester);
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));
      final shampoo = itemOf('p3', 'Shampoo', 's2', 'Fresh Mart');
      bool? answer;

      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => answer = await confirmShopSwitch(context, shampoo),
              child: const Text('go'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start new basket'));
      await tester.pumpAndSettle();

      expect(answer, isTrue);
      expect(AppState.instance.cart, isEmpty);
    });

    testWidgets('no question when there is no clash', (tester) async {
      phone(tester);
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));
      bool? answer;

      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer = await confirmShopSwitch(context, itemOf('p2', 'Bread', 's1', 'Sharma Kirana')),
            child: const Text('go'),
          ),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Start a new basket?'), findsNothing);
      expect(answer, isTrue);
    });

    testWidgets('tapping ADD on another shop\'s item asks, then adds it to a fresh basket', (tester) async {
      phone(tester);
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));
      final shampoo = itemOf('p3', 'Shampoo', 's2', 'Fresh Mart');

      await tester.pumpWidget(app(Scaffold(body: Center(child: ProductAddControl(product: shampoo, pill: true)))));
      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      expect(find.text('Start a new basket?'), findsOneWidget);

      await tester.tap(find.text('Start new basket'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cart.map((l) => l.product.id), ['p3']);
      expect(AppState.instance.cartShopName, 'Fresh Mart');
    });

    testWidgets('a dish needing a choice keeps the old basket until it is really added', (tester) async {
      phone(tester);
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));
      final dish = Product.fromJson({
        ...product(id: 'p9'),
        'title': 'Margherita Pizza',
        'seller': {'id': 's2', 'display_name': 'Fresh Mart', 'slug': 'fresh-mart'},
        'option_groups': [
          {
            'key': 'portion',
            'label': 'Portion',
            'type': 'single',
            'required': true,
            'price_mode': 'set',
            'choices': [
              {'id': 'half', 'label': 'Half plate', 'price': 150, 'default': true},
            ],
          },
        ],
      });

      await tester.pumpWidget(app(Scaffold(body: Center(child: ProductAddControl(product: dish, pill: true)))));
      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start new basket'));
      await tester.pumpAndSettle();

      // The choice sheet is open and nothing has been swapped yet.
      expect(find.textContaining('Add item'), findsOneWidget);
      expect(AppState.instance.cart.map((l) => l.product.id), ['p1']);

      // Backing out of the sheet keeps the shopper's basket.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(AppState.instance.cart.map((l) => l.product.id), ['p1']);

      // Going through with it swaps the basket.
      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start new basket'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Add item'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cart.map((l) => l.product.id), ['p9']);
    });

    testWidgets('declining leaves the first shop\'s basket and adds nothing', (tester) async {
      phone(tester);
      AppState.instance.addToCart(itemOf('p1', 'Milk', 's1', 'Sharma Kirana'));
      final shampoo = itemOf('p3', 'Shampoo', 's2', 'Fresh Mart');

      await tester.pumpWidget(app(Scaffold(body: Center(child: ProductAddControl(product: shampoo, pill: true)))));
      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my basket'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cart.map((l) => l.product.id), ['p1']);
      expect(find.text('ADD'), findsOneWidget);
    });
  });

  group('the shops list', () {
    MockClient shops(List<Map<String, dynamic>> rows, {List<Uri>? seen}) => MockClient((request) async {
          seen?.add(request.url);
          if (request.url.path.endsWith('/shops')) return response(rows);
          return response([]);
        });

    Future<void> show(WidgetTester tester, MockClient client, [Widget? child]) async {
      phone(tester, height: 1600);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: child ?? const ShopsFeed()))));
        await finishLoad(tester);
      }, () => client);
    }

    testWidgets('lists shops with what a shopper wants to know', (tester) async {
      await show(tester, shops([
        shopJson('s1', 'Sharma Kirana', extra: {'tagline': 'Fresh every morning', 'prep_minutes': 20, 'min_order_amount': 149, 'rating': 4.2}),
        shopJson('s2', 'Fresh Mart'),
      ]));

      expect(find.byType(ShopCard), findsNWidgets(2));
      expect(find.text('Sharma Kirana'), findsOneWidget);
      expect(find.text('Fresh every morning'), findsOneWidget);
      expect(find.text('20 mins · Min ₹149'), findsOneWidget);
      expect(find.byType(RatingChip), findsOneWidget, reason: 'only the rated shop');
      expect(find.text('Groceries'), findsOneWidget, reason: 'what Fresh Mart sells, since it has no tagline');
    });

    testWidgets('a closed shop says so and when it opens', (tester) async {
      await show(tester, shops([
        shopJson('s1', 'Late Mart', extra: {'is_open': false, 'closed_text': 'Opens tomorrow at 9:00 AM'}),
      ]));

      expect(find.text('Closed · Opens tomorrow at 9:00 AM'), findsOneWidget);
    });

    testWidgets('an empty list says so instead of showing nothing', (tester) async {
      await show(tester, shops([]));

      expect(find.text('No shops found'), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        // The API client repeats a failed read once on its own, so the first two fail.
        return calls <= 2 ? response({}, status: 500) : response([shopJson('s1', 'Sharma Kirana')]);
      });
      await show(tester, client);

      expect(find.text('Could not load shops'), findsOneWidget);
      await http.runWithClient(() async {
        await tester.tap(find.text('Try again'));
        await finishLoad(tester);
      }, () => client);

      expect(find.text('Sharma Kirana'), findsOneWidget);
    });

    testWidgets('signed in, only shops that deliver to the default address are asked for', (tester) async {
      ShopArea.forget();
      final seen = <Uri>[];
      final client = MockClient((request) async {
        seen.add(request.url);
        final path = request.url.path;
        if (path.endsWith('/auth/login')) return response({'token': 't', 'user': user});
        if (path.endsWith('/addresses')) {
          return response([
            {'id': 'a1', 'tag': 'Home', 'name': 'S', 'phone': '9876543210', 'line1': 'x', 'city': 'Bengaluru', 'state': 'KA', 'pincode': '560038', 'is_default': true},
          ]);
        }
        if (path.endsWith('/shops')) return response([shopJson('s1', 'Sharma Kirana')]);
        return response([]);
      });
      phone(tester, height: 1600);
      await http.runWithClient(() async {
        await AppState.instance.signIn('s@example.com', 'pw');
        await tester.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: ShopsFeed()))));
        await finishLoad(tester);
      }, () => client);

      expect(seen.firstWhere((u) => u.path.endsWith('/shops')).queryParameters['pincode'], '560038');
      expect(find.text('Shops delivering to 560038'), findsOneWidget);
      ShopArea.forget();
    });

    http.Response withFacets(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> facets) =>
        http.Response(jsonEncode({'data': rows, 'facets': {'categories': facets}}), 200,
            headers: {'content-type': 'application/json'});

    testWidgets('offers the categories the shops sell in as filters, whatever those are', (tester) async {
      ShopArea.forget();
      final seen = <Uri>[];
      final client = MockClient((request) async {
        seen.add(request.url);
        final category = request.url.queryParameters['category'];
        // Groceries, clothing and medicines: nothing here is food-specific.
        final all = [
          shopJson('s1', 'Sharma Kirana', extra: {'categories': ['Groceries']}),
          shopJson('s2', 'Style Corner', extra: {'categories': ['Clothing']}),
          shopJson('s3', 'City Pharmacy', extra: {'categories': ['Medicines']}),
        ];
        return withFacets(
          category == 'clothing' ? [all[1]] : all,
          [
            {'slug': 'groceries', 'name': 'Groceries', 'shops': 1},
            {'slug': 'clothing', 'name': 'Clothing', 'shops': 1},
            {'slug': 'medicines', 'name': 'Medicines', 'shops': 1},
          ],
        );
      });
      phone(tester, width: 800, height: 1800);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: ShopsFeed()))));
        await finishLoad(tester);
      }, () => client);

      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Groceries'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Clothing'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Medicines'), findsOneWidget);
      expect(find.byType(ShopCard), findsNWidgets(3));

      await http.runWithClient(() async {
        await tester.tap(find.widgetWithText(ChoiceChip, 'Clothing'));
        await finishLoad(tester);
      }, () => client);

      expect(seen.last.queryParameters['category'], 'clothing');
      expect(find.byType(ShopCard), findsOneWidget);
      expect(find.text('Style Corner'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Medicines'), findsOneWidget, reason: 'the other chips stay');

      await http.runWithClient(() async {
        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await finishLoad(tester);
      }, () => client);

      expect(find.byType(ShopCard), findsNWidgets(3));
    });

    testWidgets('with only one category there is nothing to filter, so no chips', (tester) async {
      ShopArea.forget();
      final client = MockClient((request) async => withFacets(
            [shopJson('s1', 'Sharma Kirana')],
            [
              {'slug': 'groceries', 'name': 'Groceries', 'shops': 1},
            ],
          ));
      await show(tester, client);

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('a server that sends no filters (an older one) simply has none', (tester) async {
      ShopArea.forget();
      await show(tester, shops([shopJson('s1', 'Sharma Kirana')]));

      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(ShopCard), findsOneWidget);
    });

    testWidgets('searching and "Open now" narrow what is asked for', (tester) async {
      ShopArea.forget();
      final seen = <Uri>[];
      final client = shops([shopJson('s1', 'Sharma Kirana')], seen: seen);
      phone(tester, height: 1600);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const ShopsScreen()));
        await finishLoad(tester);

        await tester.tap(find.text('Open now'));
        await finishLoad(tester);
        await tester.enterText(find.byType(TextField), 'sharma');
        await tester.pump(const Duration(milliseconds: 400));
        await finishLoad(tester);
      }, () => client);

      final last = seen.where((u) => u.path.endsWith('/shops')).last;
      expect(last.queryParameters['open'], '1');
      expect(last.queryParameters['search'], 'sharma');
    });
  });

  group('a shop\'s page', () {
    MockClient shopWith(Map<String, dynamic> shop, List<Map<String, dynamic>> items) => MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/shops/${shop['id']}')) return response(shop);
          if (path.endsWith('/products')) {
            expect(request.url.queryParameters['seller'], shop['id'], reason: 'only this shop\'s items');
            return response(items);
          }
          return response([]);
        });

    Future<void> open(WidgetTester tester, Map<String, dynamic> shop, List<Map<String, dynamic>> items) async {
      phone(tester, height: 2000);
      AppState.instance.useStoreConfig(multi);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(ShopScreen(shop: Shop.fromJson(shop))));
        await finishLoad(tester);
      }, () => shopWith(shop, items));
    }

    testWidgets('shows who they are, what they ask, and their items by category', (tester) async {
      await open(
        tester,
        shopJson('s1', 'Sharma Kirana', extra: {'tagline': 'Fresh every morning', 'prep_minutes': 20, 'min_order_amount': 149, 'rating': 4.2, 'reviews_count': 18}),
        [
          itemJson('p1', 'Full Cream Milk', 's1', 'Sharma Kirana', category: 'Dairy'),
          itemJson('p2', 'Salted Butter', 's1', 'Sharma Kirana', category: 'Dairy'),
          itemJson('p3', 'Basmati Rice', 's1', 'Sharma Kirana', category: 'Staples'),
        ],
      );

      expect(find.text('Sharma Kirana'), findsWidgets);
      expect(find.text('Fresh every morning'), findsOneWidget);
      expect(find.text('Ready in ~20 mins'), findsOneWidget);
      expect(find.text('Min ₹149'), findsOneWidget);
      expect(find.text('18 ratings'), findsOneWidget);
      expect(find.text('Dairy'), findsWidgets);   // heading and chip
      expect(find.text('Staples'), findsWidgets);
      expect(find.text('Full Cream Milk'), findsOneWidget);
      expect(find.text('ADD'), findsNWidgets(3));
    });

    testWidgets('a category chip narrows the list', (tester) async {
      await open(tester, shopJson('s1', 'Sharma Kirana'), [
        itemJson('p1', 'Full Cream Milk', 's1', 'Sharma Kirana', category: 'Dairy'),
        itemJson('p3', 'Basmati Rice', 's1', 'Sharma Kirana', category: 'Staples'),
      ]);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Staples'));
      await tester.pump();

      expect(find.text('Basmati Rice'), findsOneWidget);
      expect(find.text('Full Cream Milk'), findsNothing);
    });

    testWidgets('searching inside the shop filters its items', (tester) async {
      await open(tester, shopJson('s1', 'Sharma Kirana'), [
        itemJson('p1', 'Full Cream Milk', 's1', 'Sharma Kirana'),
        itemJson('p3', 'Basmati Rice', 's1', 'Sharma Kirana'),
      ]);

      await tester.enterText(find.byType(TextField), 'rice');
      await tester.pump();

      expect(find.text('Basmati Rice'), findsOneWidget);
      expect(find.text('Full Cream Milk'), findsNothing);
    });

    testWidgets('a closed shop says when it opens and cannot be added to', (tester) async {
      await open(
        tester,
        shopJson('s1', 'Late Mart', extra: {'is_open': false, 'closed_text': 'Opens tomorrow at 9:00 AM'}),
        [itemJson('p1', 'Full Cream Milk', 's1', 'Late Mart')],
      );

      expect(find.textContaining('Opens tomorrow at 9:00 AM'), findsOneWidget);
      expect(find.text('Closed'), findsWidgets);
      expect(find.text('ADD'), findsNothing);
      expect(find.text('Full Cream Milk'), findsOneWidget, reason: 'browsing is still allowed');
    });

    testWidgets('a shop with nothing on sale says so', (tester) async {
      await open(tester, shopJson('s1', 'Sharma Kirana'), []);

      expect(find.text('This shop has nothing on sale yet.'), findsOneWidget);
    });

    testWidgets('an item added here lands in the basket, with a cart strip below', (tester) async {
      await open(tester, shopJson('s1', 'Sharma Kirana'), [itemJson('p1', 'Full Cream Milk', 's1', 'Sharma Kirana')]);

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cartShopName, 'Sharma Kirana');
      expect(find.text('View cart'), findsOneWidget);
    });
  });

  group('the cart, from one shop', () {
    Future<void> openCart(WidgetTester tester, Map<String, dynamic> shop, {int subtotal = 100}) async {
      phone(tester, height: 1800);
      AppState.instance.useStoreConfig(multi);
      AppState.instance.addToCart(itemOf('p1', 'Milk', shop['id'] as String, shop['name'] as String, price: subtotal));
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/shops/${shop['id']}')) return response(shop);
        return response([]);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(app(CartScreen(onStartShopping: () {})));
        await finishLoad(tester);
      }, () => client);
    }

    testWidgets('names the shop the basket is from', (tester) async {
      await openCart(tester, shopJson('s1', 'Sharma Kirana'));

      expect(find.text('Ordering from'), findsOneWidget);
      expect(find.text('Sharma Kirana'), findsWidgets);
    });

    testWidgets('below the shop\'s minimum it says how much more, and will not go to checkout', (tester) async {
      await openCart(tester, shopJson('s1', 'Sharma Kirana', extra: {'min_order_amount': 300}), subtotal: 200);

      expect(find.textContaining('Add ₹100 more for the minimum order of ₹300'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Add ₹100 more').evaluate().isNotEmpty ||
          find.text('Add ₹100 more').evaluate().isNotEmpty, isTrue);
      expect(find.text('Proceed to checkout'), findsNothing);
    });

    testWidgets('once the minimum is met checkout opens up', (tester) async {
      await openCart(tester, shopJson('s1', 'Sharma Kirana', extra: {'min_order_amount': 300}), subtotal: 300);

      expect(find.textContaining('Minimum order of ₹300 reached'), findsOneWidget);
      expect(find.text('Sign in to checkout'), findsOneWidget);
    });

    testWidgets('a closed shop blocks checkout and says when it opens', (tester) async {
      await openCart(tester, shopJson('s1', 'Late Mart', extra: {'is_open': false, 'closed_text': 'Opens tomorrow at 9:00 AM'}));

      expect(find.text('Shop is closed'), findsWidgets);
      expect(find.textContaining('Opens tomorrow at 9:00 AM'), findsOneWidget);
      expect(find.text('Sign in to checkout'), findsNothing);
    });

    testWidgets('a single-business store shows no shop strip at all', (tester) async {
      phone(tester, height: 1800);
      AppState.instance.useStoreConfig(single);
      AppState.instance.addToCart(Product.fromJson(product()));
      await http.runWithClient(() async {
        await tester.pumpWidget(app(CartScreen(onStartShopping: () {})));
        await finishLoad(tester);
      }, () => MockClient((_) async => response([])));

      expect(find.text('Ordering from'), findsNothing);
    });
  });

  group('home', () {
    MockClient store(List<Map<String, dynamic>> shops) => MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/shops')) return response(shops);
          if (path.endsWith('/categories')) return response(categories);
          return response([]);
        });

    Future<void> openHome(WidgetTester tester, StoreConfig config, List<Map<String, dynamic>> shops) async {
      phone(tester, height: 1800);
      AppState.instance.useStoreConfig(config);
      ShopArea.forget();
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const HomeScreen()));
        await finishLoad(tester);
      }, () => store(shops));
    }

    testWidgets('a vendors-only store opens on its shops', (tester) async {
      await openHome(tester, multi, [shopJson('s1', 'Sharma Kirana'), shopJson('s2', 'Fresh Mart')]);

      expect(find.text('Order from a shop'), findsOneWidget);
      expect(find.byType(ShopCard), findsNWidgets(2));
      expect(find.text('Trending now'), findsNothing, reason: 'no product feed');
    });

    testWidgets('a store with its own shop and vendors adds a row of shops to the usual home', (tester) async {
      await openHome(tester, hybrid, [shopJson('s1', 'Sharma Kirana'), shopJson('s2', 'Fresh Mart')]);

      expect(find.text('See all'), findsOneWidget);
      expect(find.byType(ShopRailCard), findsWidgets);
      expect(find.text('Order from a shop'), findsNothing);
    });

    testWidgets('a store that lists products directly keeps shops off the home', (tester) async {
      const direct = StoreConfig(
        mode: 'hybrid',
        vendorsEnabled: true,
        houseVisible: true,
        shopsFirst: false,
        showsShops: true,
        homeShowsShops: false,
        oneShopPerCart: false,
      );
      await openHome(tester, direct, [shopJson('s1', 'Sharma Kirana'), shopJson('s2', 'Fresh Mart')]);

      expect(find.byType(ShopRailCard), findsNothing);
      expect(find.text('See all'), findsNothing);
      expect(find.text('Order from a shop'), findsNothing);
    });

    test('an older server that never says keeps the row', () {
      expect(StoreConfig.fromJson({'mode': 'hybrid', 'shows_shops': true}).homeShowsShops, isTrue);
      expect(StoreConfig.fromJson({'mode': 'hybrid', 'shows_shops': true, 'home_shows_shops': false}).homeShowsShops, isFalse);
    });

    testWidgets('one shop is not worth a row', (tester) async {
      await openHome(tester, hybrid, [shopJson('s1', 'Sharma Kirana')]);

      expect(find.text('See all'), findsNothing);
    });

    testWidgets('a single-business store, or an older server, looks as it always did', (tester) async {
      await openHome(tester, single, [shopJson('s1', 'A'), shopJson('s2', 'B')]);

      expect(find.byType(ShopsRail), findsNothing);
      expect(find.byType(ShopCard), findsNothing);
      expect(find.text('Order from a shop'), findsNothing);
    });
  });

  group('selling', () {
    testWidgets('"Sell on" is offered where vendors are welcome', (tester) async {
      phone(tester, height: 2200);
      AppState.instance.useStoreConfig(hybrid);
      await http.runWithClient(() async {
        await AppState.instance.signIn('s@example.com', 'pw');
        await tester.pumpWidget(app(const AccountScreen()));
        await finishLoad(tester);
      }, () => MockClient((request) async {
            if (request.url.path.endsWith('/auth/login')) return response({'token': 't', 'user': user});
            return response([]);
          }));

      expect(find.textContaining('Sell on'), findsOneWidget);
    });

    testWidgets('and not in a single-business store', (tester) async {
      phone(tester, height: 2200);
      AppState.instance.useStoreConfig(single);
      await http.runWithClient(() async {
        await AppState.instance.signIn('s@example.com', 'pw');
        await tester.pumpWidget(app(const AccountScreen()));
        await finishLoad(tester);
      }, () => MockClient((request) async {
            if (request.url.path.endsWith('/auth/login')) return response({'token': 't', 'user': user});
            return response([]);
          }));

      expect(find.textContaining('Sell on'), findsNothing);
    });
  });
}
