import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/storefront.dart';
import 'package:marketplace_app/screens/home_screen.dart';
import 'support.dart';

/// The admin designs the home page, but a half-finished layout must never leave a
/// shopper with a blank home: a one-card layout is how the store once looked empty.
void main() {
  setUp(resetState);

  group('what is worth drawing', () {
    HomeSection section(String type, {String? image, String title = ''}) =>
        HomeSection.tryParse({
          'id': type + (image ?? ''),
          'type': type,
          'title': title,
          'image_url': image
        })!;

    test('a hero or banner with no picture is left out', () {
      final plan = HomeLayout.plan([
        section('HERO', title: 'Hero Banner'),
        section('BANNER'),
      ]);

      expect(plan.sections, isEmpty);
      expect(plan.isEmpty, isTrue);
    });

    test(
        'a layout with no category grid or product row says the shop\'s goods must follow',
        () {
      final plan = HomeLayout.plan(
          [section('HERO', image: 'https://x/y.jpg'), section('TRUST')]);

      expect(plan.sections, hasLength(2));
      expect(plan.needsCatalogue, isTrue);
    });

    test('a layout that shows goods needs nothing added', () {
      expect(
          HomeLayout.plan([section('CATEGORY_GRID')]).needsCatalogue, isFalse);
      expect(HomeLayout.plan([section('PRODUCT_ROW')]).needsCatalogue, isFalse);
    });

    test(
        'a reels section the admin placed is remembered, so reels are not shown twice',
        () {
      expect(HomeLayout.plan([section('REELS')]).hasReelsSection, isTrue);
      expect(HomeLayout.plan([section('TRUST')]).hasReelsSection, isFalse);
    });

    test('an empty layout is empty', () {
      expect(HomeLayout.plan(const []).isEmpty, isTrue);
    });
  });

  MockClient serving(List<Map<String, dynamic>> layout) =>
      MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/storefront/sections')) return response(layout);
        if (path.endsWith('/categories')) return response(categories);
        if (path.endsWith('/reels')) return response([]);
        return response([product()]);
      });

  testWidgets(
      'a layout that is only a pictureless hero shows the built-in home',
      (tester) async {
    phone(tester);
    final client = serving([
      {'id': '1', 'type': 'HERO', 'title': 'Hero Banner', 'image_url': null},
    ]);

    await http.runWithClient(() async {
      await tester.pumpWidget(app(const HomeScreen()));
      await finishLoad(tester);

      expect(find.text('Hero Banner'), findsNothing);
      expect(find.text('Popular right now'), findsOneWidget);
    }, () => client);
  });

  testWidgets(
      'a layout with a picture but no goods gets the shop\'s lists under it',
      (tester) async {
    phone(tester);
    final client = serving([
      {
        'id': '1',
        'type': 'BANNER',
        'title': 'Diwali sale',
        'image_url': 'https://example.com/b.png'
      },
    ]);

    await http.runWithClient(() async {
      await tester.pumpWidget(app(const HomeScreen()));
      await finishLoad(tester);

      expect(find.text('Diwali sale'), findsOneWidget);
      expect(find.text('Popular right now'), findsOneWidget);
    }, () => client);
  });

  testWidgets('a layout that already shows goods is left exactly as designed',
      (tester) async {
    phone(tester);
    final client = serving([
      {'id': '1', 'type': 'PRODUCT_ROW', 'source': 'new', 'title': 'Fresh in'},
    ]);

    await http.runWithClient(() async {
      await tester.pumpWidget(app(const HomeScreen()));
      await finishLoad(tester);

      expect(find.text('Fresh in'), findsOneWidget);
      expect(find.text('Popular right now'), findsNothing);
    }, () => client);
  });
}
