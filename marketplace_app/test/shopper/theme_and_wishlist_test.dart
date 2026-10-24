import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/design/theme.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:marketplace_app/widgets/theme_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child, {bool isDark = false}) => MaterialApp(
      theme: buildMaterialTheme(isDark: isDark),
      home: DsThemeScope(isDark: isDark, child: Scaffold(body: child)),
    );

void main() {
  Future<void> freshLaunch(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    // SharedPreferences completes on real time, which the widget tester's fake
    // clock never advances — so it has to run outside it.
    await tester.runAsync(AppState.instance.load);
    AppState.instance.setThemeMode(ThemeMode.system);
  }

  testWidgets('the picker offers Light, Dark and System', (tester) async {
    await freshLaunch(tester);
    await tester.pumpWidget(host(const ThemeModePicker()));

    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
  });

  testWidgets('choosing a mode applies it and System can be chosen again',
      (tester) async {
    await freshLaunch(tester);
    await tester.pumpWidget(host(const ThemeModePicker()));

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(AppState.instance.themeMode, ThemeMode.dark);

    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(AppState.instance.themeMode, ThemeMode.light);

    await tester.tap(find.text('System'));
    await tester.pump();
    expect(AppState.instance.themeMode, ThemeMode.system);
  });

  testWidgets('the app-bar button opens the picker and shows the chosen mode',
      (tester) async {
    await freshLaunch(tester);
    await tester.pumpWidget(host(const ThemeModeButton()));

    expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(AppState.instance.themeMode, ThemeMode.dark);
  });

  testWidgets('the saved choice is restored on the next launch', (tester) async {
    await freshLaunch(tester);
    AppState.instance.setThemeMode(ThemeMode.dark);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    await tester.runAsync(AppState.instance.load);
    expect(AppState.instance.themeMode, ThemeMode.dark);
  });

  test('nothing is wishlisted for a signed-out shopper', () {
    expect(AppState.instance.isWishlisted('any-product'), isFalse);
    expect(AppState.instance.unreadNotifications, 0);
  });
}
