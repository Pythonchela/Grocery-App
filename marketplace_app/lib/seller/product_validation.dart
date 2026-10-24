import 'screens/variant_row.dart' show parseMoney;

/// One variant as typed, before parsing.
class VariantDraft {
  final String stock;
  final String sku;
  final String price;
  final String mrp;

  const VariantDraft({this.stock = '', this.sku = '', this.price = '', this.mrp = ''});
}

/// Checks the product form before anything is sent, so a seller hears about a
/// mistake straight away rather than after an upload and a round trip. The API
/// still validates everything and its answer wins.
///
/// Errors are keyed the way the API keys its own: `title`, `category_id`, `mrp`,
/// `price`, and `variants.N.stock|sku|price|mrp` — so the form shows a local
/// error and a server error in the same place. `photos` and `variants` are for
/// problems that belong to a whole section.
class ProductValidation {
  static const statuses = ['DRAFT', 'ACTIVE', 'OUT_OF_STOCK', 'DISCONTINUED'];

  static Map<String, String> validate({
    required String title,
    required String? categoryId,
    required String mrp,
    required String price,
    required String status,
    required int photoCount,
    required List<VariantDraft> variants,
  }) {
    final errors = <String, String>{};

    if (title.trim().isEmpty) {
      errors['title'] = 'Enter a product name.';
    } else if (title.trim().length > 255) {
      errors['title'] = 'That name is too long (255 characters at most).';
    }

    if (categoryId == null || categoryId.isEmpty) errors['category_id'] = 'Choose a category.';

    final mrpValue = parseMoney(mrp);
    final priceValue = parseMoney(price);

    if (mrpValue == null) {
      errors['mrp'] = 'Enter the MRP.';
    } else if (mrpValue <= 0) {
      errors['mrp'] = 'The MRP must be more than 0.';
    }

    if (priceValue == null) {
      errors['price'] = 'Enter the selling price.';
    } else if (priceValue <= 0) {
      errors['price'] = 'The selling price must be more than 0.';
    } else if (mrpValue != null && mrpValue > 0 && priceValue > mrpValue) {
      errors['price'] = 'The selling price cannot be higher than the MRP.';
    }

    // A live product with no photo is a listing nobody will click.
    if (status == 'ACTIVE' && photoCount == 0) {
      errors['photos'] = 'Add at least one photo before making this product live.';
    }

    if (variants.isEmpty) errors['variants'] = 'Add at least one variant.';

    final seenSkus = <String>{};
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];

      final stock = v.stock.trim();
      if (stock.isEmpty) {
        errors['variants.$i.stock'] = 'Enter the stock.';
      } else {
        final n = int.tryParse(stock);
        if (n == null || n < 0) errors['variants.$i.stock'] = 'Stock must be a whole number, 0 or more.';
      }

      final sku = v.sku.trim();
      if (sku.length > 80) {
        errors['variants.$i.sku'] = 'That SKU is too long.';
      } else if (sku.isNotEmpty && !seenSkus.add(sku.toLowerCase())) {
        errors['variants.$i.sku'] = 'This SKU is used by another variant here.';
      }

      final vPrice = v.price.trim().isEmpty ? null : parseMoney(v.price);
      final vMrp = v.mrp.trim().isEmpty ? null : parseMoney(v.mrp);

      if (v.price.trim().isNotEmpty && (vPrice == null || vPrice < 0)) {
        errors['variants.$i.price'] = 'Enter a valid price.';
      }
      if (v.mrp.trim().isNotEmpty && (vMrp == null || vMrp < 0)) {
        errors['variants.$i.mrp'] = 'Enter a valid MRP.';
      }
      if (vPrice != null && vMrp != null && vPrice > vMrp && !errors.containsKey('variants.$i.price')) {
        errors['variants.$i.price'] = 'The price cannot be higher than the MRP.';
      }
    }

    return errors;
  }
}
