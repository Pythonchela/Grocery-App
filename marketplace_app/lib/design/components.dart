import 'package:flutter/material.dart';

import 'mobile.dart';
import 'mobile_components.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// Brand-neutral primitives — the Flutter counterpart of `packages/ui`.
///
/// Same contract as the web side: every value here is a token lookup. No hex,
/// no `Colors.grey`, no brand strings. That is what lets a second Flutter app
/// (a seller app, a white-label build) take this file unchanged.
///
/// Names deliberately mirror the web components so the two stay recognisably
/// one system: BxButton/Button, BxField/Input, BxSheet/Modal, and so on.

// ─── Button ──────────────────────────────────────────────────────────────────

enum BxButtonVariant { primary, secondary, accent, highlight, danger, dangerSoft, ghost, link }

enum BxButtonSize { xs, sm, md, lg }

class BxButton extends StatelessWidget {
  final String? label;
  final Widget? child;
  final VoidCallback? onPressed;
  final BxButtonVariant variant;
  final BxButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool loading;
  final bool fullWidth;
  final bool pill;

  const BxButton({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.variant = BxButtonVariant.primary,
    this.size = BxButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
    this.pill = false,
  }) : assert(label != null || child != null, 'BxButton needs a label or a child');

  ({Color bg, Color fg, Color? border, List<BoxShadow>? shadow}) _paint(BuildContext context) {
    final c = context.ds;
    switch (variant) {
      case BxButtonVariant.primary:
        return (bg: c.primary, fg: c.onPrimary, border: null, shadow: context.dsShadow.button);
      case BxButtonVariant.secondary:
        return (bg: c.surface, fg: c.ink, border: c.line, shadow: null);
      case BxButtonVariant.accent:
        return (bg: c.accent, fg: c.onAccent, border: null, shadow: context.dsShadow.button);
      case BxButtonVariant.highlight:
        return (bg: c.highlight, fg: c.onHighlight, border: null, shadow: null);
      case BxButtonVariant.danger:
        return (bg: c.danger, fg: c.onPrimary, border: null, shadow: null);
      case BxButtonVariant.dangerSoft:
        return (bg: c.dangerSoft, fg: c.danger, border: c.danger, shadow: null);
      case BxButtonVariant.ghost:
        return (bg: Colors.transparent, fg: c.inkMuted, border: null, shadow: null);
      case BxButtonVariant.link:
        return (bg: Colors.transparent, fg: c.accent, border: null, shadow: null);
    }
  }

