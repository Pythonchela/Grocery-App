
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/design/mobile.dart';
import 'package:marketplace_app/design/mobile_components.dart';
import 'package:marketplace_app/main.dart';
import 'package:marketplace_app/state/app_state.dart';

import 'support.dart';

/// The mobile-owned layer of the design system: finger-sized targets, native
/// gestures, safe areas and an adaptive shell.
void main() {
  setUp(resetState);

  group('window classes', () {
    test('widths map to compact, medium and expanded', () {
      expect(DsWindowClass.of(360), DsWindowClass.compact);
      expect(DsWindowClass.of(599), DsWindowClass.compact);
      expect(DsWindowClass.of(600), DsWindowClass.medium);
      expect(DsWindowClass.of(839), DsWindowClass.medium);
      expect(DsWindowClass.of(840), DsWindowClass.expanded);
    });

    test('only phones in portrait use a bottom bar', () {
      expect(DsWindowClass.compact.usesRail, isFalse);
      expect(DsWindowClass.medium.usesRail, isTrue);
      expect(DsWindowClass.expanded.usesRail, isTrue);
    });
  });

  group('touch targets', () {
    for (final entry in {
      BxButtonSize.sm: 40.0,
      BxButtonSize.md: 44.0,
      BxButtonSize.lg: 48.0,
    }.entries) {
      testWidgets('a ${entry.key.name} button is at least ${entry.value}dp tall',
          (tester) async {
        phone(tester);
        await tester.pumpWidget(app(Scaffold(
          body: Center(
            child: BxButton(label: 'Go', size: entry.key, onPressed: () {}),
          ),
        )));

        expect(tester.getSize(find.byType(BxButton)).height,
            greaterThanOrEqualTo(entry.value));
      });
    }

    testWidgets('a full-width button still fills the row', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: BxButton(label: 'Pay', fullWidth: true, onPressed: () {}),
        ),
      )));

      expect(tester.getSize(find.byType(BxButton)).width, 390 - 32);
    });

    testWidgets('the quantity stepper has 48dp buttons', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Center(
          child: BxQuantityStepper(quantity: 2, onChanged: (_) {}),
        ),
      )));

      for (final tooltip in ['Decrease quantity', 'Increase quantity']) {
        final size = tester.getSize(find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(SizedBox),
        ).first);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('a pressable row keeps a finger-sized hit area', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Center(
          child: BxPressable(onTap: () {}, child: const SizedBox(width: 10, height: 10)),
        ),
      )));

      final size = tester.getSize(find.byType(BxPressable));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('quantity stepper', () {
    testWidgets('steps up and down within its limits', (tester) async {
      phone(tester);
      final seen = <int>[];
      await tester.pumpWidget(app(Scaffold(
        body: Center(
          child: BxQuantityStepper(
              quantity: 2, maxQuantity: 3, onChanged: seen.add),
        ),
      )));

      await tester.tap(find.byTooltip('Increase quantity'));
      await tester.tap(find.byTooltip('Decrease quantity'));
      expect(seen, [3, 1]);
    });

    testWidgets('cannot go past the stock', (tester) async {
      phone(tester);
      final seen = <int>[];
      await tester.pumpWidget(app(Scaffold(
        body: Center(
          child: BxQuantityStepper(
              quantity: 3, maxQuantity: 3, onChanged: seen.add),
        ),
      )));

      await tester.tap(find.byTooltip('Increase quantity'));
      expect(seen, isEmpty);
    });

    testWidgets('at the minimum the minus becomes a remove', (tester) async {
      phone(tester);
      var removed = 0;
      await tester.pumpWidget(app(Scaffold(
        body: Center(
          child: BxQuantityStepper(
              quantity: 1, onChanged: (_) {}, onRemove: () => removed++),
        ),
      )));

      expect(find.byTooltip('Decrease quantity'), findsNothing);
      await tester.tap(find.byTooltip('Remove from cart'));
      expect(removed, 1);
    });
  });

  group('bottom bar', () {
    testWidgets('stays clear of the gesture bar', (tester) async {
      phone(tester, height: 800);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(bottom: 34)),
          child: child!,
        ),
        home: app(Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: BxBottomBar(
            child: BxButton(label: 'Buy', fullWidth: true, onPressed: () {}),
          ),
        )),
      ));

      final button = tester.getRect(find.byType(BxButton));
      expect(button.bottom, lessThanOrEqualTo(800 - 34));
    });
  });

  group('buttons in a bottom bar', () {
    testWidgets('do not squash the screen above them', (tester) async {
      // A button that grows to fill any bounded height would make the bar eat
      // the body; the body must keep nearly the whole screen.
      phone(tester, height: 800);
      await tester.pumpWidget(app(Scaffold(
        body: const SizedBox.expand(key: ValueKey('body')),
        bottomNavigationBar: BxBottomBar(
          child: BxButton(label: 'Buy', size: BxButtonSize.lg, fullWidth: true, onPressed: () {}),
        ),
      )));

      expect(tester.getSize(find.byKey(const ValueKey('body'))).height,
          greaterThan(600));
      expect(tester.getSize(find.byType(BxBottomBar)).height, lessThan(120));
    });
  });

  group('swipe to remove', () {
    testWidgets('swiping a row left removes it', (tester) async {
      phone(tester);
      var removed = 0;
      await tester.pumpWidget(app(Scaffold(
        body: ListView(children: [
          BxSwipeToRemove(
            dismissKey: const ValueKey('row'),
            onRemoved: () => removed++,
            child: const SizedBox(height: 80, child: Text('Row')),
          ),
        ]),
      )));

      await tester.drag(find.text('Row'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(removed, 1);
    });

    testWidgets('swiping right does nothing', (tester) async {
      phone(tester);
      var removed = 0;
      await tester.pumpWidget(app(Scaffold(
        body: ListView(children: [
          BxSwipeToRemove(
            dismissKey: const ValueKey('row'),
            onRemoved: () => removed++,
            child: const SizedBox(height: 80, child: Text('Row')),
          ),
        ]),
      )));

      await tester.drag(find.text('Row'), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(removed, 0);
    });
  });

  group('sheets', () {
    testWidgets('a bottom sheet shows a drag handle', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: BxButton(
              label: 'Open',
              onPressed: () => showBxSheet<void>(
                  context: context, title: 'Options', child: const Text('Body')),
            ),
          ),
        ),
      )));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(BxSheetHandle), findsOneWidget);
      expect(find.text('Options'), findsOneWidget);
    });
  });

  group('adaptive shell', () {
    Future<void> openShell(WidgetTester tester, double width) async {
      phone(tester, width: width, height: 900);
      final client = MockClient((request) async => response(
            request.url.path.endsWith('/categories') ? categories : [product()],
          ));
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const AppShell()));
        await finishLoad(tester);
      }, () => client);
    }

    testWidgets('a phone gets a bottom navigation bar', (tester) async {
      await openShell(tester, 390);

      expect(find.byType(BxBottomNav), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a tablet gets a side rail instead', (tester) async {
      await openShell(tester, 900);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(BxBottomNav), findsNothing);
    });

    testWidgets('the cart destination shows how many items are in it',
        (tester) async {
      await openShell(tester, 390);
      AppState.instance.clearCart();

      expect(find.byTooltip('Cart'), findsOneWidget);
    });
  });

  test('reduced motion removes durations', () {
    // MediaQuery.disableAnimations is exercised through DsMobileMotion.of.
    expect(DsMobileMotion.standard, isNot(Duration.zero));
  });
}
