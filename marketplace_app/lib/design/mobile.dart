import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The mobile half of the design system.
///
/// The shared tokens (`tokens.g.dart`) give the app the brand's colours, type
/// and shape so it is recognisably the same product as the web. Everything in
/// this file is owned by the app, because it describes a thing a website does
/// not have: a thumb, a finger-sized target, a screen that rotates and folds, a
/// back gesture, a vibration motor and an operating system that expects its
/// conventions to be followed.
///
/// See `MOBILE.md` next to this file for how these are meant to be used.

// ─── Touch ───────────────────────────────────────────────────────────────────

/// Finger-sized geometry. A mouse pointer is one pixel wide; a thumb is about
/// 9mm, which is why these floors exist and why the web's denser controls are
/// not copied across.
abstract final class DsTouch {
  /// Smallest tappable area for anything a shopper can press (Material and
  /// Apple guidance converge on 44-48dp). Visuals may be smaller; the hit area
  /// may not.
  static const double minTarget = 48;

  /// The primary action of a screen: bigger, because it is pressed most and
  /// often one-handed.
  static const double primaryTarget = 56;

  /// Breathing room between two adjacent targets, so a miss lands on empty
  /// space rather than the neighbour.
  static const double gap = 8;

  static const double iconSm = 20;
  static const double icon = 24;
  static const double iconLg = 32;
}

// ─── Motion ──────────────────────────────────────────────────────────────────

/// How things move. Short and decelerating: a phone screen is small and the
/// shopper is mid-task, so motion explains a change and then gets out of the way.
abstract final class DsMobileMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration emphasized = Duration(milliseconds: 400);

  /// Things entering or settling.
  static const Curve enter = Curves.easeOutCubic;

  /// Things leaving.
  static const Curve exit = Curves.easeInCubic;

  /// A change that deserves attention (a button confirming, a sheet opening).
  static const Curve emphasis = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Honours the system "remove animations" accessibility setting: callers pass
  /// the duration they want and get [Duration.zero] when the shopper has asked
  /// for none.
  static Duration of(BuildContext context, Duration wanted) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : wanted;
}

// ─── Feedback ────────────────────────────────────────────────────────────────

/// Haptics. A tap on glass has no click of its own; a short tick is how the app
/// confirms it heard. Used sparingly and always for the same meaning, so a
/// shopper learns the vocabulary.
abstract final class DsHaptics {
  /// A press registered (buttons, toggles).
  static void tap() => HapticFeedback.lightImpact();

  /// A choice changed (tab, option, segment).
  static void select() => HapticFeedback.selectionClick();

  /// Something was added, saved or placed.
  static void success() => HapticFeedback.mediumImpact();

  /// A destructive or irreversible step is about to happen.
  static void warn() => HapticFeedback.heavyImpact();
}

// ─── Window ──────────────────────────────────────────────────────────────────

/// Width classes, after Material's window size classes. The layout adapts to
/// the room it is given rather than assuming a portrait phone: a tablet, a
/// foldable or a phone in landscape gets a different shell, not a stretched one.
enum DsWindowClass {
  /// Phones in portrait.
  compact,

  /// Large phones in landscape, small tablets, unfolded foldables.
  medium,

  /// Tablets and desktop-sized windows.
  expanded;

  static const double mediumFrom = 600;
  static const double expandedFrom = 840;

  static DsWindowClass of(double width) {
    if (width >= expandedFrom) return DsWindowClass.expanded;
    if (width >= mediumFrom) return DsWindowClass.medium;
    return DsWindowClass.compact;
  }

  bool get usesRail => this != DsWindowClass.compact;

  /// Text and forms get unreadable and awkward when stretched across a tablet;
  /// content is held to a comfortable measure and centred.
  double get maxContentWidth => switch (this) {
        DsWindowClass.compact => double.infinity,
        DsWindowClass.medium => 720,
        DsWindowClass.expanded => 960,
      };
}

extension DsMobileContext on BuildContext {
  DsWindowClass get dsWindow => DsWindowClass.of(MediaQuery.sizeOf(this).width);
}
