import 'package:flutter/material.dart';

import 'design/brand.g.dart';
import 'design/theme.dart';
import 'screens/design_system_screen.dart';
import 'state/app_state.dart';

/// Separate entry point for the design-system gallery.
///
///     flutter run -t lib/main_design_system.dart
///
/// The gallery is a developer tool, so it is not reachable from any customer
/// screen — a `kDebugMode` guard was not enough, because `flutter run` *is* a
/// debug build, so the link stayed visible during ordinary development.
///
/// Giving it its own target instead means it can never appear in the shipped
/// app by accident, while staying one command away when you need to eyeball a
/// token change across every component.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.load();
  runApp(const DesignSystemApp());
}

class DesignSystemApp extends StatelessWidget {
  const DesignSystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final mode = AppState.instance.themeMode;

        return MaterialApp(
          title: '${DsBrand.name} design system',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: buildMaterialTheme(isDark: false),
          darkTheme: buildMaterialTheme(isDark: true),
          builder: (context, child) {
            final isDark = switch (mode) {
              ThemeMode.dark => true,
              ThemeMode.light => false,
              ThemeMode.system =>
                MediaQuery.platformBrightnessOf(context) == Brightness.dark,
            };
            return DsThemeScope(isDark: isDark, child: child ?? const SizedBox.shrink());
          },
          home: const DesignSystemScreen(),
        );
      },
    );
  }
}
