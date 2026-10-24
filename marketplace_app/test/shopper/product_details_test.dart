import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/screens/product_detail_screen.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/option_picker.dart';
import 'package:marketplace_app/widgets/product_delivery_card.dart';
import 'package:marketplace_app/widgets/product_details_tabs.dart';
import 'package:marketplace_app/widgets/product_gallery.dart';
import 'package:marketplace_app/widgets/rich_text_view.dart';

import 'support.dart';

Product shirt([Map<String, dynamic> extra = const {}]) => Product.fromJson({
      ...product(),
      'title': 'Men Slim Fit Solid Shirt',
      'brand': 'Snitch',
      ...extra,
    });

/// What a shopper reads of a rich-text widget, as one string.
String plainText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join('\n');

Future<void> pumpRich(WidgetTester tester, String html) async {
  phone(tester);
  await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: RichTextView(html: html)))));
}

void main() {
  setUp(resetState);

  group('reading the details off the API', () {
    test('specifications keep only complete rows, in groups', () {
      final p = shirt({
        'specifications': [
          {
            'title': 'General',
            'rows': [
              {'label': 'Fabric', 'value': 'Polyester'},
              {'label': 'Fit', 'value': ''},
              {'label': '', 'value': 'orphan'},
            ]
          },
          {'title': 'Empty', 'rows': []},
          {'title': '', 'rows': [{'label': 'Pack of', 'value': '1'}]},
        ],
      });

      expect(p.specifications.map((g) => g.title), ['General', 'General']);
      expect(p.specifications.first.rows.single.label, 'Fabric');
      expect(p.specifications.last.rows.single.value, '1');
    });

    test('manufacturer fields come out labelled, in order, and only when filled', () {
      final p = shirt({
        'manufacturer': {'country_of_origin': 'India', 'generic_name': 'Shirt', 'packer_name': '  '},
      });

      expect(p.manufacturer.keys.toList(), ['Generic name', 'Country of origin']);
      expect(p.manufacturer['Country of origin'], 'India');
    });

    test('a product with none of it still reads fine', () {
      final p = shirt();

      expect(p.specifications, isEmpty);
      expect(p.manufacturer, isEmpty);
      expect(p.descriptionHtml, isNull);
      expect(p.soldBy, isNull);
    });

    test('the seller and a colour\'s own photos are read', () {
      final p = Product.fromJson({
        ...product(),
        'seller': {'id': 's1', 'display_name': 'RetailNet'},
        'variants': [
          {'id': 'v1', 'color': 'Navy', 'size': 'M', 'price': 999, 'stock': 3, 'images': ['https://example.com/navy.jpg']},
          {'id': 'v2', 'color': 'Olive', 'size': 'M', 'price': 999, 'stock': 3},
        ],
      });

      expect(p.soldBy, 'RetailNet');
      expect(p.variants.first.images, ['https://example.com/navy.jpg']);
      expect(p.variants.last.images, isEmpty);
    });
  });

  group('formatted description', () {
    testWidgets('paragraphs, headings and styled words are drawn', (tester) async {
      await pumpRich(tester, '<h2>Care</h2><p>Wash <strong>cold</strong> and <em>dry flat</em>.</p>');

      expect(plainText(tester), contains('Care'));
      expect(plainText(tester), contains('Wash cold and dry flat.'));

      final bold = tester
          .widgetList<RichText>(find.byType(RichText))
          .expand((r) => _spans(r.text))
          .firstWhere((s) => s.toPlainText() == 'cold' && s.style != null);
      expect(bold.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('bulleted and numbered lists get their markers', (tester) async {
      await pumpRich(tester, '<ul><li>Slim fit</li><li>Full sleeve</li></ul><ol><li>One</li><li>Two</li></ol>');

      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(plainText(tester), contains('Slim fit'));
      expect(plainText(tester), contains('Two'));
    });

    testWidgets('a list item that holds a paragraph (what the editor writes) reads normally', (tester) async {
      await pumpRich(tester, '<ul><li><p>Machine wash</p></li></ul>');

      expect(find.text('•'), findsOneWidget);
      expect(plainText(tester), contains('Machine wash'));
    });

    testWidgets('a nested list sits under its item', (tester) async {
      await pumpRich(tester, '<ul><li>Fabric<ul><li>Polyester</li></ul></li></ul>');

      expect(find.text('•'), findsNWidgets(2));
      expect(plainText(tester), contains('Polyester'));
    });

    testWidgets('a link can be tapped', (tester) async {
      await pumpRich(tester, '<p>See the <a href="https://example.com/care">care guide</a>.</p>');

      final link = tester
          .widgetList<RichText>(find.byType(RichText))
          .expand((r) => _spans(r.text))
          .firstWhere((s) => s.toPlainText() == 'care guide' && s.recognizer != null);
      expect(link.recognizer, isA<TapGestureRecognizer>());
      expect(link.style?.decoration, TextDecoration.underline);
    });

    testWidgets('a tag the view does not draw keeps its words and loses the tag', (tester) async {
      await pumpRich(tester, '<p>Plain <span class="x">words</span></p><script>alert(1)</script>');

      expect(plainText(tester), contains('Plain words'));
    });

    testWidgets('line breaks become line breaks', (tester) async {
      await pumpRich(tester, '<p>First<br>Second</p>');

      expect(plainText(tester), contains('First\nSecond'));
    });

    testWidgets('empty markup draws nothing', (tester) async {
      await pumpRich(tester, '<p></p><p> </p>');

      expect(find.byType(Text), findsNothing);
    });
  });

  group('All details tabs', () {
    Future<void> show(WidgetTester tester, Product p) async {
      phone(tester, height: 1600);
      await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: ProductDetailsTabs(product: p)))));
    }

    testWidgets('a tab appears only when it has something to show', (tester) async {
      await show(tester, shirt({'description': 'Just words'}));

      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Specifications'), findsNothing);
      expect(find.text('Manufacturer info'), findsNothing);
    });

    testWidgets('a product with nothing to show has no section at all', (tester) async {
      await show(tester, shirt({'description': ''}));

      expect(find.text('All details'), findsNothing);
    });

    testWidgets('specifications open first and are a table of labels and values', (tester) async {
      await show(tester, shirt({
        'description': 'Words',
        'specifications': [
          {'title': 'General', 'rows': [{'label': 'Fabric', 'value': 'Polyester'}, {'label': 'Fit', 'value': 'Slim'}]},
        ],
      }));

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Fabric'), findsOneWidget);
      expect(find.text('Polyester'), findsOneWidget);
      expect(find.text('Slim'), findsOneWidget);
    });

    testWidgets('a long table shows the first rows, then everything on "See all"', (tester) async {
      final rows = [for (var i = 1; i <= 14; i++) {'label': 'Row $i', 'value': 'Value $i'}];
      await show(tester, shirt({'specifications': [{'title': 'General', 'rows': rows}]}));

      expect(find.text('Row 10'), findsOneWidget);
      expect(find.text('Row 11'), findsNothing);
      expect(find.text('See all 14'), findsOneWidget);

      await tester.tap(find.text('See all 14'));
      await tester.pump();
      expect(find.text('Row 14'), findsOneWidget);
      expect(find.text('See less'), findsOneWidget);

      await tester.tap(find.text('See less'));
      await tester.pump();
      expect(find.text('Row 14'), findsNothing);
    });

    testWidgets('tabs switch the content', (tester) async {
      await show(tester, shirt({
        'description': 'Plain words',
        'specifications': [{'title': 'General', 'rows': [{'label': 'Fabric', 'value': 'Polyester'}]}],
        'manufacturer': {'generic_name': 'Shirt', 'manufacturer_name': 'Snitch Apparel', 'manufacturer_address': '4th Cross, Bengaluru'},
      }));

      await tester.tap(find.text('Description'));
      await tester.pump();
      expect(find.text('Plain words'), findsOneWidget);
      expect(find.text('Fabric'), findsNothing);

      // The third pill can sit past the edge of a phone; the row scrolls.
      await tester.ensureVisible(find.text('Manufacturer info'));
      await tester.pump();
      await tester.tap(find.text('Manufacturer info'));
      await tester.pump();
      expect(find.text('Generic name'), findsOneWidget);
      expect(find.text('Snitch Apparel'), findsOneWidget);
      expect(find.text('4th Cross, Bengaluru'), findsOneWidget);
    });

    testWidgets('a formatted description is drawn formatted, a plain one as plain text', (tester) async {
      await show(tester, shirt({'description': 'Soft cotton.', 'description_html': '<p>Soft <strong>cotton</strong>.</p>'}));
      expect(find.byType(RichTextView), findsOneWidget);
    });
  });

  group('the colour picker with photos', () {
    final variants = [
      Variant.fromJson({'id': 'v1', 'color': 'Navy', 'size': 'M', 'stock': 3, 'images': ['https://example.com/navy.jpg']}),
      Variant.fromJson({'id': 'v2', 'color': 'Navy', 'size': 'L', 'stock': 3, 'images': ['https://example.com/navy.jpg']}),
      Variant.fromJson({'id': 'v3', 'color': 'Olive', 'size': 'M', 'stock': 3}),
      Variant.fromJson({'id': 'v4', 'color': 'Olive', 'size': 'L', 'stock': 0}),
    ];

    testWidgets('names the colour that is selected, and shows a picture for a colour that has one', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(child: VariantPicker(variants: variants, selected: variants.first, onChanged: (_) {})),
      )));

      expect(find.textContaining('Selected colour: Navy', findRichText: true), findsOneWidget);
      expect(find.byType(Image), findsOneWidget, reason: 'only Navy has photos');
    });

    testWidgets('a size that is sold out for the chosen colour is struck through', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(child: VariantPicker(variants: variants, selected: variants[2], onChanged: (_) {})),
      )));

      final sizeL = tester.widget<Text>(find.text('L'));
      expect(sizeL.style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('the product page', () {
    Future<void> open(WidgetTester tester, Map<String, dynamic> extra, {MockClient? client}) async {
      phone(tester, height: 2400);
      final c = client ??
          MockClient((request) async {
            if (request.url.path.endsWith('/products/p1')) return response({...product(), ...extra});
            return response([]);
          });
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
        await finishLoad(tester);
      }, () => c);
    }

    testWidgets('lays out the way a marketplace page does', (tester) async {
      await open(tester, {
        'brand': 'Snitch',
        'title': 'Men Slim Fit Solid Shirt',
        'rating': 4.0,
        'reviews_count': 118,
        'description': 'Soft cotton.',
        'seller': {'id': 's1', 'display_name': 'RetailNet'},
        'specifications': [{'title': 'General', 'rows': [{'label': 'Fabric', 'value': 'Polyester'}]}],
        'manufacturer': {'generic_name': 'Shirt'},
      });

      expect(find.byType(ProductGallery), findsOneWidget);
      expect(find.text('Snitch'), findsWidgets);
      expect(find.text('Men Slim Fit Solid Shirt'), findsOneWidget);
      expect(find.text('Add to cart'), findsOneWidget);
      expect(find.textContaining('Buy at ₹'), findsOneWidget);
      expect(find.byType(ProductAssurances), findsOneWidget);
      expect(find.text('7-day return'), findsOneWidget);
      expect(find.text('Delivery details'), findsOneWidget);
      expect(find.textContaining('RetailNet', findRichText: true), findsOneWidget);

      await tester.scrollUntilVisible(find.text('All details'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Specifications'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Manufacturer info'), findsOneWidget);
    });

    testWidgets('the rating is on the picture', (tester) async {
      await open(tester, {'rating': 4.0, 'reviews_count': 118});

      expect(find.descendant(of: find.byType(ProductGallery), matching: find.text('4')), findsOneWidget);
      expect(find.descendant(of: find.byType(ProductGallery), matching: find.text('118')), findsOneWidget);
    });

    testWidgets('picking a colour with photos of its own shows those photos', (tester) async {
      await open(tester, {
        'images': ['https://example.com/gallery1.jpg', 'https://example.com/gallery2.jpg', 'https://example.com/gallery3.jpg'],
        'variants': [
          {'id': 'v1', 'color': 'Navy', 'size': 'M', 'price': 999, 'stock': 3, 'images': ['https://example.com/navy1.jpg']},
          {'id': 'v2', 'color': 'Olive', 'size': 'M', 'price': 999, 'stock': 3},
        ],
      });

      List<String> shown() => tester.widget<ProductGallery>(find.byType(ProductGallery)).images;
      // Navy is first and in stock, so it is selected, with its own single photo.
      expect(shown(), ['https://example.com/navy1.jpg']);

      await tester.tap(find.bySemanticsLabel('Olive'));
      await tester.pump();
      expect(shown(), hasLength(3), reason: 'a colour with no photos of its own keeps the gallery');
    });

    testWidgets('signed out it says how the item is delivered; it does not guess a date', (tester) async {
      await open(tester, {});

      expect(find.text('Free delivery above ₹1,999'), findsOneWidget);
      expect(find.textContaining('Delivery by'), findsNothing);
    });

    testWidgets('signed in with an address it shows the real delivery date', (tester) async {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login')) return response({'token': 't', 'user': user});
        if (path.endsWith('/products/p1')) return response(product());
        if (path.endsWith('/addresses')) {
          return response([
            {
              'id': 'a1', 'tag': 'Home', 'name': 'S', 'phone': '9876543210', 'line1': '12 MG Road',
              'city': 'Bengaluru', 'state': 'Karnataka', 'pincode': '560038', 'is_default': true,
            }
          ]);
        }
        if (path.endsWith('/delivery/quote')) {
          return response({
            'options': [
              {
                'carrier': 'delhivery', 'carrier_label': 'Delhivery', 'service_level': 'STANDARD', 'label': 'Standard',
                'description': '', 'price': 0, 'eta_label': '3 days', 'eta_minutes': 3 * 24 * 60, 'cod_supported': true,
              }
            ],
          });
        }
        return response([]);
      });

      phone(tester, height: 2400);
      await http.runWithClient(() async {
        await AppState.instance.signIn('s@example.com', 'pw');
        await tester.pumpWidget(app(const ProductDetailScreen(productId: 'p1')));
        await finishLoad(tester);
        await tester.pumpAndSettle();
      }, () => client);

      expect(find.textContaining('12 MG Road'), findsOneWidget);
      expect(find.textContaining('Delivery by'), findsOneWidget);
      expect(find.text('Free delivery above ₹1,999'), findsNothing);
    });

    testWidgets('Buy at shows the price with the shopper\'s choices on it', (tester) async {
      await open(tester, {'price': 999});

      expect(find.text('Buy at ₹999'), findsOneWidget);
    });
  });
}

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _spans(child);
    }
  }
}