  /// Heights are floors, not paddings: whatever the label, the control is at
  /// least this tall. Phone-normal sizes - the kind a shopper sees in any
  /// shopping app: 48 for the one big action on a screen, 44 for ordinary
  /// buttons, 40 inside cards and rows, 32 for dense inline actions. Small
  /// buttons keep a finger-sized hit area by sitting in rows with room around
  /// them; icon buttons and steppers stay 48.
  ({EdgeInsets pad, double text, double gap, double icon, double minHeight})
      _metrics() {
    switch (size) {
      case BxButtonSize.xs:
        return (
          pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          text: DsText.xs,
          gap: 4,
          icon: 14,
          minHeight: 32
        );
      case BxButtonSize.sm:
        return (
          pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          text: DsText.sm,
          gap: 6,
          icon: 16,
          minHeight: 40
        );
      case BxButtonSize.md:
        return (
          pad: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          text: DsText.base,
          gap: 8,
          icon: 18,
          minHeight: 44
        );
      case BxButtonSize.lg:
        return (
          pad: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          text: DsText.md,
          gap: 8,
          icon: 20,
          minHeight: DsTouch.minTarget
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _paint(context);
    final m = _metrics();
    final disabled = onPressed == null || loading;

    final content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: m.icon,
            height: m.icon,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.fg),
          )
        else if (leadingIcon != null)
          Icon(leadingIcon, size: m.icon, color: p.fg),
        if (loading || leadingIcon != null) SizedBox(width: m.gap),
        child ??
            // Flexible + ellipsis: a long label on a narrow screen truncates
            // instead of overflowing the row.
            Flexible(
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: DsFont.sans,
                  fontSize: m.text,
                  fontWeight: DsWeight.bold,
                  color: p.fg,
                  decoration: variant == BxButtonVariant.link ? TextDecoration.underline : null,
                ),
              ),
            ),
        if (trailingIcon != null && !loading) ...[
          SizedBox(width: m.gap),
          Icon(trailingIcon, size: m.icon, color: p.fg),
        ],
      ],
    );

    // MergeSemantics, not a bare Semantics annotation: without it the icon, the
    // spinner and the label each surface as their own node and a screen reader
    // reads the button out in pieces. This collapses the whole control to one
    // node carrying the name and the button role.
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: !disabled,
        // Only supply an explicit name when the caller passed a custom `child`,
        // which may be icon-only. When `label` is set it is already rendered as
        // Text inside, and naming the node too makes a screen reader say it
        // twice ("Checkout Checkout").
        label: child != null ? label : null,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Material(
            color: p.bg,
            borderRadius: pill ? DsRadius.pillAll : DsRadius.controlAll,
            child: InkWell(
              // A press is acknowledged with a light tick, except for text-style
              // buttons, which are links in all but name.
              onTap: disabled
                  ? null
                  : () {
                      if (variant != BxButtonVariant.link &&
                          variant != BxButtonVariant.ghost) {
                        DsHaptics.tap();
                      }
                      onPressed!();
                    },
              borderRadius: pill ? DsRadius.pillAll : DsRadius.controlAll,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: pill ? DsRadius.pillAll : DsRadius.controlAll,
                  border: p.border != null ? Border.all(color: p.border!) : null,
                  boxShadow: disabled ? null : p.shadow,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: m.minHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: m.pad.horizontal / 2),
                    child: Align(
                      alignment: Alignment.center,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: m.pad.vertical / 2),
                        // A large system font makes body text bigger, which is what
                        // it is for. A button that grows with it becomes a slab, so
                        // its label scales only a little: buttons stay phone-sized.
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.1,
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Field ───────────────────────────────────────────────────────────────────

/// Text input with the label / helper / error wiring done once.
///
/// The web `Input` generates its own id so a control cannot be rendered
/// unlabelled. Flutter has no id to forget, but the equivalent hazard is a bare
/// [TextField] with a hint and no semantic label — so the label is required
/// here, and it feeds both the visible text and the accessibility tree.
class BxField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? helper;
  final String? error;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final bool enabled;

  const BxField({
    super.key,
    required this.label,
    this.hint,
    this.helper,
    this.error,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final hasError = error != null && error!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: DsFont.sans,
            fontSize: DsText.xs,
            fontWeight: DsWeight.bold,
            color: c.inkMuted,
          ),
        ),
        const SizedBox(height: DsSpace.s1 + 2),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: obscureText ? 1 : maxLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          enabled: enabled,
          style: TextStyle(
            fontFamily: DsFont.sans,
            fontSize: DsText.base,
            color: c.ink,
          ),
          decoration: InputDecoration(
            hintText: hint,
            // Announced instead of the placeholder, which disappears the moment
            // the user types and is not a reliable label.
            label: const ExcludeSemantics(child: SizedBox.shrink()),
            hintStyle: TextStyle(color: c.inkSubtle, fontSize: DsText.base),
            filled: true,
            fillColor: enabled ? c.surface : c.surfaceSunken,
            suffixIcon: suffix,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: DsRadius.controlAll,
              borderSide: BorderSide(color: hasError ? c.danger : c.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: DsRadius.controlAll,
              borderSide: BorderSide(color: hasError ? c.danger : c.accent, width: 2),
            ),
            disabledBorder: const OutlineInputBorder(
              borderRadius: DsRadius.controlAll,
              borderSide: BorderSide(color: Colors.transparent),
            ),
          ),
        ),
        if (helper != null && !hasError) ...[
          const SizedBox(height: DsSpace.s1),
          Text(helper!, style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
        ],
        if (hasError) ...[
          const SizedBox(height: DsSpace.s1),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(fontSize: DsText.xs, fontWeight: DsWeight.semibold, color: c.danger),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Surfaces ────────────────────────────────────────────────────────────────

class BxCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final bool elevated;

  const BxCard({super.key, required this.child, this.padding, this.onTap, this.elevated = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final body = Container(
      padding: padding ?? const EdgeInsets.all(DsSpace.s5),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: DsRadius.cardAll,
        border: Border.all(color: c.line),
        boxShadow: elevated ? context.dsShadow.card : null,
      ),
      child: child,
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: DsRadius.cardAll, child: body),
    );
  }
}

enum BxTone { neutral, primary, accent, success, warning, danger, info, highlight, sale, newItem }

({Color bg, Color fg}) _tone(BuildContext context, BxTone tone) {
  final c = context.ds;
  switch (tone) {
    case BxTone.neutral:
      return (bg: c.surfaceSunken, fg: c.inkMuted);
    case BxTone.primary:
      return (bg: c.primary, fg: c.onPrimary);
    case BxTone.accent:
      return (bg: c.accentSoft, fg: c.accent);
    case BxTone.success:
      return (bg: c.successSoft, fg: c.success);
    case BxTone.warning:
      return (bg: c.warningSoft, fg: c.warning);
    case BxTone.danger:
      return (bg: c.dangerSoft, fg: c.danger);
    case BxTone.info:
      return (bg: c.infoSoft, fg: c.info);
    case BxTone.highlight:
      return (bg: c.highlight, fg: c.onHighlight);
    case BxTone.sale:
      return (bg: c.sale, fg: c.inkInverse);
    case BxTone.newItem:
      return (bg: c.newColor, fg: c.inkInverse);
  }
}

