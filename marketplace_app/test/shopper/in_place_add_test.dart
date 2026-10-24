import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/cart_bar.dart';
import 'package:marketplace_app/widgets/product_add_control.dart';

import 'support.dart';

/// A dish with a required Half / Full portion, like a restaurant item.
Product dish({int stock = 10}) => Product.fromJson({
      ...product(stock: stock),
      'title': 'Margherita Pizza',
      'option_groups': [
        {
          'key': 'portion',
          'label': 'Portion',
          'type': 'single',
          'required': true,
          'price_mode': 'set',
          'choices': [
            {'id': 'half', 'label': 'Half plate', 'price': 150, 'default': true},
            {'id': 'full', 'label': 'Full plate', 'price': 280},
          ],
        },
      ],
    });

Product shirtInTwoSizes() => Product.fromJson(product(options: true));

Future<void> control(WidgetTester tester, Product p) => tester.pumpWidget(app(
      Scaffold(
        body: Center(child: ProductAddControl(product: p, pill: true)),
        bottomNavigationBar: const CartBar(),
      ),
    ));

/// "Add" on a list or home card works where you are, like Swiggy or Blinkit:
/// no page change, a count on the item, and a cart strip at the bottom.
void main() {
  setUp(resetState);

  group('an item that needs a choice', () {
    testWidgets('ADD opens the choices in a sheet, not a new page', (tester) async {
      phone(tester, height: 1200);
      await control(tester, dish());

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();

      expect(find.text('Margherita Pizza'), findsOneWidget);
      expect(find.text('Half plate'), findsOneWidget);
      expect(find.text('Full plate'), findsOneWidget);
      expect(find.textContaining('Add item'), findsOneWidget);
      // Still on the same screen underneath: nothing was pushed.
      expect(AppState.instance.cart, isEmpty);
    });

    testWidgets('choosing and confirming adds that choice and shows the count',
        (tester) async {
      phone(tester, height: 1200);
      await control(tester, dish());

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full plate'));
      await tester.pumpAndSettle();
      expect(find.text('Add item · ₹280'), findsOneWidget);
      await tester.tap(find.text('Add item · ₹280'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cart.single.unitPrice, 280);
      // Sheet gone, count shown where ADD was.
      expect(find.textContaining('Add item'), findsNothing);
      expect(find.text('ADD'), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('the sheet opens on the default choice and adds it as is',
        (tester) async {
      phone(tester, height: 1200);
      await control(tester, dish());

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add item · ₹150'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cart.single.unitPrice, 150);
    });

    testWidgets('closing the sheet adds nothing', (tester) async {
      phone(tester, height: 1200);
      await control(tester, dish());

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // the dimmed area outside
      await tester.pumpAndSettle();

      expect(AppState.instance.cart, isEmpty);
      expect(find.text('ADD'), findsOneWidget);
    });

    testWidgets('"+" reopens the sheet on what was added, so repeating is one tap',
        (tester) async {
      phone(tester, height: 1200);
      await control(tester, dish());

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full plate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add item · ₹280'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add one more'));
      await tester.pumpAndSettle();
      expect(find.text('Add item · ₹280'), findsOneWidget); // remembered
      await tester.tap(find.text('Add item · ₹280'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cart.single.quantity, 2);
    });

    testWidgets('different choices are separate lines but one count', (tester) async {
      phone(tester, height: 1200);
      await control(tester, dish());

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add item · ₹150'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add one more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full plate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add item · ₹280'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cart.length, 2);
      expect(find.text('2'), findsWidgets); // the count on the item
    });

    testWidgets('"-" takes one off the line added last', (tester) async {
      phone(tester, height: 1200);
      await control(tester, dish());

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add item · ₹150'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove one'));
      await tester.pumpAndSettle();

      expect(AppState.instance.cart, isEmpty);
      expect(find.text('ADD'), findsOneWidget);
    });

    testWidgets('a product with several sizes asks for one in the sheet',
        (tester) async {
      phone(tester, height: 1200);
      await control(tester, shirtInTwoSizes());

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Add item'), findsOneWidget);
      expect(AppState.instance.cart, isEmpty);
    });
  });

  group('a plain item', () {
    testWidgets('adds in place with no message and no new page', (tester) async {
      phone(tester);
      await control(tester, Product.fromJson(product()));

      await tester.tap(find.text('ADD'));
      await tester.pump();

      expect(AppState.instance.cart.single.quantity, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('cart strip', () {
    testWidgets('is absent while the cart is empty', (tester) async {
      phone(tester);
      await control(tester, Product.fromJson(product()));

      expect(find.text('View cart'), findsNothing);
    });

    testWidgets('appears with the count and the total, and follows changes',
        (tester) async {
      phone(tester);
      await control(tester, Product.fromJson(product()));

      await tester.tap(find.text('ADD'));
      await tester.pump();
      expect(find.text('1 item · ₹999'), findsOneWidget);
      expect(find.text('View cart'), findsOneWidget);

      await tester.tap(find.byTooltip('Add one more'));
      await tester.pump();
      expect(find.text('2 items · ₹1,998'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove one'));
      await tester.tap(find.byTooltip('Remove one'));
      await tester.pump();
      expect(find.text('View cart'), findsNothing);
    });

    testWidgets('tapping it opens the cart', (tester) async {
      phone(tester, height: 1200);
      await control(tester, Product.fromJson(product()));
      await tester.tap(find.text('ADD'));
      await tester.pump();

      await tester.tap(find.text('View cart'));
      await tester.pumpAndSettle();

      expect(find.text('View cart'), findsNothing); // we are on the cart now
    });

    testWidgets('the home shell can take over what tapping it does', (tester) async {
      phone(tester);
      var opened = false;
      await tester.pumpWidget(app(Scaffold(
        bottomNavigationBar: CartBar(onOpen: () => opened = true),
      )));
      AppState.instance.addToCart(Product.fromJson(product()));
      await tester.pump();

      await tester.tap(find.text('View cart'));
      expect(opened, isTrue);
    });
  });
}
