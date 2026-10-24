import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/data/product_filters.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/design/mobile_components.dart';
import 'package:marketplace_app/screens/categories_screen.dart';
import 'package:marketplace_app/screens/category_screen.dart';
import 'package:marketplace_app/screens/orders_screen.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/category_shortcuts.dart';
import 'package:marketplace_app/widgets/product_filter_sheet.dart';

import 'support.dart';

Category _category({String? image, Map<String, dynamic>? config}) =>
    Category.fromJson({
      'id': 'c1',
      'name': 'Ethnic & Festive',
      'slug': 'ethnic-wear',
      'icon_url': 'Sparkles',
      if (image != null) 'image_url': image,
      if (config != null) 'filter_config': config,
    });

void main() {
  setUp(resetState);

  group('bottom navigation', () {
    final items = [
      const BxNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
      const BxNavItem(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view, label: 'Categories'),
      const BxNavItem(
          icon: Icons.shopping_bag_outlined, activeIcon: Icons.shopping_bag, label: 'Cart', badge: 3),
    ];

    testWidgets('only the selected tab shows its name, the rest are icons',
        (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        bottomNavigationBar:
            BxBottomNav(items: items, selectedIndex: 1, onSelected: (_) {}),
      )));

      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Cart'), findsOneWidget);
    });

    testWidgets('tapping an icon selects that tab', (tester) async {
      phone(tester);
      int? picked;
      await tester.pumpWidget(app(Scaffold(
        bottomNavigationBar: BxBottomNav(
            items: items, selectedIndex: 0, onSelected: (i) => picked = i),
      )));

      await tester.tap(find.byTooltip('Cart'));
      expect(picked, 2);
    });

    testWidgets('the cart shows how many items it holds', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        bottomNavigationBar:
            BxBottomNav(items: items, selectedIndex: 0, onSelected: (_) {}),
      )));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('every target is finger-sized', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        bottomNavigationBar:
            BxBottomNav(items: items, selectedIndex: 0, onSelected: (_) {}),
      )));

      for (final label in ['Categories', 'Cart']) {
        final size = tester.getSize(find.ancestor(
                of: find.byTooltip(label), matching: find.byType(Tooltip))
            .first);
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });
  });

  group('filters', () {
    test('turn into the query the API understands', () {
      const filters = ProductFilters(
        minPrice: 500,
        maxPrice: 2500.4,
        inStockOnly: true,
        minRating: 4,
        brand: 'Fab',
        attributes: {'fabric': {'silk', 'cotton'}},
      );

      final q = filters.toQuery({'category': 'ethnic-wear'});

      expect(q['category'], 'ethnic-wear');
      expect(q['min_price'], '500');
      expect(q['max_price'], '2500');
      expect(q['in_stock'], '1');
      expect(q['min_rating'], '4.0');
      expect(q['brand'], 'Fab');
      expect(q.entries.where((e) => e.key.startsWith('attr[fabric]')).map((e) => e.value).toSet(),
          {'silk', 'cotton'});
    });

    test('count the things being filtered, not the values', () {
      expect(ProductFilters.none.isActive, isFalse);
      expect(ProductFilters.none.count, 0);
      expect(
        const ProductFilters(minPrice: 1, maxPrice: 9, inStockOnly: true).count,
        2,
      );
      expect(
        const ProductFilters(attributes: {'a': {'x', 'y'}, 'b': {}}).count,
        1,
      );
    });

    test('copyWith can clear a value as well as set one', () {
      final f = const ProductFilters(brand: 'Fab', minRating: 3)
          .copyWith(brand: null);
      expect(f.brand, isNull);
      expect(f.minRating, 3);
    });

    test('the admin filter groups are read, and bad ones skipped', () {
      final groups = FilterGroup.parse({
        'groups': [
          {
            'id': 'fabric',
            'label': 'Fabric',
            'type': 'chip',
            'options': [
              {'label': 'Silk', 'value': 'silk'},
              {'label': 'Cotton', 'value': 'cotton'},
              {'label': '', 'value': ''},
            ]
          },
          {'id': 'price', 'label': 'Price', 'type': 'range'},
          {'id': 'empty', 'label': 'Nothing', 'type': 'checkbox', 'options': []},
          'garbage',
        ]
      });

      expect(groups.map((g) => g.id), ['fabric']);
      expect(groups.single.options.map((o) => o.value), ['silk', 'cotton']);
      expect(FilterGroup.parse(null), isEmpty);
    });

    testWidgets('the sheet returns what was chosen', (tester) async {
      phone(tester, height: 1000);
      ProductFilters? result;
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: BxButton(
              label: 'Open',
              onPressed: () async => result = await showProductFilterSheet(
                context,
                current: ProductFilters.none,
                priceCeiling: 4000,
                brands: const ['Fab', 'Kora'],
                groups: [
                  FilterGroup.parse({
                    'groups': [
                      {
                        'id': 'fabric',
                        'label': 'Fabric',
                        'type': 'chip',
                        'options': [
                          {'label': 'Silk', 'value': 'silk'}
                        ]
                      }
                    ]
                  }).single
                ],
              ),
            ),
          ),
        ),
      )));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('In stock only'));
      await tester.tap(find.text('Kora'));
      await tester.tap(find.text('Silk'));
      await tester.pump();
      await tester.tap(find.textContaining('Show results'));
      await tester.pumpAndSettle();

      expect(result!.inStockOnly, isTrue);
      expect(result!.brand, 'Kora');
      expect(result!.attributes['fabric'], {'silk'});
    });

    testWidgets('Clear all resets everything', (tester) async {
      phone(tester, height: 1000);
      ProductFilters? result;
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: BxButton(
              label: 'Open',
              onPressed: () async => result = await showProductFilterSheet(
                context,
                current: const ProductFilters(inStockOnly: true, brand: 'Fab'),
                priceCeiling: 1000,
                brands: const ['Fab'],
              ),
            ),
          ),
        ),
      )));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(result!.isActive, isFalse);
    });
  });

  group('category screen', () {
    testWidgets('applying a filter asks the server for exactly that',
        (tester) async {
      phone(tester, height: 1000);
      final queries = <Map<String, String>>[];
      final client = MockClient((request) async {
        queries.add(request.url.queryParameters);
        return response([product()]);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(app(CategoryScreen(category: _category())));
        await finishLoad(tester);
        expect(queries.last.containsKey('in_stock'), isFalse);

        await tester.tap(find.byTooltip('Filters'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('In stock only'));
        await tester.pump();
        await tester.tap(find.textContaining('Show results'));
        await tester.pumpAndSettle();
        await finishLoad(tester);

        expect(queries.last['in_stock'], '1');
        expect(queries.last['category'], 'ethnic-wear');
        expect(find.textContaining('1 filter applied'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });

    testWidgets('no matches offers a way out', (tester) async {
      phone(tester, height: 1000);
      final client = MockClient((request) async =>
          response(request.url.queryParameters.containsKey('in_stock') ? [] : [product()]));

      await http.runWithClient(() async {
        await tester.pumpWidget(app(CategoryScreen(category: _category())));
        await finishLoad(tester);
        await tester.tap(find.byTooltip('Filters'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('In stock only'));
        await tester.pump();
        await tester.tap(find.textContaining('Show results'));
        await tester.pumpAndSettle();
        await finishLoad(tester);

        expect(find.text('No matches'), findsOneWidget);
        await tester.tap(find.text('Clear filters'));
        await finishLoad(tester);
        expect(find.text('No matches'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });
  });

  group('category pictures', () {
    test('the model reads the picture and the filter config', () {
      final c = _category(image: 'https://x/y.jpg', config: {'groups': []});
      expect(c.imageUrl, 'https://x/y.jpg');
      expect(c.filterConfig, {'groups': []});
      expect(_category().imageUrl, isNull);
      expect(Category.fromJson({'id': '1', 'name': 'A', 'slug': 'a', 'image_url': '  '}).imageUrl,
          isNull);
    });

    testWidgets('a category with a picture shows it', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Center(child: CategoryThumb(category: _category(image: 'https://x/y.jpg'))),
      )));

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('one without falls back to its icon', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Center(child: CategoryThumb(category: _category())),
      )));

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    });

    testWidgets('on the home page categories sit in one row that scrolls',
        (tester) async {
      phone(tester, width: 360);
      await tester.pumpWidget(app(Scaffold(
        body: CategoryShortcuts(
          categories: categories.map(Category.fromJson).toList(),
          onSelected: (_) {},
          scrollable: true,
        ),
      )));

      final tops = categories
          .map((c) => tester.getTopLeft(find.byKey(ValueKey('category-${c['slug']}'))).dy)
          .toSet();
      expect(tops.length, 1);
    });
  });

  group('categories tab', () {
    testWidgets('lists every category and what is new', (tester) async {
      phone(tester, height: 1000);
      final client = MockClient((request) async => response(
            request.url.path.endsWith('/categories') ? categories : [product()],
          ));

      await http.runWithClient(() async {
        await tester.pumpWidget(app(const CategoriesScreen()));
        await finishLoad(tester);

        expect(find.byType(CategoryThumb), findsNWidgets(5));
        expect(find.text('New arrivals'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });
  });

  group('orders', () {
    test('every status belongs to one of the shopper-facing buckets', () {
      expect(bucketOf('PENDING'), OrderBucket.pending);
      expect(bucketOf('CONFIRMED'), OrderBucket.pending);
      expect(bucketOf('PACKED'), OrderBucket.processing);
      expect(bucketOf('SHIPPED'), OrderBucket.processing);
      expect(bucketOf('OUT_FOR_DELIVERY'), OrderBucket.processing);
      expect(bucketOf('DELIVERED'), OrderBucket.completed);
      expect(bucketOf('CANCELLED'), OrderBucket.cancelled);
    });

    Map<String, dynamic> order(String id, String status, {int qty = 1}) => {
          'id': id,
          'order_number': 'ORD-$id',
          'status': status,
          'payment_method': 'COD',
          'total_amount': 999,
          'created_at': '2026-10-09T10:00:00Z',
          'items': [
            {
              'id': 'i$id',
              'product_id': 'p1',
              'variant_id': 'v1',
              'quantity': qty,
              'price': 999,
              'product': {'title': 'Cotton shirt', 'images': []},
            }
          ],
        };

    MockClient shop(List<Map<String, dynamic>> orders, {bool soldOut = false}) =>
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/auth/login')) return response({'token': 't', 'user': user});
          if (path.endsWith('/orders/mine')) return response(orders);
          if (path.endsWith('/products/p1')) return response(product(stock: soldOut ? 0 : 5));
          return response({}, status: 404);
        });

    testWidgets('signed out it asks you to sign in', (tester) async {
      phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const OrdersScreen()));
        await finishLoad(tester);

        expect(find.text('Sign in to see your orders'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => shop([]));
    });

    testWidgets('chips filter the list and show counts', (tester) async {
      phone(tester, width: 900, height: 1200); // wide enough to build every chip
      await http.runWithClient(() async {
        await AppState.instance.signIn('a@b.c', 'pw');
        await tester.pumpWidget(app(const OrdersScreen()));
        await finishLoad(tester);

        expect(find.text('Order #A'), findsOneWidget);
        expect(find.text('Order #B'), findsOneWidget);
        expect(find.text('Completed · 1'), findsOneWidget);

        await tester.tap(find.text('Completed · 1'));
        await tester.pump();

        expect(find.text('Order #A'), findsNothing);
        expect(find.text('Order #B'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => shop([order('A', 'CONFIRMED'), order('B', 'DELIVERED')]));
    });

    testWidgets('each card offers the action that fits its status', (tester) async {
      phone(tester, height: 1400);
      await http.runWithClient(() async {
        await AppState.instance.signIn('a@b.c', 'pw');
        await tester.pumpWidget(app(const OrdersScreen()));
        await finishLoad(tester);

        expect(find.text('Cancel order'), findsOneWidget);
        expect(find.text('Track order'), findsOneWidget);
        expect(find.text('Return / refund'), findsOneWidget);
        expect(find.text('Buy again'), findsNWidgets(3));
        await tester.pumpWidget(const SizedBox());
      }, () => shop([
            order('A', 'CONFIRMED'),
            order('B', 'OUT_FOR_DELIVERY'),
            order('C', 'DELIVERED'),
          ]));
    });

    testWidgets('Buy again puts the same item back in the cart', (tester) async {
      phone(tester, height: 1200);
      await http.runWithClient(() async {
        await AppState.instance.signIn('a@b.c', 'pw');
        AppState.instance.clearCart();
        await tester.pumpWidget(app(const OrdersScreen()));
        await finishLoad(tester);

        await tester.tap(find.text('Buy again'));
        await finishLoad(tester);

        expect(AppState.instance.cart.single.variant?.id, 'v1');
        expect(AppState.instance.cart.single.quantity, 2);
        expect(find.textContaining('added to your cart'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => shop([order('A', 'DELIVERED', qty: 2)]));
    });

    testWidgets('Buy again says so when the item is gone', (tester) async {
      phone(tester, height: 1200);
      await http.runWithClient(() async {
        await AppState.instance.signIn('a@b.c', 'pw');
        AppState.instance.clearCart();
        await tester.pumpWidget(app(const OrdersScreen()));
        await finishLoad(tester);

        await tester.tap(find.text('Buy again'));
        await finishLoad(tester);

        expect(AppState.instance.cart, isEmpty);
        expect(find.textContaining('not available'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => shop([order('A', 'DELIVERED')], soldOut: true));
    });

    testWidgets('an empty bucket says so', (tester) async {
      phone(tester, width: 900, height: 1200); // wide enough to build every chip
      await http.runWithClient(() async {
        await AppState.instance.signIn('a@b.c', 'pw');
        await tester.pumpWidget(app(const OrdersScreen()));
        await finishLoad(tester);

        await tester.tap(find.text('Cancelled'));
        await tester.pump();

        expect(find.text('No cancelled orders'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => shop([order('A', 'DELIVERED')]));
    });
  });
}
