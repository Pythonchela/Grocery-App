import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import 'rich_text_view.dart';

/// "All details" on a product page: Specifications, Description and
/// Manufacturer info as tabs. A tab only appears when it has something to show,
/// and the whole section is absent for a product with none of the three.
class ProductDetailsTabs extends StatefulWidget {
  final Product product;

  /// How many specification rows show before "See all".
  final int collapsedRows;

  const ProductDetailsTabs({super.key, required this.product, this.collapsedRows = 10});

  @override
  State<ProductDetailsTabs> createState() => _ProductDetailsTabsState();
}

enum _Tab { specifications, description, manufacturer }

class _ProductDetailsTabsState extends State<ProductDetailsTabs> {
  _Tab? _selected;
  bool _expanded = false;

  Product get _p => widget.product;

  List<_Tab> get _tabs => [
        if (_p.specifications.isNotEmpty) _Tab.specifications,
        if (_p.descriptionHtml != null || _p.description.trim().isNotEmpty) _Tab.description,
        if (_p.manufacturer.isNotEmpty) _Tab.manufacturer,
      ];

  static String _label(_Tab t) => switch (t) {
        _Tab.specifications => 'Specifications',
        _Tab.description => 'Description',
        _Tab.manufacturer => 'Manufacturer info',
      };

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs.isEmpty) return const SizedBox.shrink();

    final c = context.ds;
    final current = tabs.contains(_selected) ? _selected! : tabs.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('All details',
            style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
        const SizedBox(height: DsSpace.s3),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in tabs)
                Padding(
                  padding: const EdgeInsets.only(right: DsSpace.s2),
                  child: _TabPill(
                    label: _label(t),
                    selected: t == current,
                    onTap: () => setState(() => _selected = t),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: DsSpace.s4),
        switch (current) {
          _Tab.specifications => _specifications(c),
          _Tab.description => _description(c),
          _Tab.manufacturer => _manufacturer(c),
        },
      ],
    );
  }

  // ── Specifications ─────────────────────────────────────────────────

  Widget _specifications(DsColors c) {
    final total = _p.specifications.fold<int>(0, (n, g) => n + g.rows.length);
    final collapsible = total > widget.collapsedRows;
    var budget = _expanded || !collapsible ? total : widget.collapsedRows;

    final sections = <Widget>[];
    for (final group in _p.specifications) {
      if (budget <= 0) break;
      final rows = group.rows.take(budget).toList();
      budget -= rows.length;
      sections.add(Padding(
        padding: EdgeInsets.only(top: sections.isEmpty ? 0 : DsSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.title,
                style: TextStyle(fontSize: DsText.md, fontWeight: DsWeight.bold, color: c.ink)),
            const SizedBox(height: DsSpace.s2),
            _pairs(rows, c),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...sections,
        if (collapsible) ...[
          const SizedBox(height: DsSpace.s4),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18),
              label: Text(_expanded ? 'See less' : 'See all $total'),
            ),
          ),
        ],
      ],
    );
  }

  /// Rows laid out two to a line, label above value, a rule under each line.
  Widget _pairs(List<SpecRow> rows, DsColors c) {
    Widget cell(SpecRow r) => Padding(
          padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.label, style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
              const SizedBox(height: 2),
              Text(r.value,
                  style: TextStyle(
                      fontSize: DsText.base, fontWeight: DsWeight.semibold, color: c.ink)),
            ],
          ),
        );

    return LayoutBuilder(builder: (context, box) {
      final twoUp = box.maxWidth >= 300;
      final lines = <List<SpecRow>>[];
      for (var i = 0; i < rows.length; i += twoUp ? 2 : 1) {
        lines.add(rows.sublist(i, twoUp && i + 1 < rows.length ? i + 2 : i + 1));
      }

      return Column(
        children: [
          for (final line in lines)
            Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cell(line.first)),
                  const SizedBox(width: DsSpace.s4),
                  Expanded(child: line.length > 1 ? cell(line[1]) : const SizedBox.shrink()),
                ],
              ),
            ),
        ],
      );
    });
  }

  // ── Description ────────────────────────────────────────────────────

  Widget _description(DsColors c) {
    if (_p.descriptionHtml != null) return RichTextView(html: _p.descriptionHtml!);

    return Text(
      _p.description.trim(),
      style: TextStyle(fontSize: DsText.base, height: DsText.baseHeight, color: c.inkMuted),
    );
  }

  // ── Manufacturer ───────────────────────────────────────────────────

  Widget _manufacturer(DsColors c) {
    final short = <SpecRow>[];
    final long = <SpecRow>[];
    for (final e in _p.manufacturer.entries) {
      (e.key.startsWith('Address') || e.key.startsWith('Name') ? long : short)
          .add(SpecRow(e.key, e.value));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (short.isNotEmpty) _pairs(short, c),
        for (final r in long)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label, style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                const SizedBox(height: 2),
                Text(r.value,
                    style: TextStyle(
                        fontSize: DsText.base, fontWeight: DsWeight.semibold, color: c.ink)),
              ],
            ),
          ),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected ? c.primary : c.surfaceSunken,
        borderRadius: DsRadius.pillAll,
        child: InkWell(
          borderRadius: DsRadius.pillAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(label,
                style: TextStyle(
                    fontSize: DsText.sm,
                    fontWeight: DsWeight.bold,
                    color: selected ? c.onPrimary : c.ink)),
          ),
        ),
      ),
    );
  }
}
