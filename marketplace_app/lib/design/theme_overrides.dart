import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// The admin's colour choices from the web panel (`GET /theme`), applied to the
/// app's palettes.
///
/// The shipped tokens are the defaults; this only re-points the tokens an admin
/// has deliberately changed, so a later change to a default still reaches every
/// token that was never overridden — the same rule the web follows when it emits
/// these as CSS custom properties.
class DsPalette {
  DsPalette._();

  /// What the widgets resolve against. Starts as the shipped tokens.
  static DsColors light = DsColors.light;
  static DsColors dark = DsColors.dark;

  static void reset() {
    light = DsColors.light;
    dark = DsColors.dark;
  }

  /// Parse the `/theme` payload and make it the active palette. Anything that is
  /// not a six-digit hex colour is ignored, exactly as the web ignores it.
  static void applyFromApi(Map<String, dynamic>? theme) {
    if (theme == null) return reset();
    light = withOverrides(DsColors.light, _stringMap(theme['colors']));
    dark = withOverrides(DsColors.dark, _stringMap(theme['colors_dark']));
  }

  static Map<String, String> _stringMap(dynamic raw) => raw is Map
      ? {for (final e in raw.entries) '${e.key}': '${e.value}'}
      : const {};

  static final RegExp _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

  static Color? _parse(Map<String, String> o, String token) {
    final value = o[token];
    if (value == null || !_hex.hasMatch(value)) return null;
    return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
  }

  /// [base] with every valid override in [o] (keyed by the admin panel's token
  /// names, e.g. `surface-muted`) swapped in.
  static DsColors withOverrides(DsColors base, Map<String, String> o) {
    if (o.isEmpty) return base;
    Color pick(String token, Color fallback) => _parse(o, token) ?? fallback;

    return DsColors(
      canvas: pick('canvas', base.canvas),
      surface: pick('surface', base.surface),
      surfaceMuted: pick('surface-muted', base.surfaceMuted),
      surfaceSunken: pick('surface-sunken', base.surfaceSunken),
      inverse: pick('inverse', base.inverse),
      ink: pick('ink', base.ink),
      inkMuted: pick('ink-muted', base.inkMuted),
      inkSubtle: pick('ink-subtle', base.inkSubtle),
      inkInverse: pick('ink-inverse', base.inkInverse),
      line: pick('line', base.line),
      lineStrong: pick('line-strong', base.lineStrong),
      primary: pick('primary', base.primary),
      primaryHover: pick('primary-hover', base.primaryHover),
      onPrimary: pick('on-primary', base.onPrimary),
      accent: pick('accent', base.accent),
      accentHover: pick('accent-hover', base.accentHover),
      accentSoft: pick('accent-soft', base.accentSoft),
      onAccent: pick('on-accent', base.onAccent),
      highlight: pick('highlight', base.highlight),
      highlightHover: pick('highlight-hover', base.highlightHover),
      onHighlight: pick('on-highlight', base.onHighlight),
      success: pick('success', base.success),
      successSoft: pick('success-soft', base.successSoft),
      warning: pick('warning', base.warning),
      warningSoft: pick('warning-soft', base.warningSoft),
      danger: pick('danger', base.danger),
      dangerHover: pick('danger-hover', base.dangerHover),
      dangerSoft: pick('danger-soft', base.dangerSoft),
      info: pick('info', base.info),
      infoSoft: pick('info-soft', base.infoSoft),
      agent: base.agent,
      agentHover: base.agentHover,
      agentSurface: base.agentSurface,
      sale: pick('sale', base.sale),
      newColor: pick('new', base.newColor),
      rating: pick('rating', base.rating),
      pastelGreen: base.pastelGreen,
      pastelTan: base.pastelTan,
      pastelBlue: base.pastelBlue,
      scrollTrack: base.scrollTrack,
      scrollThumb: base.scrollThumb,
    );
  }
}
