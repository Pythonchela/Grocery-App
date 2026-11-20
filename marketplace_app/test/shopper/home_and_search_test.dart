import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/models.dart';
import 'package:marketplace_app/main.dart';
import 'package:marketplace_app/screens/category_screen.dart';
import 'package:marketplace_app/screens/home_screen.dart';
import 'package:marketplace_app/screens/search_screen.dart';
import 'package:marketplace_app/widgets/category_shortcuts.dart';
import 'package:marketplace_app/widgets/quick_home.dart';
import 'support.dart';

void main() {
  setUp(resetState);
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('category icons align and navigate at $width / $scale',
          (tester) async {
        phone(tester, width: width, height: 1200);
        Category? selected;
        await tester.pumpWidget(app(
            Scaffold(
                body: CategoryShortcuts(
              categories: categories.map(Category.fromJson).toList(),
              onSelected: (value) => selected = value,
            )),
            scale: scale));
        final first = find.byKey(const ValueKey('category-ethnic-wear'));
        final second = find.byKey(const ValueKey('category-casual-wear'));
        expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
        expect(tester.getSize(first), tester.getSize(second));
        expect(find.byIcon(Icons.checkroom_outlined), findsOneWidget);
        expect(find.byIcon(Icons.headphones_outlined), findsOneWidget);
        expect(find.byIcon(Icons.directions_walk_outlined), findsOneWidget);
        for (final category in categories) {
          await tester
              .tap(find.byKey(ValueKey('category-${category['slug']}')));
          expect(selected?.slug, category['slug']);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('home scrolls without overflow at $width / $scale',
          (tester) async {
        phone(tester, width: width);
        final client = MockClient((request) async => response(
              request.url.path.endsWith('/categories')
                  ? categories
                  : [product()],
            ));
        await http.runWithClient(() async {
          await tester.pumpWidget(app(const HomeScreen(), scale: scale));
          await finishLoad(tester);
          expect(tester.takeException(), isNull);
          for (var i = 0; i < 7; i++) {
            await tester.drag(
                find.byType(CustomScrollView), const Offset(0, -300));
            await tester.pump();
            expect(tester.takeException(), isNull, reason: 'scroll step $i');
          }
        }, () => client);
      });
    }
  }

  testWidgets('recommendation failure keeps the catalog available',
      (tester) async {
    phone(tester);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/trending')) {
        return response({}, status: 503);
      }
      return response(
          request.url.path.endsWith('/categories') ? categories : [product()]);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const HomeScreen()));
      await finishLoad(tester);
      expect(find.text('Could not reach the store'), findsNothing);
      expect(find.byType(QuickCategoryGrid), findsOneWidget);
      await tester.tap(find
          .descendant(of: find.byType(QuickCategoryGrid), matching: find.byType(InkWell))
          .first);
      await tester.pumpAndSettle();
      expect(find.byType(CategoryScreen), findsOneWidget);
    }, () => client);
  });

  testWidgets('home does not focus hidden search and empty cart returns home',
      (tester) async {
    phone(tester);
    final client = MockClient((request) async => response(
          request.url.path.endsWith('/categories') ? categories : [product()],
        ));
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const AppShell()));
      await finishLoad(tester);
      expect(find.byType(SearchScreen, skipOffstage: false), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byTooltip('Cart'));
      await tester.pumpAndSettle();
      expect(find.text('Your cart is empty'), findsOneWidget);
      await tester.tap(find.text('Start shopping'));
      await tester.pumpAndSettle();
      expect(find.text('Your cart is empty'), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    }, () => client);
  });

  testWidgets(
      'search uses backend search parameter and shows matching products',
      (tester) async {
    phone(tester);
    final queries = <String>[];
    final client = MockClient((request) async {
      expect(request.url.queryParameters.containsKey('q'), isFalse);
      queries.add(request.url.queryParameters['search']!);
      return response([product()]);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const SearchScreen()));
      await tester.enterText(find.byType(TextField), 'cotton');
      await finishLoad(tester);
      expect(queries, ['cotton']);
      expect(find.text(product()['title']), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text(product()['title']), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('clearing search ignores a late response', (tester) async {
    phone(tester);
    final pending = Completer<http.Response>();
    final client = MockClient((request) => pending.future);
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const SearchScreen()));
      await tester.enterText(find.byType(TextField), 'cotton');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Clear search'));
      pending.complete(response([product()]));
      await finishLoad(tester);
      expect(find.text(product()['title']), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => client);
  });
}
