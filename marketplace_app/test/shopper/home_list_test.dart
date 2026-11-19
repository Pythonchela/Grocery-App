import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/screens/category_screen.dart';
import 'package:marketplace_app/screens/home_screen.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/product_add_control.dart';
import 'package:marketplace_app/widgets/product_list_row.dart';

import 'support.dart';

Product make({
  String id = 'p1',
  String title = 'Cotton shirt',
  int price = 400,
  int mrp = 800,
  double rating = 4.5,
  bool isNew = false,
  int stock = 5,
  bool options = false,
}) =>
    Product.fromJson({
      ...product(id: id, stock: stock, options: options),
      'title': title,
      'price': price,
      'mrp': mrp,
      'rating': rating,
      'is_new': isNew,
      'brand': 'Fab',
      'category': {'name': 'Menswear'},
    });

void main() {
  setUp(resetState);

  group('ADD control', () {
    testWidgets('ADD becomes a stepper, and the stepper can empty the cart',
        (tester) async {
      phone(tester);
      final p = make();
      await tester.pumpWidget(app(Scaffold(
        body: Center(child: ProductAddControl(product: p, pill: true)),
      )));

      expect(find.text('ADD'), findsOneWidget);
      await tester.tap(find.text('ADD'));
      await tester.pump();

      expect(AppState.instance.cart.single.quantity, 1);
      expect(find.text('ADD'), findsNothing);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.byTooltip('Add one more'));
      await tester.pump();
      expect(AppState.instance.cart.single.quantity, 2);

      await tester.tap(find.byTooltip('Remove one'));
      await tester.tap(find.byTooltip('Remove one'));
      await tester.pump();
      expect(AppState.instance.cart, isEmpty);
      expect(find.text('ADD'), findsOneWidget);
    });

    testWidgets('stops at the stock that is left', (tester) async {
      phone(tester);
      final p = make(stock: 2);
      await tester.pumpWidget(app(Scaffold(
        body: Center(child: ProductAddControl(product: p, pill: true)),
      )));

      await tester.tap(find.text('ADD'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add one more'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add one more'));
      await tester.pump();

      expect(AppState.instance.cart.single.quantity, 2);
    });

    testWidgets('a product that needs a choice opens its page instead',
        (tester) async {
      phone(tester);
      var opened = false;
      final p = make(options: true);
      await tester.pumpWidget(app(Scaffold(
        body: Center(
            child: ProductAddControl(
                product: p, pill: true, onOpen: () => opened = true)),
      )));

      await tester.tap(find.text('ADD'));
      expect(opened, isTrue);
      expect(AppState.instance.cart, isEmpty);
      expect(find.text('customisable'), findsOneWidget);
    });

    testWidgets('sold out says so and cannot be added', (tester) async {
      phone(tester);
      final p = make(stock: 0);
      await tester.pumpWidget(app(Scaffold(
        body: Center(child: ProductAddControl(product: p, pill: true)),
      )));

      expect(find.text('Sold out'), findsOneWidget);
      expect(find.text('ADD'), findsNothing);
    });
  });

  group('list row', () {
    testWidgets('shows what a shopper wants to know before adding',
        (tester) async {
      phone(tester);
      var tapped = false;
      await tester.pumpWidget(app(Scaffold(
        body: ProductListRow(
            product: make(isNew: true), onTap: () => tapped = true),
      )));

      expect(find.text('Cotton shirt'), findsOneWidget);
      expect(find.text('Fab · Menswear'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget); // rating chip
      expect(find.text('NEW'), findsOneWidget);
      expect(find.textContaining('comfortable everyday shirt'), findsOneWidget);
      expect(find.text('₹400'), findsOneWidget);
      expect(find.text('₹800'), findsOneWidget);
      expect(find.text('-50%'), findsOneWidget);
      expect(find.text('ADD'), findsOneWidget);

      await tester.tap(find.text('Cotton shirt'));
      expect(tapped, isTrue);
    });

    testWidgets('a bare product does not show empty rating or description',
        (tester) async {
      phone(tester);
      final bare = Product.fromJson({
        ...product(),
        'rating': 0,
        'reviews_count': 0,
        'description': '',
        'is_new': false,
        'brand': '',
      });
      await tester.pumpWidget(app(Scaffold(
        body: ProductListRow(product: bare, onTap: () {}),
      )));

      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.textContaining('comfortable'), findsNothing);
    });
  });

  group('home', () {
    MockClient shop(List<Map<String, dynamic>> items) => MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/categories')) return response(categories);
          if (path.endsWith('/products')) return response(items);
          if (path.endsWith('/storefront/sections')) return response([]);
          return response([]);
        });

    Map<String, dynamic> item(String id, String title,
            {int price = 400, int mrp = 800, double rating = 4.5, bool isNew = false, String? diet}) =>
        {
          ...product(id: id),
          'diet': diet,
          'category': {'name': 'Ethnic & Festive'},
          'title': title,
          'price': price,
          'mrp': mrp,
          'rating': rating,
          'is_new': isNew,
        };

    testWidgets('shows the items in rails, and "Veg only" hides what is not vegetarian', (tester) async {
      phone(tester, width: 800, height: 1800);
      final items = [
        item('a', 'Paneer wrap', diet: 'veg'),
        item('b', 'Chicken roll', diet: 'non_veg'),
      ];

      await http.runWithClient(() async {
        await tester.pumpWidget(app(const HomeScreen()));
        await finishLoad(tester);
        expect(find.text('Paneer wrap'), findsWidgets);
        expect(find.text('Chicken roll'), findsWidgets);

        await tester.tap(find.text('Veg only'));
        await tester.pump();
        expect(find.text('Paneer wrap'), findsWidgets);
        expect(find.text('Chicken roll'), findsNothing);

        await tester.tap(find.text('Veg only'));
        await tester.pump();
        expect(find.text('Chicken roll'), findsWidgets);

        await tester.tap(find.text('Offers'));
        await tester.pump();
        expect(find.text('Paneer wrap'), findsWidgets, reason: 'both have an offer (price below MRP)');
        await tester.pumpWidget(const SizedBox());
      }, () => shop(items));
    });

    testWidgets('an item can be added straight from home', (tester) async {
      phone(tester, height: 1800);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const HomeScreen()));
        await finishLoad(tester);
        await tester.scrollUntilVisible(find.text('ADD').first, 300,
            scrollable: find.byType(Scrollable).first);

        await tester.tap(find.text('ADD').first);
        await tester.pump();

        expect(AppState.instance.cart, hasLength(1));
        await tester.pumpWidget(const SizedBox());
      }, () => shop([item('a', 'Cheap tee')]));
    });
  });

  group('category pictures', () {
    test('uses the admin picture, else the cover photo the API picked', () {
      expect(
          Category.fromJson({'id': '1', 'name': 'A', 'slug': 'a', 'image_url': 'https://x/own.jpg', 'cover_image_url': 'https://x/cover.jpg'}).imageUrl,
          'https://x/own.jpg');
      expect(
          Category.fromJson({'id': '1', 'name': 'A', 'slug': 'a', 'image_url': null, 'cover_image_url': 'https://x/cover.jpg'}).imageUrl,
          'https://x/cover.jpg');
      expect(Category.fromJson({'id': '1', 'name': 'A', 'slug': 'a'}).imageUrl, isNull);
    });
  });

  group('category buttons', () {
    test('a category without a picture borrows a photo of something in it', () {
      final cats = [
        Category.fromJson({'id': '1', 'name': 'Menswear', 'slug': 'menswear'}),
        Category.fromJson({'id': '2', 'name': 'Empty', 'slug': 'empty'}),
        Category.fromJson({'id': '3', 'name': 'Own', 'slug': 'own', 'image_url': 'https://x/own.jpg'}),
      ];
      final withPhotos = Category.withCoverPhotos(cats, [
        make(), // Menswear, has a photo
        Product.fromJson({...product(id: 'z'), 'images': [], 'category': {'name': 'Empty'}}), // no real photo
      ]);

      expect(withPhotos[0].imageUrl, 'https://example.com/shirt.png');
      expect(withPhotos[1].imageUrl, isNull);
      expect(withPhotos[2].imageUrl, 'https://x/own.jpg');
    });

    testWidgets('a category page lets you hop to another category', (tester) async {
      phone(tester, width: 900, height: 1000); // test fonts are wide; fit the strip
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/categories')) return response(categories);
        return response([product()]);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(app(CategoryScreen(category: Category.fromJson(categories.first))));
        await finishLoad(tester);

        final casual = find.byKey(const ValueKey('strip-casual-wear'));
        final ethnic = find.byKey(const ValueKey('strip-ethnic-wear'));
        final casualBefore = tester.getSize(casual);
        final ethnicBefore = tester.getSize(ethnic);
        final ethnicTop = tester.getTopLeft(ethnic);

        await tester.tap(casual);
        await finishLoad(tester);

        // The page is now the other category, with no page transition...
        expect(find.descendant(of: find.byType(AppBar), matching: find.text('Casual & Streetwear')), findsOneWidget);
        // ...and the buttons did not change shape, size or place.
        expect(tester.getSize(casual), casualBefore);
        expect(tester.getSize(ethnic), ethnicBefore);
        expect(tester.getTopLeft(ethnic), ethnicTop);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });

    testWidgets('switching category clears the previous categorys filters', (tester) async {
      phone(tester, width: 900, height: 1000);
      final queries = <Map<String, String>>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/categories')) return response(categories);
        queries.add(request.url.queryParameters);
        return response([product()]);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(app(CategoryScreen(category: Category.fromJson(categories.first))));
        await finishLoad(tester);
        await tester.tap(find.byTooltip('Filters'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('In stock only'));
        await tester.pump();
        await tester.tap(find.textContaining('Show results'));
        await tester.pumpAndSettle();
        await finishLoad(tester);
        expect(queries.last['in_stock'], '1');

        await tester.tap(find.byKey(const ValueKey('strip-casual-wear')));
        await finishLoad(tester);

        expect(queries.last['category'], 'casual-wear');
        expect(queries.last.containsKey('in_stock'), isFalse);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });
  });
}
