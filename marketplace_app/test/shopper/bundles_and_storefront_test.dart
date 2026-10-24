import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/bundles.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/data/storefront.dart';
import 'package:marketplace_app/design/theme_overrides.dart';
import 'package:marketplace_app/design/tokens.g.dart';

import 'support.dart';

Map<String, dynamic> _product(String id, double price) => {
      ...product(id: id),
      'price': price,
      'variants': [
        {'id': '$id-v', 'color': 'Blue', 'size': 'M', 'price': price, 'stock': 9},
      ],
    };

CartLine _line(String id, double price, [int qty = 1]) {
  final p = Product.fromJson(_product(id, price));
  return CartLine(product: p, variant: p.variants.first, quantity: qty);
}

Bundle _bundle(String a, double pa, String b, double pb, double price,
    {String id = 'b1'}) {
  return Bundle.tryParse({
    'id': id,
    'name': 'Pair',
    'bundle_price': price,
    'compare_at_price': pa + pb,
    'savings': pa + pb - price,
    'products': [_product(a, pa), _product(b, pb)],
  })!;
}

void main() {
  group('bundle pricing — kept identical to the server', () {
    test('a complete pair earns the saving', () {
      final bundle = _bundle('a', 1000, 'b', 500, 1200);
      final cart = [_line('a', 1000), _line('b', 500)];

      expect(BundlePricing.discount(cart, [bundle]), 300);
      expect(BundlePricing.apply(cart, [bundle]).single.pairs, 1);
    });

    test('only whole pairs are discounted', () {
      final bundle = _bundle('a', 1000, 'b', 500, 1200);
      final cart = [_line('a', 1000, 3), _line('b', 500)];

      expect(BundlePricing.discount(cart, [bundle]), 300);
    });

    test('two pairs earn twice the saving', () {
      final bundle = _bundle('a', 1000, 'b', 500, 1200);
      final cart = [_line('a', 1000, 2), _line('b', 500, 2)];

      expect(BundlePricing.discount(cart, [bundle]), 600);
    });

    test('half a bundle earns nothing', () {
      final bundle = _bundle('a', 1000, 'b', 500, 1200);

      expect(BundlePricing.discount([_line('a', 1000)], [bundle]), 0);
    });

    test('a bundle priced above its parts never raises the total', () {
      final bundle = _bundle('a', 1000, 'b', 500, 2000);
      final cart = [_line('a', 1000), _line('b', 500)];

      expect(BundlePricing.discount(cart, [bundle]), 0);
    });

    test('a shared product goes to the bundle that saves the most', () {
      final small = _bundle('a', 1000, 'b', 500, 1400, id: 'small');
      final big = _bundle('a', 1000, 'c', 800, 1300, id: 'big');
      final cart = [_line('a', 1000), _line('b', 500), _line('c', 800)];

      final applied = BundlePricing.apply(cart, [small, big]);

      expect(applied.single.bundle.id, 'big');
      expect(applied.single.discount, 500);
    });

    test('a half-complete bundle is suggested', () {
      final bundle = _bundle('a', 1000, 'b', 500, 1200);

      expect(BundlePricing.suggestions([_line('a', 1000)], [bundle]), [bundle]);
      expect(
          BundlePricing.suggestions(
              [_line('a', 1000), _line('b', 500)], [bundle]),
          isEmpty);
    });

    test('a malformed bundle is skipped rather than breaking the list', () {
      expect(Bundle.tryParse({'id': 'x', 'products': []}), isNull);
      expect(Bundle.tryParse({'id': 'x'}), isNull);
    });
  });

  group('storefront layout', () {
    test('sections are read in order and unknown types are dropped', () {
      final sections = HomeSection.parseList([
        {'id': '1', 'type': 'HERO', 'title': 'Big sale', 'image_url': 'https://x/y.jpg'},
        {'id': '2', 'type': 'HOLOGRAM', 'title': 'From the future'},
        {'id': '3', 'type': 'PRODUCT_ROW', 'source': 'deals', 'title': ''},
      ]);

      expect(sections.map((s) => s.type), [HomeSectionType.hero, HomeSectionType.productRow]);
      expect(sections.first.title, 'Big sale');
      expect(sections.last.source, 'deals');
      expect(sections.last.title, isEmpty);
    });

    test('anything that is not a list yields an empty layout', () {
      expect(HomeSection.parseList(null), isEmpty);
      expect(HomeSection.parseList({'oops': true}), isEmpty);
    });

    test('links resolve to screens the app can open', () {
      expect(HomeLink.parse('/category/ethnic-wear'), isA<CategoryLink>());
      expect((HomeLink.parse('https://rentalmoney.in/category/shoes') as CategoryLink).slug, 'shoes');
      expect((HomeLink.parse('/product/abc') as ProductLink).id, 'abc');
      expect((HomeLink.parse('/search?q=saree') as SearchLink).query, 'saree');
      expect(HomeLink.parse('/reels'), isA<ReelsLink>());
    });

    test('links the app cannot open are ignored', () {
      expect(HomeLink.parse(null), isNull);
      expect(HomeLink.parse(''), isNull);
      expect(HomeLink.parse('/'), isNull);
      expect(HomeLink.parse('/admin'), isNull);
    });
  });

  group('admin colours', () {
    tearDown(DsPalette.reset);

    test('valid overrides replace only the tokens they name', () {
      DsPalette.applyFromApi({
        'colors': {'accent': '#FF0000'},
        'colors_dark': {'canvas': '#101010'},
      });

      expect(DsPalette.light.accent, const Color(0xFFFF0000));
      expect(DsPalette.light.surface, DsColors.light.surface);
      expect(DsPalette.dark.canvas, const Color(0xFF101010));
      expect(DsPalette.dark.accent, DsColors.dark.accent);
    });

    test('anything that is not a six-digit hex colour is ignored', () {
      DsPalette.applyFromApi({
        'colors': {
          'accent': 'red',
          'ink': '#12345',
          'surface': 'url(javascript:alert(1))',
          'canvas': '#abcdef',
        },
      });

      expect(DsPalette.light.accent, DsColors.light.accent);
      expect(DsPalette.light.ink, DsColors.light.ink);
      expect(DsPalette.light.surface, DsColors.light.surface);
      expect(DsPalette.light.canvas, const Color(0xFFABCDEF));
    });

    test('names the admin panel uses map onto the app tokens', () {
      DsPalette.applyFromApi({
        'colors': {'surface-muted': '#111111', 'on-accent': '#222222', 'new': '#333333'},
      });

      expect(DsPalette.light.surfaceMuted, const Color(0xFF111111));
      expect(DsPalette.light.onAccent, const Color(0xFF222222));
      expect(DsPalette.light.newColor, const Color(0xFF333333));
    });

    test('no theme means the shipped colours', () {
      DsPalette.applyFromApi({'colors': {'accent': '#FF0000'}});
      DsPalette.applyFromApi(null);

      expect(DsPalette.light.accent, DsColors.light.accent);
    });
  });
}
