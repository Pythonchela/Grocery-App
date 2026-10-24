import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

const _options = <(ThemeMode, String, IconData)>[
  (ThemeMode.light, 'Light', Icons.light_mode_outlined),
  (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
  (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
];

/// Icon that reflects the *chosen* mode, so "System" reads as its own state.
IconData themeModeIcon(ThemeMode mode) =>
    _options.firstWhere((o) => o.$1 == mode).$3;

/// Segmented Light / Dark / System picker, persisted by [AppState].
class ThemeModePicker extends StatelessWidget {
  const ThemeModePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final current = AppState.instance.themeMode;
        return Row(
          children: [
            for (var i = 0; i < _options.length; i++) ...[
              if (i > 0) const SizedBox(width: DsSpace.s2),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: current == _options[i].$1,
                  label: '${_options[i].$2} theme',
                  child: Material(
                    color: current == _options[i].$1 ? c.accentSoft : c.surface,
                    borderRadius: DsRadius.cardAll,
                    child: InkWell(
                      borderRadius: DsRadius.cardAll,
                      onTap: () =>
                          AppState.instance.setThemeMode(_options[i].$1),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                            vertical: DsSpace.s3),
                        decoration: BoxDecoration(
                          borderRadius: DsRadius.cardAll,
                          border: Border.all(
                              color: current == _options[i].$1
                                  ? c.accent
                                  : c.line),
                        ),
                        child: Column(
                          children: [
                            Icon(_options[i].$3,
                                size: 20,
                                color: current == _options[i].$1
                                    ? c.ink
                                    : c.inkMuted),
                            const SizedBox(height: DsSpace.s1),
                            Text(
                              _options[i].$2,
                              style: TextStyle(
                                fontSize: DsText.xs,
                                fontWeight: DsWeight.bold,
                                color: current == _options[i].$1
                                    ? c.ink
                                    : c.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// App-bar action: shows the chosen mode and opens the picker.
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) => IconButton(
        icon: Icon(themeModeIcon(AppState.instance.themeMode)),
        tooltip: 'Appearance',
        onPressed: () => showBxSheet<void>(
          context: context,
          title: 'Appearance',
          child: const Padding(
            padding: EdgeInsets.fromLTRB(
                DsSpace.s4, DsSpace.s2, DsSpace.s4, DsSpace.s5),
            child: ThemeModePicker(),
          ),
        ),
      ),
    );
  }
}
