import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/product_options.dart';
import '../design/mobile.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// The product page's custom selection options: portion, add-ons, "leave out",
/// colour swatches, a weight - one block per group the store configured.
class OptionPicker extends StatelessWidget {
  final List<OptionGroup> groups;
  final OptionSelection selection;
  final ValueChanged<OptionSelection> onChanged;

  const OptionPicker({
    super.key,
    required this.groups,
    required this.selection,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(top: DsSpace.s5),
            child: _Group(group: g, selection: selection, onChanged: onChanged),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  final OptionGroup group;
  final OptionSelection selection;
  final ValueChanged<OptionSelection> onChanged;

  const _Group(
      {required this.group, required this.selection, required this.onChanged});

  String get _hint {
    if (group.isStepper) return group.required ? 'Required' : 'Optional';
    if (group.isMulti) {
      if (group.min > 0 && group.max > group.min) {
        return 'Choose ${group.min}-${group.max}';
      }
      if (group.min > 0) return 'Choose ${group.min}';
      return group.max < group.choices.length
          ? 'Up to ${group.max}'
          : 'Optional';
    }
    return group.required ? 'Required' : 'Optional';
  }

  void _pick(OptionChoice choice) {
    DsHaptics.select();
    final current = selection.of(group.key);

    if (group.isMulti) {
      final next = [...current];
      if (next.contains(choice.id)) {
        next.remove(choice.id);
      } else {
        if (next.length >= group.max) {
          // At the cap, a new pick pushes the oldest out when only one is allowed.
          if (group.max == 1) {
            next.clear();
          } else {
            return;
          }
        }
        next.add(choice.id);
      }
      onChanged(selection.withChoices(group.key, next));
      return;
    }

    // Single / swatch: tapping the chosen one clears it unless it is required.
    if (current.contains(choice.id)) {
      if (!group.required) onChanged(selection.withChoices(group.key, []));
      return;
    }
    onChanged(selection.withChoices(group.key, [choice.id]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final chosen = selection.of(group.key);
    final chosenLabel = group.choices
        .where((o) => chosen.contains(o.id))
        .map((o) => o.label)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: group.label,
                    style: TextStyle(
                        fontSize: DsText.base,
                        fontWeight: DsWeight.bold,
                        color: c.ink),
                  ),
                  if (group.type == OptionType.swatch && chosenLabel.isNotEmpty)
                    TextSpan(
                      text: '  $chosenLabel',
                      style: TextStyle(
                          fontSize: DsText.sm,
                          fontWeight: DsWeight.regular,
                          color: c.inkMuted),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: DsSpace.s2),
            Text(_hint,
                style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
          ],
        ),
        if (group.help != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(group.help!,
                style: TextStyle(fontSize: DsText.xs, color: c.inkMuted)),
          ),
        const SizedBox(height: DsSpace.s2),
        if (group.isStepper)
          _StepperRow(group: group, selection: selection, onChanged: onChanged)
        else if (group.type == OptionType.swatch)
          Wrap(
            spacing: DsSpace.s3,
            runSpacing: DsSpace.s3,
            children: [
              for (final o in group.choices)
                _Swatch(
                  choice: o,
                  selected: chosen.contains(o.id),
                  onTap: o.selectable ? () => _pick(o) : null,
                ),
            ],
          )
        else if (group.isMulti)
          Column(
            children: [
              for (final o in group.choices)
                _CheckRow(
                  group: group,
                  choice: o,
                  selected: chosen.contains(o.id),
                  onTap: o.selectable ? () => _pick(o) : null,
                ),
            ],
          )
        else
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s2,
            children: [
              for (final o in group.choices)
                _ChoiceChip(
                  group: group,
                  choice: o,
                  selected: chosen.contains(o.id),
                  onTap: o.selectable ? () => _pick(o) : null,
                ),
            ],
          ),
      ],
    );
  }
}

String _priceHint(OptionGroup group, OptionChoice choice) {
  if (choice.price <= 0) return '';
  final money = formatMoney(choice.price);
  return group.priceMode == OptionPriceMode.set ? money : '+$money';
}

class _ChoiceChip extends StatelessWidget {
  final OptionGroup group;
  final OptionChoice choice;
  final bool selected;
  final VoidCallback? onTap;

