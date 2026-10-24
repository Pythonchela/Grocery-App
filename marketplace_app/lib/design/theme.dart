import 'package:flutter/material.dart';

import 'theme_overrides.dart';
import 'tokens.g.dart';

/// The Flutter half of the design system.
///
/// The web app gets theming for free: every Tailwind utility resolves through a
/// CSS custom property, so flipping `.dark` on `<html>` re-points the whole app.
/// Flutter has no equivalent, so [DsTheme] plays that role — an InheritedWidget
/// carrying the palette and shadows for the active theme, read as `DsTheme.of(context)`.
///
/// The rule is the same as on the web: widgets never name a hex value or a
/// Material colour. They ask for a token.
class DsTheme extends InheritedWidget {
  final DsColors colors;
  final DsShadows shadows;
  final bool isDark;

  const DsTheme({
    super.key,
    required this.colors,
    required this.shadows,
    required this.isDark,
    required super.child,
  });

  static DsTheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<DsTheme>();
    assert(theme != null, 'No DsTheme in context. Wrap the app in DsThemeScope.');
    return theme!;
  }

  @override
  bool updateShouldNotify(DsTheme old) =>
      old.isDark != isDark || !identical(old.colors, colors);
}

/// Wraps [child] in the token set matching [isDark].
class DsThemeScope extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const DsThemeScope({super.key, required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return DsTheme(
      isDark: isDark,
      colors: isDark ? DsPalette.dark : DsPalette.light,
      shadows: isDark ? DsShadows.dark : DsShadows.light,
      child: child,
    );
  }
}

/// Convenience accessors, so a build method reads `context.ds.surface` rather
/// than `DsTheme.of(context).colors.surface` at every use site.
extension DsContext on BuildContext {
  DsColors get ds => DsTheme.of(this).colors;
  DsShadows get dsShadow => DsTheme.of(this).shadows;
  bool get dsIsDark => DsTheme.of(this).isDark;
}

/// Material [ThemeData] built from the same tokens, so the framework widgets we
/// don't wrap (dialogs, snackbars, text selection handles, the scroll glow)
/// still land inside the design system instead of falling back to Material
/// defaults that look nothing like the rest of the app.
ThemeData buildMaterialTheme({required bool isDark}) {
  final c = isDark ? DsPalette.dark : DsPalette.light;

  TextStyle style(double size, double height, FontWeight weight, Color color) => TextStyle(
        fontFamily: DsFont.sans,
        fontSize: size,
        height: height,
        fontWeight: weight,
        color: color,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    fontFamily: DsFont.sans,
    splashFactory: InkSparkle.splashFactory,
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: c.onPrimary,
      surface: c.surface,
      onSurface: c.ink,
      surfaceContainerHighest: c.surfaceSunken,
      outline: c.line,
      outlineVariant: c.lineStrong,
    ),
    // Phone conventions: Android's predictive back (the screen peels away as the
    // gesture progresses) and iOS's edge-swipe back, rather than one transition
    // for every platform.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    // Framework widgets keep their 48dp hit area even when drawn smaller.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentSoft,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => style(
            DsText.xs,
            DsText.xsHeight,
            states.contains(WidgetState.selected) ? DsWeight.bold : DsWeight.medium,
            states.contains(WidgetState.selected) ? c.ink : c.inkMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? c.ink : c.inkMuted,
          )),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accentSoft,
      selectedIconTheme: IconThemeData(color: c.ink),
      unselectedIconTheme: IconThemeData(color: c.inkMuted),
      selectedLabelTextStyle:
          style(DsText.xs, DsText.xsHeight, DsWeight.bold, c.ink),
      unselectedLabelTextStyle:
          style(DsText.xs, DsText.xsHeight, DsWeight.medium, c.inkMuted),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: style(DsText.lg, DsText.lgHeight, DsWeight.black, c.ink),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.surface,
      selectedItemColor: c.ink,
      unselectedItemColor: c.inkSubtle,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: DsRadius.panelAll),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DsRadius.panel)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.inverse,
      contentTextStyle: style(DsText.base, DsText.baseHeight, DsWeight.semibold, c.inkInverse),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: DsRadius.controlAll),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.25),
      selectionHandleColor: c.accent,
    ),
    textTheme: TextTheme(
      displayLarge: style(DsText.x4xl, DsText.x4xlHeight, DsWeight.black, c.ink),
      headlineLarge: style(DsText.x3xl, DsText.x3xlHeight, DsWeight.black, c.ink),
      headlineMedium: style(DsText.x2xl, DsText.x2xlHeight, DsWeight.black, c.ink),
      titleLarge: style(DsText.xl, DsText.xlHeight, DsWeight.black, c.ink),
      titleMedium: style(DsText.lg, DsText.lgHeight, DsWeight.bold, c.ink),
      bodyLarge: style(DsText.md, DsText.mdHeight, DsWeight.regular, c.ink),
      bodyMedium: style(DsText.base, DsText.baseHeight, DsWeight.regular, c.ink),
      bodySmall: style(DsText.sm, DsText.smHeight, DsWeight.regular, c.inkMuted),
      labelSmall: style(DsText.x2xs, DsText.x2xsHeight, DsWeight.bold, c.inkSubtle),
    ),
  );
}
