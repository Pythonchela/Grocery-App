import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/widgets/diet_mark.dart';
import 'package:marketplace_app/widgets/product_card.dart';
import 'package:marketplace_app/widgets/product_list_row.dart';

import 'support.dart';

Product dish(Map<String, dynamic> extra) => Product.fromJson({...product(), 'title': 'Paneer Tikka', ...extra});

void main() {
  setUp(resetState);

  group('reading the mark off the API', () {
    test('veg, non-veg and egg come through; anything else is no mark', () {
      expect(dish({'diet': 'veg'}).diet, 'veg');
      expect(dish({'diet': 'non_veg'}).diet, 'non_veg');
      expect(dish({'diet': 'egg'}).diet, 'egg');
      expect(dish({'diet': 'vegan-ish'}).diet, isNull);
      expect(dish({}).diet, isNull);
    });
  });

  group('on screen', () {
    testWidgets('a vegetarian dish shows the mark in a list row and on a card', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Column(children: [
          ProductListRow(product: dish({'diet': 'veg'}), onTap: () {}),
          SizedBox(width: 180, height: 300, child: ProductCardTile(product: dish({'diet': 'non_veg'}), onTap: () {})),
        ]),
      )));

      expect(find.byType(DietMark), findsNWidgets(2));
      expect(tester.widgetList<DietMark>(find.byType(DietMark)).map((d) => d.diet), ['veg', 'non_veg']);
      expect(DietMark.labelOf('veg'), 'Vegetarian');
      expect(DietMark.labelOf('non_veg'), 'Non-vegetarian');
    });

    testWidgets('an item without a mark shows nothing extra', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(body: ProductListRow(product: dish({}), onTap: () {}))));

      expect(find.byType(DietMark), findsNothing);
      expect(find.text('Paneer Tikka'), findsOneWidget);
    });
  });
}
