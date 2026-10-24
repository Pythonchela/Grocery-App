import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/design/brand.g.dart';
import 'package:marketplace_app/design/theme.dart';
import 'package:marketplace_app/design/tokens.g.dart';
import 'package:marketplace_app/screens/design_system_screen.dart';

/// Renders the gallery screen end to end in both themes.
///
/// It touches every primitive and needs no API, so it is the cheapest check
/// that the whole design layer still composes — a token renamed in
/// packages/tokens without regenerating, or a primitive whose constructor
/// changed, fails here rather than at runtime on a device.

Widget app({required bool isDark}) => MaterialApp(
      theme: buildMaterialTheme(isDark: isDark),
      home: DsThemeScope(isDark: isDark, child: const DesignSystemScreen()),
    );

void main() {
  testWidgets('renders in light mode with no overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(isDark: false));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('${DsBrand.name} components & tokens'), findsOneWidget);
    expect(find.text('Colour'), findsOneWidget);

    // Below the fold, so it only exists once the lazy list builds it — which is
    // also the point of scrolling to it rather than asserting it up front.
    await tester.scrollUntilVisible(find.text('Typography'), 400);
    expect(find.text('Typography'), findsOneWidget);
  });

  testWidgets('renders in dark mode against the dark palette', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(isDark: true));
    await tester.pump();

    expect(tester.takeException(), isNull);

    // The scaffold paints the dark canvas token, not a Material default grey.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(scaffold.backgroundColor ?? theme.scaffoldBackgroundColor, DsColors.dark.canvas);
  });

  testWidgets('scrolls through every section without throwing', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(isDark: false));
    await tester.pump();

    // Drag to the bottom in steps; a layout error in any section surfaces here.
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'threw after scroll step $i');
    }
  });
}