class BxBadge extends StatelessWidget {
  final String label;
  final BxTone tone;
  final IconData? icon;

  const BxBadge(this.label, {super.key, this.tone = BxTone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = _tone(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: t.bg, borderRadius: DsRadius.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: t.fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: DsFont.sans,
                fontSize: DsText.x2xs,
                fontWeight: DsWeight.black,
                color: t.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BxAlert extends StatelessWidget {
  final String message;
  final String? title;
  final BxTone tone;

  const BxAlert(this.message, {super.key, this.title, this.tone = BxTone.info});

  @override
  Widget build(BuildContext context) {
    final t = _tone(context, tone);
    return Semantics(
      liveRegion: tone == BxTone.danger,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s3),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: DsRadius.controlAll,
          border: Border.all(color: t.fg.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Text(title!,
                  style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: t.fg)),
            Text(message, style: TextStyle(fontSize: DsText.base, color: t.fg)),
          ],
        ),
      ),
    );
  }
}

class BxSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius radius;

  const BxSkeleton({super.key, this.width, this.height = 14, this.radius = DsRadius.controlAll});

  @override
  State<BxSkeleton> createState() => _BxSkeletonState();
}

class _BxSkeletonState extends State<BxSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(color: context.ds.surfaceSunken, borderRadius: widget.radius),
        ),
      ),
    );
  }
}

class BxEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  const BxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s6, vertical: DsSpace.s12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: DsRadius.pillAll),
              child: Icon(icon, size: 24, color: c.inkSubtle),
            ),
            const SizedBox(height: DsSpace.s4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: DsText.md, fontWeight: DsWeight.black, color: c.ink),
            ),
            if (description != null) ...[
              const SizedBox(height: DsSpace.s1),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: DsSpace.s5), action!],
          ],
        ),
      ),
    );
  }
}

// ─── Tabs ────────────────────────────────────────────────────────────────────

class BxTab {
  final String value;
  final String label;
  final int? count;

  const BxTab(this.value, this.label, {this.count});
}

class BxTabs extends StatelessWidget {
  final List<BxTab> tabs;
  final String value;
  final ValueChanged<String> onChanged;

  const BxTabs({super.key, required this.tabs, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
      child: Row(
        children: tabs.map((t) {
          final active = t.value == value;
          return Padding(
            padding: const EdgeInsets.only(right: DsSpace.s2),
            child: Semantics(
              selected: active,
              button: true,
              child: Material(
                color: active ? c.primary : c.surface,
                borderRadius: DsRadius.pillAll,
                child: InkWell(
                  onTap: () => onChanged(t.value),
                  borderRadius: DsRadius.pillAll,
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: DsRadius.pillAll,
                      border: Border.all(color: active ? Colors.transparent : c.line),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.label,
                          style: TextStyle(
                            fontSize: DsText.xs,
                            fontWeight: DsWeight.bold,
                            color: active ? c.onPrimary : c.inkMuted,
                          ),
                        ),
                        if (t.count != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: active ? c.onPrimary.withValues(alpha: 0.2) : c.surfaceSunken,
                              borderRadius: DsRadius.pillAll,
                            ),
                            child: Text(
                              '${t.count}',
                              style: TextStyle(
                                fontSize: DsText.x2xs,
                                fontWeight: DsWeight.bold,
                                color: active ? c.onPrimary : c.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Sheet (the Modal/Drawer analogue) ───────────────────────────────────────

/// Bottom sheet with the chrome the web `Modal` provides: a titled header, a
/// close affordance, scrollable body and a pinned footer. Flutter gives focus
/// handling and scrim dismissal for free, which is the part the sixteen
/// hand-rolled web overlays kept getting wrong.
Future<T?> showBxSheet<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  Widget? footer,
}) {
  final c = context.ds;
  final isDark = context.dsIsDark;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surface,
    barrierColor: c.inverse.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DsRadius.panel)),
    ),
    builder: (sheetContext) => DsThemeScope(
      isDark: isDark,
      child: Builder(
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BxSheetHandle(),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(DsSpace.s5, DsSpace.s2, DsSpace.s2, DsSpace.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontFamily: DsFont.sans,
                            fontSize: DsText.lg,
                            fontWeight: DsWeight.black,
                            color: ctx.ds.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: ctx.ds.inkMuted),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: ctx.ds.line),
                Flexible(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(DsSpace.s5), child: child)),
                if (footer != null) ...[
                  Divider(height: 1, color: ctx.ds.line),
                  Padding(padding: const EdgeInsets.all(DsSpace.s4), child: footer),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
