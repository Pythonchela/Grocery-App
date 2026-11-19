import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// A round picture for a category: its photo when it has one, otherwise its icon.
class CategoryThumb extends StatelessWidget {
  final Category category;
  final double size;

  const CategoryThumb({super.key, required this.category, this.size = 64});

  /// Icon names the admin can choose, mapped to Material icons.
  static const icons = {
    'Sparkles': Icons.auto_awesome_outlined,
    'Shirt': Icons.checkroom_outlined,
    'Zap': Icons.directions_walk_outlined,
    'Footprints': Icons.directions_walk_outlined,
    'Headphones': Icons.headphones_outlined,
    'Cpu': Icons.memory_outlined,
    'Home': Icons.chair_outlined,
    'Leaf': Icons.eco_outlined,
    'Flame': Icons.restaurant_outlined,
    'ShoppingBag': Icons.shopping_basket_outlined,
    'Gift': Icons.cake_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final image = category.imageUrl;

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
      child: Icon(icons[category.iconUrl] ?? Icons.category_outlined,
          size: size * 0.42, color: c.accent),
    );

    if (image == null) return fallback;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: c.surfaceSunken,
          child: Image.network(
            image,
            fit: BoxFit.cover,
            // A dead image falls back to the icon rather than a blank circle.
            errorBuilder: (_, __, ___) => fallback,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Categories as round pictures with the name beneath - the way phone shopping
/// apps show them.
///
/// By default they wrap onto rows so nothing is hidden (the Categories tab).
/// With [scrollable] they sit in one row that scrolls sideways, which is what
/// the home page wants: a long list must not push everything else off screen.
class CategoryShortcuts extends StatelessWidget {
  final List<Category> categories;
  final ValueChanged<Category> onSelected;
  final bool scrollable;

  const CategoryShortcuts({
    super.key,
    required this.categories,
    required this.onSelected,
    this.scrollable = false,
  });

  /// Wide enough that a name like "Restaurant" fits on one line at normal text size.
  static const double _itemWidth = 74;

  Widget _item(BuildContext context, Category category, double width,
      double scale) {
    final c = context.ds;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: 'Browse ${category.name}',
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('category-${category.slug}'),
          borderRadius: DsRadius.cardAll,
          onTap: () => onSelected(category),
          child: Column(children: [
            CategoryThumb(category: category, size: width < 72 ? width - 4 : 64),
            const SizedBox(height: DsSpace.s2),
            SizedBox(
              height: 34 * scale,
              child: Text(
                category.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: DsText.x2xs,
                    height: 1.35,
                    fontWeight: DsWeight.medium,
                    color: c.ink),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final category in categories)
              Padding(
                padding: const EdgeInsets.only(right: DsSpace.s1),
                child: _item(context, category,
                    scale > 1.3 ? 96 : _itemWidth, scale),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
      child: LayoutBuilder(builder: (context, constraints) {
        final minWidth = scale > 1.3 ? 96.0 : _itemWidth;
        final columns = (constraints.maxWidth / minWidth).floor().clamp(3, 8);
        final width =
            (constraints.maxWidth - (columns - 1) * DsSpace.s2) / columns;

        return Wrap(
          spacing: DsSpace.s2,
          runSpacing: DsSpace.s4,
          children: [
            for (final category in categories)
              _item(context, category, width, scale),
          ],
        );
      }),
    );
  }
}

/// A row of small category buttons - picture and name - along the top of a
/// list page, so you can hop to another category without going back.
///
/// Every button is the same size whether or not it is selected: only colours
/// change. (A thicker border or bolder text on the chosen one made the row
/// shift as you moved between categories.)
class CategoryStrip extends StatefulWidget {
  final List<Category> categories;
  final String selectedSlug;
  final ValueChanged<Category> onSelected;

  const CategoryStrip({
    super.key,
    required this.categories,
    required this.selectedSlug,
    required this.onSelected,
  });

  @override
  State<CategoryStrip> createState() => _CategoryStripState();
}

class _CategoryStripState extends State<CategoryStrip> {
  final _keys = <String, GlobalKey>{};

  GlobalKey _keyFor(String slug) => _keys.putIfAbsent(slug, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _showSelected();
  }

  @override
  void didUpdateWidget(CategoryStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedSlug != widget.selectedSlug) _showSelected();
  }

  /// Keeps the chosen button on screen, centred if the row has to scroll.
  void _showSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[widget.selectedSlug]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: const Duration(milliseconds: 200));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    // A plain scrolling row (not a lazy list) so every button exists and can be
    // scrolled to; there are only ever a handful of categories.
    return SizedBox(
      height: 56,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: DsSpace.s4, vertical: DsSpace.s2),
        child: Row(
          children: [
            for (final category in widget.categories)
              Padding(
                key: _keyFor(category.slug),
                padding: const EdgeInsets.only(right: DsSpace.s2),
                child: _StripButton(
                  category: category,
                  selected: category.slug == widget.selectedSlug,
                  onTap: () => widget.onSelected(category),
                  colors: c,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  final Category category;
  final bool selected;
  final VoidCallback onTap;
  final DsColors colors;

  const _StripButton({
    required this.category,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Semantics(
      button: true,
      selected: selected,
      label: category.name,
      child: Material(
        color: selected ? c.accentSoft : c.surface,
        borderRadius: DsRadius.pillAll,
        child: InkWell(
          key: ValueKey('strip-${category.slug}'),
          borderRadius: DsRadius.pillAll,
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.only(left: 4, right: 12),
            decoration: BoxDecoration(
              borderRadius: DsRadius.pillAll,
              // Same width for both states; only the colour changes.
              border: Border.all(color: selected ? c.accent : c.line, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CategoryThumb(category: category, size: 30),
                const SizedBox(width: DsSpace.s2),
                Text(
                  category.name,
                  style: TextStyle(
                    fontSize: DsText.sm,
                    fontWeight: DsWeight.semibold,
                    color: selected ? c.accent : c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
