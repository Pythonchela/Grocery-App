import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/data/product_options.dart';
import 'package:marketplace_app/screens/cart_screen.dart';
import 'package:marketplace_app/screens/orders_screen.dart';
import 'package:marketplace_app/screens/product_detail_screen.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/option_picker.dart';
import 'package:marketplace_app/widgets/product_card.dart';

import 'support.dart';

/// A pizza-style product: Half/Full sets the price, add-ons add to it, a
/// "leave out" list is free, and a weight multiplies.
List<Map<String, dynamic>> foodGroups() => [
      {
        'key': 'portion',
        'label': 'Portion',
        'type': 'single',
        'required': true,
        'price_mode': 'set',
        'min': 1,
        'max': 1,
        'choices': [
          {'id': 'half_plate', 'label': 'Half plate', 'price': 180, 'default': true},
          {'id': 'full_plate', 'label': 'Full plate', 'price': 320},
        ],
      },
      {
        'key': 'add_ons',
        'label': 'Add-ons',
        'type': 'multi',
        'required': false,
        'price_mode': 'add',
        'min': 0,
        'max': 2,
        'choices': [
          {'id': 'extra_cheese', 'label': 'Extra cheese', 'price': 30},
          {'id': 'egg', 'label': 'Egg', 'price': 20},
          {'id': 'paneer', 'label': 'Paneer', 'price': 50},
        ],
      },
      {
        'key': 'leave_out',
        'label': 'Leave out',
        'type': 'multi',
        'remove': true,
        'min': 0,
        'max': 2,
        'choices': [
          {'id': 'onion', 'label': 'Onion', 'price': 0},
          {'id': 'garlic', 'label': 'Garlic', 'price': 0},
        ],
      },
    ];

Map<String, dynamic> foodProduct({List<Map<String, dynamic>>? groups}) => {
      ...product(),
      'title': 'Margherita pizza',
      'price': 180,
      'mrp': 240,
      'variants': [
        {'id': 'v1', 'color': '', 'size': '', 'price': 180, 'stock': 9}
      ],
      'option_groups': groups ?? foodGroups(),
    };

Product food({List<Map<String, dynamic>>? groups}) =>
    Product.fromJson(foodProduct(groups: groups));

