import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/design/theme.dart';
import 'package:marketplace_app/design/tokens.g.dart';

/// Tests that the design system is actually wired, rather than merely present.
///
/// The web side had exactly this failure mode before: a token layer existed,
/// looked plausible, and was reached by about 3% of the UI. These assert the
/// two properties that matter — components read the generated tokens, and
/// switching theme re-resolves them.

Widget host({required bool isDark, required Widget child}) {
  return MaterialApp(
    theme: buildMaterialTheme(isDark: isDark),
    home: DsThemeScope(
      isDark: isDark,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('tokens', () {
    test('every colour has a distinct light and dark value where intended', () {
      // canvas and surface must invert; if these ever match, the dark theme has
      // silently collapsed into the light one.
      expect(DsColors.light.canvas, isNot(equals(DsColors.dark.canvas)));
      expect(DsColors.light.surface, isNot(equals(DsColors.dark.surface)));
      expect(DsColors.light.ink, isNot(equals(DsColors.dark.ink)));
    });

    test('radii are role-named and ordered', () {
      expect(DsRadius.chip, lessThan(DsRadius.control));
      expect(DsRadius.control, lessThan(DsRadius.card));
      expect(DsRadius.card, lessThan(DsRadius.panel));
      expect(DsRadius.pill, greaterThan(DsRadius.panel));
    });

    test('type scale ascends', () {
      expect(DsText.x2xs, lessThan(DsText.xs));
      expect(DsText.xs, lessThan(DsText.sm));
      expect(DsText.sm, lessThan(DsText.base));
      expect(DsText.base, lessThan(DsText.md));
      expect(DsText.md, lessThan(DsText.lg));
    });
  });

  group('DsTheme', () {
    testWidgets('exposes the light palette in light mode', (tester) async {
      late DsColors seen;
      await tester.pumpWidget(host(
        isDark: false,
        child: Builder(builder: (context) {
          seen = context.ds;
          return const SizedBox.shrink();
        }),
      ));
      expect(seen.surface, DsColors.light.surface);
    });

    testWidgets('exposes the dark palette in dark mode', (tester) async {
      late DsColors seen;
      await tester.pumpWidget(host(
        isDark: true,
        child: Builder(builder: (context) {
          seen = context.ds;
          return const SizedBox.shrink();
        }),
      ));
      expect(seen.surface, DsColors.dark.surface);
    });
  });

  group('BxButton', () {
    testWidgets('primary variant paints the primary token, not a Material default',
        (tester) async {
      await tester.pumpWidget(host(
        isDark: false,
        child: BxButton(label: 'Buy', onPressed: () {}),
      ));

      final material = tester.widget<Material>(
        find.descendant(of: find.byType(BxButton), matching: find.byType(Material)).first,
      );
      expect(material.color, DsColors.light.primary);
    });

    testWidgets('re-resolves against the dark palette', (tester) async {
      await tester.pumpWidget(host(
        isDark: true,
        child: BxButton(label: 'Buy', onPressed: () {}),
      ));

      final material = tester.widget<Material>(
        find.descendant(of: find.byType(BxButton), matching: find.byType(Material)).first,
      );
      expect(material.color, DsColors.dark.primary);
    });

    testWidgets('a loading button is not tappable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        isDark: false,
        child: BxButton(label: 'Save', loading: true, onPressed: () => taps++),
      ));

      await tester.tap(find.byType(BxButton), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('is one merged semantics node with a button role and a name',
        (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(host(
        isDark: false,
        child: BxButton(
          label: 'Checkout',
          leadingIcon: Icons.shopping_bag_outlined,
          onPressed: () {},
        ),
      ));

      // One node, not three — an icon plus a label must not be announced as
      // separate items.
      final node = tester.getSemantics(find.byType(BxButton));
      expect(node.label, 'Checkout');
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);

      handle.dispose();
    });

    testWidgets('a disabled button reports itself as disabled', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(host(
        isDark: false,
        child: const BxButton(label: 'Checkout'),
      ));

      final node = tester.getSemantics(find.byType(BxButton));
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);

      handle.dispose();
    });
  });

  group('BxField', () {
    testWidgets('always renders its label, so a control cannot ship unlabelled',
        (tester) async {
      await tester.pumpWidget(host(
        isDark: false,
        child: const BxField(label: 'Pincode', hint: '560001'),
      ));

      expect(find.text('Pincode'), findsOneWidget);
    });

    testWidgets('an error message is announced', (tester) async {
      await tester.pumpWidget(host(
        isDark: false,
        child: const BxField(label: 'Pincode', error: 'Enter 6 digits.'),
      ));

      expect(find.text('Enter 6 digits.'), findsOneWidget);
      final semantics = tester.getSemantics(find.text('Enter 6 digits.'));
      expect(semantics.flagsCollection.isLiveRegion, isTrue);
    });
  });
}
