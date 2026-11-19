import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import 'category_shortcuts.dart';
import 'diet_mark.dart';
import 'product_rail.dart';

/// The pieces of the food and grocery app's home page: how soon, a search box, the categories as
/// a grid, and a rail of products for each. Built the way quick-delivery apps are, because that is
/// what a shopper hungry or out of milk expects: the answer to "how fast" first, search one tap
/// away, and ADD on every item.

/// "15–25 min", from the preparation times the products themselves declare; null when none do.
String? readyRange(Iterable<Product> products) {
  final minutes = products.map((p) => p.prepMinutes).where((m) => m > 0).toList()..sort();
  if (minutes.isEmpty) return null;
  final low = minutes.first;
  final high = minutes.last;
  return low == high ? '$low min' : '$low–$high min';
}

/// The search box that sits in the pinned header. It is a button that opens the search page.
class QuickSearchBar extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;

  const QuickSearchBar({super.key, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      button: true,
      label: 'Search',
      child: Material(
        color: c.surface,
        borderRadius: DsRadius.panelAll,
        child: InkWell(
          borderRadius: DsRadius.panelAll,
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
            decoration: BoxDecoration(
              borderRadius: DsRadius.panelAll,
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 22, color: c.inkMuted),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Text(hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: DsText.md, color: c.inkSubtle)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Veg only / Offers: the quick filters that sit above the product rails.
class QuickToolbar extends StatelessWidget {
  final bool vegOnly;
  final bool offersOnly;
  final ValueChanged<bool> onVeg;
  final ValueChanged<bool> onOffers;

  const QuickToolbar({
    super.key,
    required this.vegOnly,
    required this.offersOnly,
    required this.onVeg,
    required this.onOffers,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    Widget chip({required String label, required bool on, required VoidCallback onTap, Widget? leading}) {
      return Material(
        color: on ? c.accentSoft : c.surface,
        borderRadius: DsRadius.pillAll,
        child: InkWell(
          borderRadius: DsRadius.pillAll,
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
            decoration: BoxDecoration(
              borderRadius: DsRadius.pillAll,
              border: Border.all(color: on ? c.accent : c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading, const SizedBox(width: DsSpace.s2)],
                Text(label,
                    style: TextStyle(
                        fontSize: DsText.sm,
                        fontWeight: DsWeight.semibold,
                        color: on ? c.accent : c.inkMuted)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s3, DsSpace.s4, 0),
      child: Wrap(
        spacing: DsSpace.s2,
        runSpacing: DsSpace.s2,
        children: [
          chip(
            label: 'Veg only',
            on: vegOnly,
            leading: const DietMark('veg', size: 14),
            onTap: () => onVeg(!vegOnly),
          ),
          chip(
            label: 'Offers',
            on: offersOnly,
            leading: Icon(Icons.local_offer_outlined, size: 15, color: offersOnly ? c.accent : c.inkMuted),
            onTap: () => onOffers(!offersOnly),
          ),
        ],
      ),
    );
  }
}

/// Every category as a tile in a grid, four to a row, like the aisles of a shop.
class QuickCategoryGrid extends StatelessWidget {
  final List<Category> categories;
  final ValueChanged<Category> onSelected;

  const QuickCategoryGrid({super.key, required this.categories, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    if (categories.isEmpty) return const SizedBox.shrink();

    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return Padding(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: categories.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: scale > 1.5 ? 2 : 4,
          mainAxisSpacing: DsSpace.s3,
          crossAxisSpacing: DsSpace.s2,
          mainAxisExtent: 98 * scale,
        ),
        itemBuilder: (context, i) {
          final category = categories[i];
          return InkWell(
            borderRadius: DsRadius.cardAll,
            onTap: () => onSelected(category),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                CategoryThumb(category: category, size: 62),
                const SizedBox(height: DsSpace.s2),
                Text(category.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: DsText.xs,
                        height: 1.25,
                        fontWeight: DsWeight.semibold,
                        color: c.ink)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A heading with "See all", then a rail of product tiles.
class QuickSection extends StatelessWidget {
  final String title;
  final List<Product> products;
  final void Function(Product) onTap;
  final VoidCallback? onSeeAll;

  const QuickSection({
    super.key,
    required this.title,
    required this.products,
    required this.onTap,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s5, DsSpace.s2, DsSpace.s2),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontFamily: DsFont.display,
                        fontSize: DsText.lg,
                        fontWeight: DsWeight.black,
                        color: c.ink)),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: Text('See all',
                      style: TextStyle(
                          fontSize: DsText.sm,
                          fontWeight: DsWeight.bold,
                          color: c.accent)),
                ),
            ],
          ),
        ),
        ProductRail(products: products, onTap: onTap),
      ],
    );
  }
}