  const _ChoiceChip({
    required this.group,
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final hint = _priceHint(group, choice);

    return Semantics(
      button: true,
      selected: selected,
      label: choice.label,
      child: Material(
        color: selected ? c.primary : c.surface,
        borderRadius: DsRadius.controlAll,
        child: InkWell(
          borderRadius: DsRadius.controlAll,
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: DsRadius.controlAll,
              border: Border.all(color: selected ? c.primary : c.line),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Opacity(
                  opacity: onTap == null ? 0.4 : 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        choice.label,
                        style: TextStyle(
                          fontSize: DsText.sm,
                          fontWeight: DsWeight.semibold,
                          color: selected ? c.onPrimary : c.ink,
                          decoration:
                              onTap == null ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (hint.isNotEmpty)
                        Text(hint,
                            style: TextStyle(
                                fontSize: DsText.x2xs,
                                color: selected ? c.onPrimary : c.inkMuted)),
                    ],
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

class _Swatch extends StatelessWidget {
  final OptionChoice choice;
  final bool selected;
  final VoidCallback? onTap;

  /// A rounded square (for a colour's photo) rather than a round swatch.
  final bool square;

  const _Swatch(
      {required this.choice,
      required this.selected,
      required this.onTap,
      this.square = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final color = choice.color;
    final image = choice.imageUrl;

    return Semantics(
      button: true,
      selected: selected,
      label: choice.label,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Container(
            width: square ? 56 : 44,
            height: square ? 64 : 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: square ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: square ? BorderRadius.circular(10) : null,
              border: Border.all(
                  color: selected ? c.ink : c.line, width: selected ? 2 : 1),
            ),
            child: _clip(
              square: square,
              child: image != null
                  ? Image.network(image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: color ?? c.surfaceSunken))
                  : ColoredBox(
                      color: color ?? c.surfaceSunken,
                      child: color == null
                          ? Center(
                              child: Text(
                                choice.label.characters.firstOrNull ?? '',
                                style: TextStyle(
                                    fontSize: DsText.xs, color: c.inkMuted),
                              ),
                            )
                          : null,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _clip({required bool square, required Widget child}) => square
      ? ClipRRect(borderRadius: BorderRadius.circular(7), child: child)
      : ClipOval(child: child);
}

class _CheckRow extends StatelessWidget {
  final OptionGroup group;
  final OptionChoice choice;
  final bool selected;
  final VoidCallback? onTap;

  const _CheckRow({
    required this.group,
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final hint = _priceHint(group, choice);
    final label = group.remove ? 'No ${choice.label}' : choice.label;

    return Semantics(
      checked: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: DsRadius.controlAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Checkbox(
                    value: selected,
                    onChanged: onTap == null ? null : (_) => onTap!(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: DsText.base, color: c.ink)),
                ),
                if (hint.isNotEmpty)
                  Text(hint,
                      style: TextStyle(
                          fontSize: DsText.sm,
                          fontWeight: DsWeight.semibold,
                          color: c.inkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final OptionGroup group;
  final OptionSelection selection;
  final ValueChanged<OptionSelection> onChanged;

  const _StepperRow(
      {required this.group, required this.selection, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final s = group.stepper!;
    final value = selection.number(group.key);

    void set(double? v) {
      DsHaptics.select();
      onChanged(selection.withNumber(group.key, v));
    }

    if (value == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => set(s.initial),
          child: Text('Choose ${group.label.toLowerCase()}'),
        ),
      );
    }

    final canLess = value - s.step >= s.min - 1e-9;
    final canMore = value + s.step <= s.max + 1e-9;

    return Row(
      children: [
        IconButton.outlined(
          tooltip: 'Less ${group.label.toLowerCase()}',
          onPressed: canLess
              ? () => set(value - s.step)
              : (group.required ? null : () => set(null)),
          icon: Icon(
              canLess || group.required ? Icons.remove : Icons.delete_outline),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 96),
          alignment: Alignment.center,
          child: Text(
            s.format(value),
            style: TextStyle(
                fontSize: DsText.md, fontWeight: DsWeight.bold, color: c.ink),
          ),
        ),
        IconButton.outlined(
          tooltip: 'More ${group.label.toLowerCase()}',
          onPressed: canMore ? () => set(value + s.step) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Colour swatches and size chips for variants - the way clothing is shopped.
///
/// Falls back to a single list of variant labels when the variants are not a
/// colour x size grid, so any shape of product still works.
class VariantPicker extends StatelessWidget {
  final List<Variant> variants;
  final Variant? selected;
  final ValueChanged<Variant> onChanged;

  const VariantPicker({
    super.key,
    required this.variants,
    required this.selected,
    required this.onChanged,
  });

  static bool isGrid(List<Variant> variants) {
    if (variants.length < 2) return false;
    if (variants.any((v) => v.color.isEmpty || v.size.isEmpty)) return false;
    final colours = variants.map((v) => v.color).toSet();
    final sizes = variants.map((v) => v.size).toSet();
    // A real grid has several of at least one, and no duplicate pairs.
    return (colours.length > 1 || sizes.length > 1) &&
        variants.map((v) => '${v.color}|${v.size}').toSet().length ==
            variants.length;
  }

  Variant? _find(String color, String size) =>
      variants.where((v) => v.color == color && v.size == size).firstOrNull;

  /// The first picture of a colour, if the seller gave it any of its own.
  String? _photoOf(String color) => variants
      .where((v) => v.color == color)
      .expand((v) => v.images)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    if (!isGrid(variants)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose a variant',
              style: TextStyle(
                  fontSize: DsText.base,
                  fontWeight: DsWeight.bold,
                  color: c.ink)),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s2,
            children: [
              for (final v in variants)
                _Pill(
                  label: v.label.isEmpty ? 'Default' : v.label,
                  selected: v.id == selected?.id,
                  available: v.stock > 0,
                  onTap: () => onChanged(v),
                ),
            ],
          ),
        ],
      );
    }

    final colours = <String>[];
    final sizes = <String>[];
    for (final v in variants) {
      if (!colours.contains(v.color)) colours.add(v.color);
      if (!sizes.contains(v.size)) sizes.add(v.size);
    }
    final color = selected?.color ?? colours.first;
    final size = selected?.size ?? sizes.first;

    bool colourHasStock(String col) =>
        variants.any((v) => v.color == col && v.stock > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (colours.length > 1) ...[
          Text.rich(TextSpan(children: [
            TextSpan(
              text: 'Selected colour: ',
              style: TextStyle(
                  fontSize: DsText.base,
                  fontWeight: DsWeight.bold,
                  color: c.ink),
            ),
            TextSpan(
              text: color,
              style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
            ),
          ])),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s3,
            runSpacing: DsSpace.s3,
            children: [
              for (final col in colours)
                _Swatch(
                  square: _photoOf(col) != null,
                  choice: OptionChoice(
                    id: col,
                    label: col,
                    imageUrl: _photoOf(col),
                    color: variants
                        .where((v) => v.color == col)
                        .map((v) => v.swatch)
                        .firstWhere((s) => s != null, orElse: () => null),
                  ),
                  selected: col == color,
                  // Keep the chosen size when this colour has it in stock.
                  onTap: colourHasStock(col)
                      ? () {
                          final same = _find(col, size);
                          onChanged(same != null && same.stock > 0
                              ? same
                              : variants.firstWhere(
                                  (v) => v.color == col && v.stock > 0));
                        }
                      : null,
                ),
            ],
          ),
        ],
        if (sizes.length > 1) ...[
          SizedBox(height: colours.length > 1 ? DsSpace.s5 : 0),
          Text('Size',
              style: TextStyle(
                  fontSize: DsText.base,
                  fontWeight: DsWeight.bold,
                  color: c.ink)),
          const SizedBox(height: DsSpace.s2),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s2,
            children: [
              for (final sz in sizes)
                Builder(builder: (_) {
                  final v = _find(color, sz);
                  return _Pill(
                    label: sz,
                    selected: sz == size,
                    available: v != null && v.stock > 0,
                    onTap: v == null ? null : () => onChanged(v),
                  );
                }),
            ],
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final bool available;
  final VoidCallback? onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      selected: selected,
      button: true,
      label: available ? label : '$label, sold out',
      child: Material(
        color: selected ? c.primary : c.surface,
        borderRadius: DsRadius.controlAll,
        child: InkWell(
          borderRadius: DsRadius.controlAll,
          onTap: available ? onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: DsRadius.controlAll,
              border: Border.all(color: selected ? c.primary : c.line),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 48),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Opacity(
                  opacity: available ? 1 : 0.4,
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: DsText.sm,
                        fontWeight: DsWeight.semibold,
                        color: selected ? c.onPrimary : c.ink,
                        decoration:
                            available ? null : TextDecoration.lineThrough,
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
