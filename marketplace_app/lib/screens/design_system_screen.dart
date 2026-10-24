import 'package:flutter/material.dart';

import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/mobile.dart';
import '../design/mobile_components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../widgets/theme_picker.dart';

/// The mobile half of the design system's visual contract.
///
/// The first sections mirror the web's `/design-system` — same order, same token
/// names — because colour, type and shape are shared brand: put side by side,
/// a swatch that differs is something hand-written that should be generated.
///
/// "Mobile patterns" at the end has no web twin. It shows what the app owns on
/// its own account: finger-sized targets, gestures, adaptive layout, haptics.
/// See `lib/design/MOBILE.md`.
class DesignSystemScreen extends StatefulWidget {
  const DesignSystemScreen({super.key});

  @override
  State<DesignSystemScreen> createState() => _DesignSystemScreenState();
}

class _DesignSystemScreenState extends State<DesignSystemScreen> {
  String _tab = 'all';
  final _fieldController = TextEditingController(text: '12');

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    final colorGroups = <String, List<(String, Color)>>{
      'Surfaces': [
        ('canvas', c.canvas),
        ('surface', c.surface),
        ('surface-muted', c.surfaceMuted),
        ('surface-sunken', c.surfaceSunken),
        ('inverse', c.inverse),
      ],
      'Foreground': [
        ('ink', c.ink),
        ('ink-muted', c.inkMuted),
        ('ink-subtle', c.inkSubtle),
        ('ink-inverse', c.inkInverse),
      ],
      'Lines': [('line', c.line), ('line-strong', c.lineStrong)],
      'Brand': [
        ('primary', c.primary),
        ('primary-hover', c.primaryHover),
        ('accent', c.accent),
        ('accent-soft', c.accentSoft),
        ('highlight', c.highlight),
      ],
      'Status': [
        ('success', c.success),
        ('success-soft', c.successSoft),
        ('warning', c.warning),
        ('warning-soft', c.warningSoft),
        ('danger', c.danger),
        ('danger-soft', c.dangerSoft),
        ('info', c.info),
        ('info-soft', c.infoSoft),
      ],
      'Commerce': [
        ('sale', c.sale),
        ('new', c.newColor),
        ('rating', c.rating),
        ('agent', c.agent),
      ],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Design system'),
        actions: const [ThemeModeButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(DsSpace.s4),
        children: [
          const BxBadge('Generated from packages/tokens', tone: BxTone.accent),
          const SizedBox(height: DsSpace.s3),
          Text(
            '${DsBrand.name} components & tokens',
            style: TextStyle(
              fontFamily: DsFont.display,
              fontSize: DsText.x2xl,
              fontWeight: DsWeight.black,
              color: c.ink,
            ),
          ),
          const SizedBox(height: DsSpace.s2),
          Text(
            'Every value below comes from packages/tokens/src/tokens.js — the same file '
            'the web storefront reads through CSS custom properties. Toggle the theme; '
            'nothing here hardcodes a colour.',
            style: TextStyle(fontSize: DsText.base, height: DsText.baseHeight, color: c.inkMuted),
          ),

          const _Section('Colour', 'Semantic tokens. Each flips with the theme.'),
          ...colorGroups.entries.map((group) => Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label(group.key),
                    const SizedBox(height: DsSpace.s2),
                    Wrap(
                      spacing: DsSpace.s3,
                      runSpacing: DsSpace.s3,
                      children: group.value
                          .map((e) => _Swatch(name: e.$1, color: e.$2))
                          .toList(),
                    ),
                  ],
                ),
              )),

