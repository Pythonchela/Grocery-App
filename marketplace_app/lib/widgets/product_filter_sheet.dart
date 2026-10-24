import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/product_filters.dart';
import '../design/components.dart';
import '../design/mobile.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// The filter sheet shared by category pages and search: price range, stock,
/// rating, brand, and whatever category-specific groups the admin configured
/// (fabric, size, cuisine... whatever suits the store).
///
/// Returns the new filters on Apply, or null if dismissed.
Future<ProductFilters?> showProductFilterSheet(
  BuildContext context, {
  required ProductFilters current,
  required double priceCeiling,
  List<String> brands = const [],
  List<FilterGroup> groups = const [],
}) {
  return showBxSheet<ProductFilters>(
    context: context,
    title: 'Filters',
    child: _FilterBody(
      initial: current,
      priceCeiling: priceCeiling,
      brands: brands,
      groups: groups,
    ),
  );
}

class _FilterBody extends StatefulWidget {
  final ProductFilters initial;
  final double priceCeiling;
  final List<String> brands;
  final List<FilterGroup> groups;

  const _FilterBody({
    required this.initial,
    required this.priceCeiling,
    required this.brands,
    required this.groups,
  });

  @override
  State<_FilterBody> createState() => _FilterBodyState();
}

class _FilterBodyState extends State<_FilterBody> {
  late ProductFilters _f = widget.initial;

  /// A sensible slider range: whole thousands above the dearest product shown,
  /// never smaller than a few hundred so a cheap catalogue is still usable.
  late final double _max = () {
    final ceil = widget.priceCeiling <= 0 ? 1000.0 : widget.priceCeiling;
    final step = ceil > 5000 ? 1000.0 : 500.0;
    return (ceil / step).ceil() * step;
  }();

  RangeValues get _range =>
      RangeValues(_f.minPrice ?? 0, (_f.maxPrice ?? _max).clamp(0, _max));

  void _toggle(FilterGroup group, String value) {
    final all = {for (final e in _f.attributes.entries) e.key: {...e.value}};
    final chosen = all.putIfAbsent(group.id, () => <String>{});
    if (group.type == 'radio') {
      final already = chosen.contains(value);
      chosen.clear();
      if (!already) chosen.add(value);
    } else {
      chosen.contains(value) ? chosen.remove(value) : chosen.add(value);
    }
    setState(() => _f = _f.copyWith(attributes: all));
  }

  Widget _label(String text) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(top: DsSpace.s5, bottom: DsSpace.s2),
      child: Text(text,
          style: TextStyle(
              fontSize: DsText.base,
              fontWeight: DsWeight.bold,
              color: c.ink)),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) {
        DsHaptics.select();
        onTap();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final range = _range;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label('Price'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatMoney(range.start),
                style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
            Text(
                range.end >= _max
                    ? '${formatMoney(_max)}+'
                    : formatMoney(range.end),
                style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
          ],
        ),
        RangeSlider(
          values: range,
          min: 0,
          max: _max,
          divisions: (_max / (_max > 5000 ? 500 : 100)).round(),
          onChanged: (v) => setState(() => _f = _f.copyWith(
                minPrice: v.start <= 0 ? null : v.start,
                maxPrice: v.end >= _max ? null : v.end,
              )),
        ),
        const SizedBox(height: DsSpace.s2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('In stock only',
              style: TextStyle(
                  fontSize: DsText.base,
                  fontWeight: DsWeight.semibold,
                  color: c.ink)),
          value: _f.inStockOnly,
          onChanged: (v) => setState(() => _f = _f.copyWith(inStockOnly: v)),
        ),
        _label('Rating'),
        Wrap(
          spacing: DsSpace.s2,
          children: [
            _chip('Any', _f.minRating == null,
                () => setState(() => _f = _f.copyWith(minRating: null))),
            for (final r in [3.0, 4.0])
              _chip('${r.toInt()}★ & up', _f.minRating == r,
                  () => setState(() => _f = _f.copyWith(minRating: r))),
          ],
        ),
        if (widget.brands.isNotEmpty) ...[
          _label('Brand'),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s1,
            children: [
              for (final b in widget.brands)
                _chip(
                    b,
                    _f.brand == b,
                    () => setState(() =>
                        _f = _f.copyWith(brand: _f.brand == b ? null : b))),
            ],
          ),
        ],
        for (final group in widget.groups) ...[
          _label(group.label),
          Wrap(
            spacing: DsSpace.s2,
            runSpacing: DsSpace.s1,
            children: [
              for (final o in group.options)
                _chip(
                  o.label,
                  _f.attributes[group.id]?.contains(o.value) ?? false,
                  () => _toggle(group, o.value),
                ),
            ],
          ),
        ],
        const SizedBox(height: DsSpace.s6),
        Row(
          children: [
            Expanded(
              child: BxButton(
                label: 'Clear all',
                variant: BxButtonVariant.secondary,
                fullWidth: true,
                onPressed: _f.isActive
                    ? () => setState(() => _f = ProductFilters.none)
                    : null,
              ),
            ),
            const SizedBox(width: DsSpace.s3),
            Expanded(
              flex: 2,
              child: BxButton(
                label: _f.isActive ? 'Show results (${_f.count})' : 'Show results',
                fullWidth: true,
                onPressed: () => Navigator.of(context).pop(_f),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
