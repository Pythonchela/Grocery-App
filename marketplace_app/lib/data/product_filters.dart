/// What a shopper has narrowed a product list down to.
///
/// Turned into the query parameters the products API already understands
/// (`min_price`, `max_price`, `in_stock`, `min_rating`, `brand` and the
/// category-specific `attr[group][]`), so filtering happens on the server over
/// the whole catalogue and not just the page that happens to be loaded.
class ProductFilters {
  final double? minPrice;
  final double? maxPrice;
  final bool inStockOnly;
  final double? minRating;
  final String? brand;

  /// Category-specific choices: filter group id -> chosen values.
  final Map<String, Set<String>> attributes;

  const ProductFilters({
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
    this.minRating,
    this.brand,
    this.attributes = const {},
  });

  static const none = ProductFilters();

  bool get isActive => count > 0;

  /// How many separate things are being filtered on (for the badge on the button).
  int get count =>
      (minPrice != null || maxPrice != null ? 1 : 0) +
      (inStockOnly ? 1 : 0) +
      (minRating != null ? 1 : 0) +
      (brand != null ? 1 : 0) +
      attributes.values.where((v) => v.isNotEmpty).length;

  ProductFilters copyWith({
    Object? minPrice = _keep,
    Object? maxPrice = _keep,
    bool? inStockOnly,
    Object? minRating = _keep,
    Object? brand = _keep,
    Map<String, Set<String>>? attributes,
  }) =>
      ProductFilters(
        minPrice: identical(minPrice, _keep) ? this.minPrice : minPrice as double?,
        maxPrice: identical(maxPrice, _keep) ? this.maxPrice : maxPrice as double?,
        inStockOnly: inStockOnly ?? this.inStockOnly,
        minRating:
            identical(minRating, _keep) ? this.minRating : minRating as double?,
        brand: identical(brand, _keep) ? this.brand : brand as String?,
        attributes: attributes ?? this.attributes,
      );

  /// The API query for this filter set, merged over [base].
  Map<String, String> toQuery([Map<String, String> base = const {}]) {
    final q = {...base};
    if (minPrice != null) q['min_price'] = minPrice!.round().toString();
    if (maxPrice != null) q['max_price'] = maxPrice!.round().toString();
    if (inStockOnly) q['in_stock'] = '1';
    if (minRating != null) q['min_rating'] = minRating!.toString();
    if (brand != null) q['brand'] = brand!;
    attributes.forEach((group, values) {
      var i = 0;
      for (final v in values) {
        q['attr[$group][${i++}]'] = v;
      }
    });
    return q;
  }
}

const Object _keep = Object();

/// One category-specific filter group from the admin's configuration.
class FilterGroup {
  final String id;
  final String label;
  final String type; // checkbox | radio | chip | range
  final List<({String label, String value})> options;

  const FilterGroup(this.id, this.label, this.type, this.options);

  /// Reads `filter_config.groups`, skipping anything malformed and the price
  /// range (price is always offered separately).
  static List<FilterGroup> parse(Map<String, dynamic>? config) {
    final groups = config?['groups'];
    if (groups is! List) return const [];

    final out = <FilterGroup>[];
    for (final g in groups) {
      if (g is! Map) continue;
      final id = g['id']?.toString();
      final type = g['type']?.toString() ?? 'checkbox';
      if (id == null || id.isEmpty || type == 'range' || id == 'price') continue;

      final options = <({String label, String value})>[];
      for (final o in (g['options'] as List? ?? const [])) {
        if (o is! Map) continue;
        final value = (o['value'] ?? o['label'])?.toString() ?? '';
        final label = (o['label'] ?? o['value'])?.toString() ?? '';
        if (value.isNotEmpty && label.isNotEmpty) {
          options.add((label: label, value: value));
        }
      }
      if (options.isEmpty) continue;
      out.add(FilterGroup(id, g['label']?.toString() ?? id, type, options));
    }
    return out;
  }
}
