import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/widgets/product_add_control.dart';
import 'package:marketplace_app/widgets/product_card.dart';
import 'package:marketplace_app/widgets/quick_home.dart';

import 'support.dart';

Product dish(Map<String, dynamic> extra) => Product.fromJson({...product(), ...extra});

void main() {
  setUp(resetState);

  group('how soon', () {
    test('is the range of the preparation times the products declare', () {
      final items = [
        dish({'delivery_info': {'profile': 'instant', 'prep_minutes': 15}}),
        dish({'delivery_info': {'profile': 'instant', 'prep_minutes': 25}}),
        dish({}),
      ];
      expect(readyRange(items), '15–25 min');
      expect(readyRange([items.first]), '15 min');
    });

    test('says nothing when no product declares one', () {
      expect(readyRange([dish({})]), isNull);
    });
  });

  group('the product tile', () {
    test('shows a pack size only when there is exactly one and it says something', () {
      expect(ProductCardTile.unitOf(dish({'variants': [{'id': 'v', 'color': '', 'size': '500 g', 'stock': 3}]})), '500 g');
      expect(ProductCardTile.unitOf(dish({'variants': [{'id': 'v', 'color': '', 'size': 'Free Size', 'stock': 3}]})), isNull);
      expect(
          ProductCardTile.unitOf(dish({
            'variants': [
              {'id': 'v1', 'color': '', 'size': '250 g', 'stock': 3},
              {'id': 'v2', 'color': '', 'size': '500 g', 'stock': 3},
            ]
          })),
          '2 options');
    });

    testWidgets('has the ADD button on the picture, and how soon it is ready', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: SizedBox(
          width: 170,
          height: 300,
          child: ProductCardTile(
            product: dish({
              'delivery_info': {'profile': 'instant', 'prep_minutes': 20},
              'variants': [{'id': 'v', 'color': '', 'size': '1 kg', 'stock': 5}],
            }),
            onTap: () {},
          ),
        ),
      )));

      expect(find.byType(ProductAddControl), findsOneWidget);
      expect(find.text('ADD'), findsOneWidget);
      expect(find.text('20 MIN'), findsOneWidget);
      expect(find.text('1 kg'), findsOneWidget);
    });
  });
}
