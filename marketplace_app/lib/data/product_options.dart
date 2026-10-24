import 'package:flutter/material.dart';

/// Custom selection options - portion, add-ons, "leave out", colour swatches,
/// a quantity in kg - as the API describes them for a product.
///
/// The server prices an order from the choices (never from a number the app
/// sends); the arithmetic here only previews the price while the shopper picks,
/// and mirrors `ProductOptions::resolve()` on the backend rule for rule.
enum OptionType { single, multi, swatch, stepper }

/// How a group moves the price.
///  - [set]: the picked choice's price replaces the base (Half 180 / Full 320).
///  - [add]: it is added on top (extra cheese +30).
///  - [multiply]: the value multiplies the per-unit base price (1.5 kg x 60).
enum OptionPriceMode { set, add, multiply }

class OptionChoice {
  final String id;
  final String label;
  final double price;
  final Color? color;
  final String? imageUrl;
  final bool isDefault;
  final bool available;

  /// Null = not counted. A number is how many of this choice are left.
  final int? stock;

  const OptionChoice({
    required this.id,
    required this.label,
    this.price = 0,
    this.color,
    this.imageUrl,
    this.isDefault = false,
    this.available = true,
    this.stock,
  });

  bool get selectable => available && (stock == null || stock! > 0);

  factory OptionChoice.fromJson(Map<String, dynamic> j) => OptionChoice(
        id: '${j['id']}',
        label: '${j['label'] ?? ''}',
        price: _d(j['price']),
        color: parseHexColor(j['color']),
        imageUrl: _s(j['image']),
        isDefault: j['default'] == true,
        available: j['available'] != false,
        stock: j['stock'] is num ? (j['stock'] as num).toInt() : null,
      );
}

class StepperSpec {
  final double min;
  final double max;
  final double step;
  final String unit;
  final double initial;

  /// Rupees per step when the group's price mode is "add".
  final double price;

  const StepperSpec({
    this.min = 1,
    this.max = 10,
    this.step = 1,
    this.unit = '',
    this.initial = 1,
    this.price = 0,
  });

  factory StepperSpec.fromJson(Map<String, dynamic> j) => StepperSpec(
        min: _d(j['min'], 1),
        max: _d(j['max'], 10),
        step: _d(j['step'], 1) <= 0 ? 1 : _d(j['step'], 1),
        unit: '${j['unit'] ?? ''}',
        initial: _d(j['default'], _d(j['min'], 1)),
        price: _d(j['price']),
      );

  /// 1.5 -> "1.5", 2.0 -> "2", with the unit: "1.5 kg".
  String format(double value) =>
      '${formatOptionNumber(value)}${unit.isEmpty ? '' : ' $unit'}';
}

class OptionGroup {
  final String key;
  final String label;
  final OptionType type;
  final bool required;
  final int min;
  final int max;
  final OptionPriceMode priceMode;

  /// A "leave out" list ("no onion"): picks are free and read as removals.
  final bool remove;
  final String? help;
  final StepperSpec? stepper;
  final List<OptionChoice> choices;

  const OptionGroup({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.min = 0,
    this.max = 1,
    this.priceMode = OptionPriceMode.add,
    this.remove = false,
    this.help,
    this.stepper,
    this.choices = const [],
  });

  bool get isStepper => type == OptionType.stepper;
  bool get isMulti => type == OptionType.multi;

  factory OptionGroup.fromJson(Map<String, dynamic> j) {
    final type = switch (j['type']) {
      'multi' => OptionType.multi,
      'swatch' => OptionType.swatch,
      'stepper' => OptionType.stepper,
      _ => OptionType.single,
    };
    return OptionGroup(
      key: '${j['key']}',
      label: '${j['label'] ?? ''}',
      type: type,
      required: j['required'] == true,
      min: (j['min'] as num?)?.toInt() ?? 0,
      max: (j['max'] as num?)?.toInt() ?? 1,
      priceMode: switch (j['price_mode']) {
        'set' => OptionPriceMode.set,
        'multiply' => OptionPriceMode.multiply,
        _ => OptionPriceMode.add,
      },
      remove: j['remove'] == true,
      help: _s(j['help']),
      stepper: type == OptionType.stepper && j['stepper'] is Map
          ? StepperSpec.fromJson((j['stepper'] as Map).cast<String, dynamic>())
          : null,
      choices: ((j['choices'] as List?) ?? [])
          .whereType<Map>()
          .map((c) => OptionChoice.fromJson(c.cast<String, dynamic>()))
          .toList(),
    );
  }