          const _Section('Typography', 'Three families, ten steps.'),
          Text('Plus Jakarta Sans — DsFont.sans',
              style: TextStyle(fontFamily: DsFont.sans, fontSize: DsText.lg, color: c.ink)),
          const SizedBox(height: DsSpace.s2),
          Text('Outfit — DsFont.display',
              style: TextStyle(fontFamily: DsFont.display, fontSize: DsText.lg, color: c.ink)),
          const SizedBox(height: DsSpace.s2),
          Text('JetBrains Mono — DsFont.mono',
              style: TextStyle(fontFamily: DsFont.mono, fontSize: DsText.base, color: c.ink)),
          const SizedBox(height: DsSpace.s4),
          ...[
            ('2xs', DsText.x2xs, DsText.x2xsHeight),
            ('xs', DsText.xs, DsText.xsHeight),
            ('sm', DsText.sm, DsText.smHeight),
            ('base', DsText.base, DsText.baseHeight),
            ('md', DsText.md, DsText.mdHeight),
            ('lg', DsText.lg, DsText.lgHeight),
            ('xl', DsText.xl, DsText.xlHeight),
            ('2xl', DsText.x2xl, DsText.x2xlHeight),
          ].map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text('text-${t.$1}',
                          style: TextStyle(
                              fontFamily: DsFont.mono, fontSize: DsText.x2xs, color: c.inkSubtle)),
                    ),
                    Expanded(
                      child: Text('The quick brown fox',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: t.$2, height: t.$3, color: c.ink)),
                    ),
                  ],
                ),
              )),

          const _Section('Geometry', 'Radii named by role, not size.'),
          const _Label('Radius'),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s3,
            runSpacing: DsSpace.s3,
            children: [
              ('chip', DsRadius.chip),
              ('control', DsRadius.control),
              ('card', DsRadius.card),
              ('panel', DsRadius.panel),
              ('pill', DsRadius.pill),
            ].map((r) => _Tile(
                  label: 'rounded-${r.$1}',
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: c.surfaceSunken,
                      border: Border.all(color: c.lineStrong),
                      borderRadius: BorderRadius.circular(r.$2),
                    ),
                  ),
                )).toList(),
          ),
          const SizedBox(height: DsSpace.s4),
          const _Label('Elevation'),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s4,
            runSpacing: DsSpace.s4,
            children: [
              ('subtle', context.dsShadow.subtle),
              ('card', context.dsShadow.card),
              ('hover', context.dsShadow.hover),
              ('panel', context.dsShadow.panel),
            ].map((s) => _Tile(
                  label: 'shadow-${s.$1}',
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: DsRadius.cardAll,
                      boxShadow: s.$2,
                    ),
                  ),
                )).toList(),
          ),

          const _Section('Button', 'One component. Eight variants, four sizes.'),
          const _Label('Variants'),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s2,
            children: BxButtonVariant.values
                .map((v) => BxButton(label: v.name, variant: v, size: BxButtonSize.sm, onPressed: () {}))
                .toList(),
          ),
          const SizedBox(height: DsSpace.s4),
          const _Label('Sizes'),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: BxButtonSize.values
                .map((s) => BxButton(label: 'Size ${s.name}', size: s, onPressed: () {}))
                .toList(),
          ),
          const SizedBox(height: DsSpace.s4),
          const _Label('States'),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s2,
            children: [
              const BxButton(label: 'Loading', loading: true),
              const BxButton(label: 'Disabled'),
              BxButton(label: 'With icon', leadingIcon: Icons.notifications_outlined, onPressed: () {}),
              BxButton(label: 'Squared', pill: false, onPressed: () {}),
            ],
          ),

          const _Section('Form controls', 'Label, helper and error handled once.'),
          const BxField(label: 'Full name', hint: 'Priya Sharma'),
          const SizedBox(height: DsSpace.s4),
          const BxField(
            label: 'Email',
            hint: 'you@example.com',
            helper: 'We only use this for order updates.',
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Pincode',
            controller: _fieldController,
            error: 'Enter a valid 6-digit pincode.',
            keyboardType: TextInputType.number,
          ),

          const _Section('Feedback'),
          const _Label('Badges'),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s2,
            children: BxTone.values.map((t) => BxBadge(t.name, tone: t)).toList(),
          ),
          const SizedBox(height: DsSpace.s4),
          const BxAlert('Delivery may take an extra day this week.',
              title: 'Heads up', tone: BxTone.info),
          const SizedBox(height: DsSpace.s2),
          const BxAlert('You will get a confirmation shortly.',
              title: 'Order placed', tone: BxTone.success),
          const SizedBox(height: DsSpace.s2),
          const BxAlert('Only 2 left at this price.', title: 'Low stock', tone: BxTone.warning),
          const SizedBox(height: DsSpace.s2),
          const BxAlert('Your card was declined.', title: 'Payment failed', tone: BxTone.danger),

          const SizedBox(height: DsSpace.s4),
          const _Label('Tabs'),
          const SizedBox(height: DsSpace.s2),
          BxTabs(
            tabs: const [
              BxTab('all', 'All', count: 42),
              BxTab('pending', 'Pending', count: 3),
              BxTab('done', 'Delivered', count: 39),
            ],
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),

          const SizedBox(height: DsSpace.s4),
          const _Label('Cards & loading'),
          const SizedBox(height: DsSpace.s2),
          BxCard(
            elevated: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Elevated card',
                    style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink)),
                Text('Uses shadow-card from the tokens.',
                    style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
              ],
            ),
          ),
          const SizedBox(height: DsSpace.s3),
          const BxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BxSkeleton(width: 180),
                SizedBox(height: DsSpace.s2),
                BxSkeleton(width: 120),
                SizedBox(height: DsSpace.s2),
                BxSkeleton(width: 220),
              ],
            ),
          ),

          const _Section('Overlays', 'The Modal/Drawer analogue.'),
          BxButton(
            label: 'Open sheet',
            onPressed: () => showBxSheet(
              context: context,
              title: 'Confirm cancellation',
              child: Text(
                'This releases the stock back to inventory. Scrim tap and the system '
                'back gesture both dismiss — handled once, here.',
                style: TextStyle(fontSize: DsText.base, height: DsText.baseHeight, color: c.inkMuted),
              ),
              footer: Row(
                children: [
                  Expanded(
                    child: BxButton(
                      label: 'Keep order',
                      variant: BxButtonVariant.secondary,
                      fullWidth: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: DsSpace.s3),
                  Expanded(
                    child: BxButton(
                      label: 'Cancel order',
                      variant: BxButtonVariant.danger,
                      fullWidth: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const _Section('Mobile patterns',
              'Owned by the app, not borrowed from the web.'),
          BxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('Touch targets — sm 44, md 48, lg 56'),
                Wrap(
                  spacing: DsSpace.s2,
                  runSpacing: DsSpace.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    BxButton(label: 'Small', size: BxButtonSize.sm, onPressed: () {}),
                    BxButton(label: 'Medium', onPressed: () {}),
                    BxButton(label: 'Large', size: BxButtonSize.lg, onPressed: () {}),
                  ],
                ),
                const SizedBox(height: DsSpace.s4),
                const _Label('Quantity stepper — 48dp buttons, minus becomes remove'),
                _StepperDemo(),
                const SizedBox(height: DsSpace.s4),
                const _Label('Pressable — settles on press, ticks the haptic motor'),
                BxPressable(
                  haptic: true,
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(DsSpace.s4),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.line),
                      borderRadius: DsRadius.cardAll,
                    ),
                    child: Text('Tap me', style: TextStyle(color: c.ink)),
                  ),
                ),
                const SizedBox(height: DsSpace.s4),
                const _Label('Window class — the shell adapts to the room'),
                Text(
                  '${context.dsWindow.name} · ${MediaQuery.sizeOf(context).width.round()}dp'
                  '${context.dsWindow.usesRail ? ' · side rail' : ' · bottom bar'}',
                  style: TextStyle(fontSize: DsText.base, color: c.ink),
                ),
                const SizedBox(height: DsSpace.s4),
                const _Label('Appearance — Light, Dark or follow the device'),
                const ThemeModePicker(),
              ],
            ),
          ),

          const _Section('Empty state'),
          BxCard(
            padding: EdgeInsets.zero,
            child: BxEmptyState(
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              description: 'Order updates and price-drop alerts will show up here.',
              action: BxButton(label: 'Browse products', size: BxButtonSize.sm, onPressed: () {}),
            ),
          ),

          const SizedBox(height: DsSpace.s12),
        ],
      ),
    );
  }
}

class _StepperDemo extends StatefulWidget {
  @override
  State<_StepperDemo> createState() => _StepperDemoState();
}

class _StepperDemoState extends State<_StepperDemo> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) => BxQuantityStepper(
        quantity: _quantity,
        maxQuantity: 5,
        onChanged: (q) => setState(() => _quantity = q),
        onRemove: () => setState(() => _quantity = 1),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _Section(this.title, [this.subtitle]);

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(top: DsSpace.s10, bottom: DsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: DsFont.display,
              fontSize: DsText.xl,
              fontWeight: DsWeight.black,
              color: c.ink,
            ),
          ),
          if (subtitle != null)
            Text(subtitle!, style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: DsText.x2xs,
        fontWeight: DsWeight.black,
        letterSpacing: 0.8,
        color: context.ds.inkSubtle,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final Widget child;

  const _Tile({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: DsSpace.s1),
        Text(label,
            style: TextStyle(
                fontFamily: DsFont.mono, fontSize: DsText.x2xs, color: context.ds.inkMuted)),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final String name;
  final Color color;

  const _Swatch({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return _Tile(
      label: name,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: DsRadius.controlAll,
          border: Border.all(color: context.ds.line),
        ),
      ),
    );
  }
}