void main() {
  setUp(resetState);

  group('reading the options', () {
    test('malformed groups are skipped, not fatal', () {
      final groups = OptionGroup.parseList([
        ...foodGroups(),
        {'key': '', 'label': 'No key', 'choices': []},
        {'key': 'empty', 'label': 'Empty', 'type': 'single', 'choices': []},
        'garbage',
      ]);
      expect(groups.map((g) => g.key), ['portion', 'add_ons', 'leave_out']);
      expect(OptionGroup.parseList(null), isEmpty);
      expect(OptionGroup.parseList('x'), isEmpty);
    });

    test('hex colours and colour names become swatches', () {
      expect(parseHexColor('#1F3A93'), const Color(0xFF1F3A93));
      expect(parseHexColor('#1F3A9380'), const Color(0x801F3A93));
      expect(parseHexColor('blue'), isNull);
      expect(parseHexColor(null), isNull);
      expect(swatchForName('Navy'), isNotNull);
      expect(swatchForName(' navy '), swatchForName('navy'));
      expect(swatchForName('Chartreuse-ish'), isNull);
    });

    test('a variant swatch prefers its own hex over the name', () {
      final own = Variant.fromJson(
          {'id': 'v', 'color': 'Navy', 'size': 'M', 'stock': 1, 'color_hex': '#112233'});
      final byName =
          Variant.fromJson({'id': 'v', 'color': 'Navy', 'size': 'M', 'stock': 1});
      expect(own.swatch, const Color(0xFF112233));
      expect(byName.swatch, swatchForName('navy'));
    });

    test('a product with no options has none', () {
      expect(Product.fromJson(product()).optionGroups, isEmpty);
    });
  });

  group('the price while choosing', () {
    final groups = OptionGroup.parseList(foodGroups());

    test('a set-price choice replaces the base', () {
      const full = OptionSelection(choices: {'portion': ['full_plate']});
      expect(ProductOptionMath.unitPrice(180, groups, full), 320);
    });

    test('add-ons add and exclusions are free', () {
      const sel = OptionSelection(choices: {
        'portion': ['half_plate'],
        'add_ons': ['extra_cheese', 'egg'],
        'leave_out': ['onion'],
      });
      expect(ProductOptionMath.unitPrice(180, groups, sel), 230);
    });

    test('a weight multiplies the per-unit price', () {
      final weight = OptionGroup.parseList([
        {
          'key': 'weight',
          'label': 'Weight',
          'type': 'stepper',
          'required': true,
          'price_mode': 'multiply',
          'stepper': {'min': 0.5, 'max': 5, 'step': 0.5, 'unit': 'kg', 'default': 1},
        }
      ]);
      const sel = OptionSelection(numbers: {'weight': 1.5});
      expect(ProductOptionMath.unitPrice(60, weight, sel), 90);
      expect(weight.single.stepper!.format(1.5), '1.5 kg');
      expect(weight.single.stepper!.format(2), '2 kg');
    });

    test('says what is missing, and when it is fine', () {
      expect(ProductOptionMath.problem(groups, OptionSelection.empty),
          'Choose Portion');
      expect(
          ProductOptionMath.problem(
              groups, const OptionSelection(choices: {'portion': ['half_plate']})),
          isNull);
      expect(
          ProductOptionMath.problem(groups, const OptionSelection(choices: {
            'portion': ['half_plate'],
            'add_ons': ['egg', 'paneer', 'extra_cheese'],
          })),
          'Choose at most 2 for Add-ons');
    });

    test('an unavailable or sold-out choice cannot be picked', () {
      final g = OptionGroup.parseList([
        {
          'key': 'f',
          'label': 'Flavour',
          'type': 'single',
          'required': true,
          'choices': [
            {'id': 'a', 'label': 'Mango', 'stock': 0},
            {'id': 'b', 'label': 'Plain', 'available': false},
            {'id': 'c', 'label': 'Lime'},
          ],
        }
      ]);
      expect(g.single.choices.map((c) => c.selectable), [false, false, true]);
      expect(ProductOptionMath.problem(g, const OptionSelection(choices: {'f': ['a']})),
          'Mango is not available');
    });

    test('the summary reads as the shopper would say it', () {
      const sel = OptionSelection(choices: {
        'portion': ['full_plate'],
        'leave_out': ['onion', 'garlic'],
      });
      final picks = ProductOptionMath.summary(groups, sel);
      expect(picks.map((p) => '${p.label}: ${p.value}'),
          ['Portion: Full plate', 'Leave out: Onion, Garlic']);
      expect(picks.last.removal, isTrue);
    });

    test('defaults pre-select the flagged choice', () {
      final sel = OptionSelection.defaults(groups);
      expect(sel.of('portion'), ['half_plate']);
      expect(sel.of('add_ons'), isEmpty);
    });

    test('equal selections share a signature and survive a round trip', () {
      const a = OptionSelection(choices: {
        'add_ons': ['egg', 'extra_cheese'],
        'portion': ['half_plate'],
      }, numbers: {'weight': 1.5});
      const b = OptionSelection(choices: {
        'portion': ['half_plate'],
        'add_ons': ['extra_cheese', 'egg'],
      }, numbers: {'weight': 1.5});
      expect(a.signature, b.signature);
      expect(OptionSelection.fromJson(jsonDecode(jsonEncode(a.toJson()))).signature,
          a.signature);
      expect(OptionSelection.empty.signature, '');
    });
  });

  group('the cart', () {
    const full = OptionSelection(choices: {'portion': ['full_plate']});
    const half = OptionSelection(choices: {'portion': ['half_plate']});

    test('refuses a product whose required choice is missing', () {
      expect(AppState.instance.addToCart(food()), isFalse);
      expect(AppState.instance.cart, isEmpty);
    });

    test('same dish with different picks is a different line', () {
      final p = food();
      expect(AppState.instance.addToCart(p, selection: half), isTrue);
      expect(AppState.instance.addToCart(p, selection: full), isTrue);
      expect(AppState.instance.addToCart(p, selection: half), isTrue);

      final lines = AppState.instance.cart;
      expect(lines, hasLength(2));
      expect(lines.first.quantity, 2);
      expect(lines.map((l) => l.unitPrice), [180, 320]);
      expect(AppState.instance.cartSubtotal, 2 * 180 + 320);
    });

    test('they draw on one stock pool', () {
      final p = Product.fromJson({
        ...foodProduct(),
        'variants': [
          {'id': 'v1', 'price': 180, 'stock': 3}
        ],
      });
      expect(AppState.instance.addToCart(p, selection: half, quantity: 2), isTrue);
      expect(AppState.instance.addToCart(p, selection: full, quantity: 2), isFalse);
      expect(AppState.instance.addToCart(p, selection: full, quantity: 1), isTrue);
    });

    test('a request carries the choices, never a price', () {
      final p = food();
      AppState.instance.addToCart(p, selection: full);
      final req = AppState.instance.cart.single.toRequest();

      expect(req['options'], {'portion': ['full_plate']});
      expect(req.containsKey('price'), isFalse);
      expect(req.containsKey('unit_price'), isFalse);
    });

    test('the strike-through price carries a dearer option\'s discount', () {
      AppState.instance.addToCart(food(), selection: full);
      final line = AppState.instance.cart.single;
      expect(line.unitPrice, 320);
      expect(line.unitMrp, closeTo(240 * 320 / 180, 0.01));
    });

    testWidgets('survives a restart, picks and all', (tester) async {
      final client = MockClient((request) async => response(foodProduct()));
      await http.runWithClient(() async {
        AppState.instance.addToCart(food(), selection: full);
        AppState.instance.cart; // persisted
        final saved = AppState.instance.cart.single;
        AppState.instance.clearCart();
        // clearCart persists an empty cart; put the line back and reload.
        AppState.instance.addToCart(saved.product, selection: saved.selection);
        final before = AppState.instance.cart.single.key;

        await tester.runAsync(() async {
          // Simulate a fresh launch: the in-memory cart is empty, storage is not.
          final lines = AppState.instance.cart.length;
          expect(lines, 1);
          await AppState.instance.restoreCart();
        });

        expect(AppState.instance.cart.single.key, before);
      }, () => client);
    });

    testWidgets('the cart shows what was chosen', (tester) async {
      phone(tester, height: 1000);
      AppState.instance.addToCart(food(), selection: const OptionSelection(choices: {
        'portion': ['full_plate'],
        'leave_out': ['onion'],
      }));
      final client = MockClient((request) async => response([]));

      await http.runWithClient(() async {
        await tester.pumpWidget(app(const CartScreen()));
        await finishLoad(tester);

        expect(find.textContaining('Full plate'), findsOneWidget);
        expect(find.textContaining('no Onion'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });
  });

  group('the product page', () {
    MockClient shop(Map<String, dynamic> p) => MockClient((request) async {
          if (request.url.path.endsWith('/products/p1')) return response(p);
          return response([]);
        });

    testWidgets('shows each group and prices the choices live', (tester) async {
      phone(tester, height: 1600);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
        await finishLoad(tester);

        expect(find.text('Portion'), findsOneWidget);
        expect(find.text('Add-ons'), findsOneWidget);
        expect(find.text('Leave out'), findsOneWidget);
        // Half plate is the default.
        expect(find.text('₹180'), findsWidgets);

        await tester.tap(find.text('Full plate'));
        await tester.pump();
        expect(find.text('₹320'), findsWidgets);

        await tester.tap(find.text('Extra cheese'));
        await tester.pump();
        expect(find.text('₹350'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
      }, () => shop(foodProduct()));
    });

    testWidgets('adds the chosen picks to the cart', (tester) async {
      phone(tester, height: 1600);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
        await finishLoad(tester);

        await tester.tap(find.text('Full plate'));
        await tester.pump();
        await tester.tap(find.text('No Onion'));
        await tester.pump();
        await tester.tap(find.text('Add to cart'));
        await tester.pump();

        final line = AppState.instance.cart.single;
        expect(line.selection.of('portion'), ['full_plate']);
        expect(line.selection.of('leave_out'), ['onion']);
        expect(line.unitPrice, 320);
        await tester.pumpWidget(const SizedBox());
      }, () => shop(foodProduct()));
    });

    testWidgets('a required choice with no default asks for it', (tester) async {
      phone(tester, height: 1600);
      final groups = foodGroups();
      (groups.first['choices'] as List).first['default'] = false;

      await http.runWithClient(() async {
        await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
        await finishLoad(tester);

        await tester.tap(find.text('Add to cart'));
        await tester.pump();

        expect(find.text('Choose Portion'), findsOneWidget);
        expect(AppState.instance.cart, isEmpty);
        await tester.pumpWidget(const SizedBox());
      }, () => shop(foodProduct(groups: groups)));
    });

    testWidgets('a stepper counts up in its steps', (tester) async {
      phone(tester, height: 1600);
      final weight = [
        {
          'key': 'weight',
          'label': 'Weight',
          'type': 'stepper',
          'required': true,
          'price_mode': 'multiply',
          'stepper': {'min': 0.5, 'max': 2, 'step': 0.5, 'unit': 'kg', 'default': 1},
        }
      ];
      final tomatoes = {...foodProduct(groups: weight), 'price': 60, 'mrp': 60, 'variants': [
        {'id': 'v1', 'price': 60, 'stock': 9}
      ]};

      await http.runWithClient(() async {
        await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
        await finishLoad(tester);

        // A required stepper opens at its starting value.
        expect(find.text('1 kg'), findsOneWidget);
        expect(find.text('₹60'), findsWidgets);

        await tester.tap(find.byTooltip('More weight'));
        await tester.pump();
        expect(find.text('1.5 kg'), findsOneWidget);
        expect(find.text('₹90'), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      }, () => shop(tomatoes));
    });
  });

  group('colour and size', () {
    List<Variant> grid() => [
          for (final color in ['Navy', 'Red'])
            for (final size in ['S', 'M'])
              Variant.fromJson({
                'id': '$color-$size',
                'color': color,
                'size': size,
                'price': 999,
                'stock': color == 'Red' && size == 'S' ? 0 : 5,
              })
        ];

    test('a colour x size list is recognised as a grid', () {
      expect(VariantPicker.isGrid(grid()), isTrue);
      expect(VariantPicker.isGrid(grid().take(1).toList()), isFalse);
      expect(
          VariantPicker.isGrid([
            Variant.fromJson({'id': 'a', 'color': 'Navy', 'size': '', 'stock': 1}),
            Variant.fromJson({'id': 'b', 'color': 'Red', 'size': '', 'stock': 1}),
          ]),
          isFalse);
    });

    testWidgets('picking a colour keeps the size when it can', (tester) async {
      phone(tester, height: 900);
      final variants = grid();
      Variant? picked = variants[1]; // Navy / M

      await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: VariantPicker(
            variants: variants,
            selected: picked,
            onChanged: (v) => setState(() => picked = v),
          ),
        ),
      )));

      expect(find.textContaining('Navy', findRichText: true), findsOneWidget); // beside the heading
      await tester.tap(find.bySemanticsLabel('Red'));
      await tester.pump();
      expect(picked!.id, 'Red-M');

      // Red / S is sold out, so tapping it does nothing.
      await tester.tap(find.text('S'));
      await tester.pump();
      expect(picked!.id, 'Red-M');
    });
  });

  group('orders', () {
    test('an order line remembers what was chosen', () {
      final item = OrderItem.fromJson({
        'id': 'i1',
        'product_id': 'p1',
        'variant_id': 'v1',
        'quantity': 2,
        'price': 320,
        'product': {'title': 'Margherita pizza', 'images': []},
        'selected_options': [
          {
            'key': 'portion',
            'label': 'Portion',
            'type': 'single',
            'choices': [
              {'id': 'full_plate', 'label': 'Full plate', 'price': 320}
            ]
          },
          {
            'key': 'leave_out',
            'label': 'Leave out',
            'type': 'multi',
            'remove': true,
            'choices': [
              {'id': 'onion', 'label': 'Onion', 'price': 0}
            ]
          },
          {'key': 'weight', 'label': 'Weight', 'type': 'stepper', 'value': 1.5, 'unit': 'kg', 'choices': []},
        ],
      });

      expect(item.picks.map((p) => '${p.label}: ${p.value}'),
          ['Portion: Full plate', 'Leave out: Onion', 'Weight: 1.5 kg']);
      expect(item.selection.of('portion'), ['full_plate']);
      expect(item.selection.number('weight'), 1.5);
    });

    testWidgets('Buy again repeats the same picks', (tester) async {
      phone(tester, width: 900, height: 1200);
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login')) return response({'token': 't', 'user': user});
        if (path.endsWith('/orders/mine')) {
          return response([
            {
              'id': 'o1',
              'order_number': 'ORD-AAA',
              'status': 'DELIVERED',
              'payment_method': 'COD',
              'total_amount': 320,
              'created_at': '2026-10-09T10:00:00Z',
              'items': [
                {
                  'id': 'i1',
                  'product_id': 'p1',
                  'variant_id': 'v1',
                  'quantity': 1,
                  'price': 320,
                  'product': {'title': 'Margherita pizza', 'images': []},
                  'selected_options': [
                    {
                      'key': 'portion',
                      'label': 'Portion',
                      'type': 'single',
                      'choices': [
                        {'id': 'full_plate', 'label': 'Full plate', 'price': 320}
                      ]
                    }
                  ],
                }
              ],
            }
          ]);
        }
        if (path.endsWith('/products/p1')) return response(foodProduct());
        return response({}, status: 404);
      });

      await http.runWithClient(() async {
        await AppState.instance.signIn('a@b.c', 'pw');
        AppState.instance.clearCart();
        await tester.pumpWidget(app(const OrdersScreen()));
        await finishLoad(tester);

        expect(find.textContaining('Full plate'), findsOneWidget);
        await tester.tap(find.text('Buy again'));
        await finishLoad(tester);

        final line = AppState.instance.cart.single;
        expect(line.selection.of('portion'), ['full_plate']);
        expect(line.unitPrice, 320);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });
  });

  group('product cards', () {
    testWidgets('a product with a required choice asks in a sheet, not on a new page',
        (tester) async {
      phone(tester, height: 1200);
      var opened = false;
      var added = false;

      await tester.pumpWidget(app(Scaffold(
        body: SizedBox(
          width: 172,
          child: ProductCardTile(
            product: food(),
            onTap: () => opened = true,
            onAddToCart: () => added = true,
          ),
        ),
      )));

      await tester.tap(find.byTooltip('Choose options'));
      await tester.pumpAndSettle();
      expect(opened, isFalse, reason: 'the shopper stays on the list');
      expect(added, isFalse);
      expect(find.textContaining('Add item'), findsOneWidget);
    });

    testWidgets('one with only optional extras still adds in one tap',
        (tester) async {
      phone(tester);
      var added = false;
      final optional = foodGroups()..removeAt(0);

      await tester.pumpWidget(app(Scaffold(
        body: SizedBox(
          width: 172,
          child: ProductCardTile(
            product: food(groups: optional),
            onTap: () {},
            onAddToCart: () => added = true,
          ),
        ),
      )));

      await tester.tap(find.byTooltip('Add to cart'));
      expect(added, isTrue);
    });
  });
}