  /// Skips anything malformed rather than failing the whole product.
  static List<OptionGroup> parseList(Object? raw) {
    if (raw is! List) return const [];
    final groups = <OptionGroup>[];
    for (final g in raw) {
      if (g is! Map) continue;
      try {
        final group = OptionGroup.fromJson(g.cast<String, dynamic>());
        if (group.key.isEmpty || group.label.isEmpty) continue;
        if (!group.isStepper && group.choices.isEmpty) continue;
        groups.add(group);
      } catch (_) {}
    }
    return groups;
  }
}

/// What the shopper has picked: choice ids per group, and a number per stepper.
@immutable
class OptionSelection {
  final Map<String, List<String>> choices;
  final Map<String, double> numbers;

  const OptionSelection({this.choices = const {}, this.numbers = const {}});

  static const empty = OptionSelection();

  bool get isEmpty =>
      choices.values.every((v) => v.isEmpty) && numbers.isEmpty;

  List<String> of(String key) => choices[key] ?? const [];
  double? number(String key) => numbers[key];

  /// The defaults the product page opens with: each group's flagged choice, and
  /// each stepper at its starting value.
  factory OptionSelection.defaults(List<OptionGroup> groups) {
    final choices = <String, List<String>>{};
    final numbers = <String, double>{};
    for (final g in groups) {
      if (g.isStepper) {
        if (g.required && g.stepper != null) numbers[g.key] = g.stepper!.initial;
        continue;
      }
      final flagged =
          g.choices.where((c) => c.isDefault && c.selectable).map((c) => c.id);
      if (flagged.isNotEmpty) {
        choices[g.key] = g.isMulti ? flagged.toList() : [flagged.first];
      }
    }
    return OptionSelection(choices: choices, numbers: numbers);
  }

  OptionSelection withChoices(String key, List<String> ids) {
    final next = {...choices};
    ids.isEmpty ? next.remove(key) : next[key] = ids;
    return OptionSelection(choices: next, numbers: numbers);
  }

  OptionSelection withNumber(String key, double? value) {
    final next = {...numbers};
    value == null ? next.remove(key) : next[key] = value;
    return OptionSelection(choices: choices, numbers: next);
  }

  /// The request body shape: {group: [ids]} or {group: number}.
  Map<String, dynamic> toJson() => {
        for (final e in choices.entries)
          if (e.value.isNotEmpty) e.key: e.value,
        ...numbers,
      };

  factory OptionSelection.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final choices = <String, List<String>>{};
    final numbers = <String, double>{};
    raw.forEach((k, v) {
      if (v is List) {
        choices['$k'] = v.map((e) => '$e').toList();
      } else if (v is num) {
        numbers['$k'] = v.toDouble();
      }
    });
    return OptionSelection(choices: choices, numbers: numbers);
  }

  /// Equal selections share a signature - used to merge identical cart lines.
  String get signature {
    final parts = <String>[
      for (final e in choices.entries)
        if (e.value.isNotEmpty)
          '${e.key}=${([...e.value]..sort()).join(',')}',
      for (final e in numbers.entries) '${e.key}=${formatOptionNumber(e.value)}',
    ]..sort();
    return parts.join('|');
  }
}

/// One line of "what you chose", ready to print under a cart or order row.
class OptionPick {
  final String label;
  final String value;
  final bool removal;
  const OptionPick(this.label, this.value, {this.removal = false});
}

class ProductOptionMath {
  const ProductOptionMath._();

  /// The unit price with the shopper's picks on it.
  static double unitPrice(
      double base, List<OptionGroup> groups, OptionSelection selection) {
    double? setPrice;
    var multiplier = 1.0;
    var add = 0.0;

    for (final g in groups) {
      if (g.isStepper) {
        final v = selection.number(g.key);
        final s = g.stepper;
        if (v == null || s == null) continue;
        if (g.priceMode == OptionPriceMode.multiply) {
          multiplier *= v;
        } else {
          add += v * s.price;
        }
        continue;
      }
      for (final id in selection.of(g.key)) {
        final c = g.choices.where((c) => c.id == id).firstOrNull;
        if (c == null) continue;
        if (g.priceMode == OptionPriceMode.set) {
          setPrice = c.price;
        } else {
          add += c.price;
        }
      }
    }
    return _round((setPrice ?? base) * multiplier + add);
  }

  /// The first thing wrong with the selection (what the product page shows
  /// beside the disabled button), or null when it can be ordered.
  static String? problem(List<OptionGroup> groups, OptionSelection selection) {
    for (final g in groups) {
      if (g.isStepper) {
        final v = selection.number(g.key);
        if (v == null) {
          if (g.required) return 'Choose ${g.label}';
          continue;
        }
        final s = g.stepper!;
        if (v < s.min - 1e-9 || v > s.max + 1e-9) return '${g.label} is out of range';
        continue;
      }

      final picked = selection.of(g.key);
      if (picked.isEmpty) {
        if (g.required || g.min > 0) return 'Choose ${g.label}';
        continue;
      }
      if (picked.length < g.min) return 'Choose at least ${g.min} for ${g.label}';
      if (g.isMulti && picked.length > g.max) {
        return 'Choose at most ${g.max} for ${g.label}';
      }
      for (final id in picked) {
        final c = g.choices.where((c) => c.id == id).firstOrNull;
        if (c == null || !c.selectable) return '${c?.label ?? id} is not available';
      }
    }
    return null;
  }

  /// "Portion: Full plate", "Add-ons: Extra cheese, Egg", "Leave out: Onion",
  /// "Weight: 1.5 kg" - the picks in the order the groups appear.
  static List<OptionPick> summary(
      List<OptionGroup> groups, OptionSelection selection) {
    final picks = <OptionPick>[];
    for (final g in groups) {
      if (g.isStepper) {
        final v = selection.number(g.key);
        if (v != null && g.stepper != null) {
          picks.add(OptionPick(g.label, g.stepper!.format(v)));
        }
        continue;
      }
      final labels = [
        for (final id in selection.of(g.key))
          if (g.choices.where((c) => c.id == id).firstOrNull case final c?)
            c.label,
      ];
      if (labels.isNotEmpty) {
        picks.add(OptionPick(g.label, labels.join(', '), removal: g.remove));
      }
    }
    return picks;
  }
}

/// "#1F3A93" or "#1F3A93CC" -> Color; anything else -> null.
Color? parseHexColor(Object? raw) {
  if (raw is! String) return null;
  final hex = raw.trim().replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) return null;
  final v = int.tryParse(hex, radix: 16);
  if (v == null) return null;
  return Color(hex.length == 6 ? 0xFF000000 | v : ((v & 0xFF) << 24) | (v >> 8));
}

/// Common colour names -> a swatch, so a variant called "Navy" needs no extra
/// setup. A variant's own `color_hex` always wins over this.
Color? swatchForName(String name) {
  const known = {
    'black': 0xFF1B1B1F,
    'white': 0xFFFFFFFF,
    'red': 0xFFD32F2F,
    'maroon': 0xFF7B1E2B,
    'pink': 0xFFEC6A9B,
    'orange': 0xFFF57C00,
    'yellow': 0xFFFBC02D,
    'mustard': 0xFFD4A017,
    'green': 0xFF2E7D32,
    'olive': 0xFF6B7A2A,
    'teal': 0xFF00897B,
    'blue': 0xFF1E5BD8,
    'navy': 0xFF1F2A5A,
    'sky blue': 0xFF5DADE2,
    'purple': 0xFF7B3FA0,
    'violet': 0xFF7E57C2,
    'brown': 0xFF6D4C41,
    'beige': 0xFFD9C7A3,
    'cream': 0xFFF3EAD3,
    'grey': 0xFF8E8E93,
    'gray': 0xFF8E8E93,
    'silver': 0xFFBFC3C9,
    'gold': 0xFFD4AF37,
    'tan': 0xFFB98B5E,
  };
  final v = known[name.trim().toLowerCase()];
  return v == null ? null : Color(v);
}

String formatOptionNumber(double v) {
  final s = v.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

double _round(double v) => (v * 100).round() / 100;

double _d(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? fallback);

String? _s(Object? v) {
  final t = v?.toString().trim();
  return t == null || t.isEmpty ? null : t;
}
