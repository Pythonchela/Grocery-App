import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_models.dart';

/// The text controllers behind one variant on the product form.
///
/// An existing variant keeps its [id] so the server edits it rather than
/// replacing it, which is what keeps past orders attached to the size and colour
/// they were placed against.
class VariantRow {
  final String? id;
  final TextEditingController color;
  final TextEditingController size;
  final TextEditingController sku;
  final TextEditingController stock;
  final TextEditingController price;
  final TextEditingController mrp;

  VariantRow({
    this.id,
    String color = '',
    String size = '',
    String sku = '',
    String stock = '',
    String price = '',
    String mrp = '',
  })  : color = TextEditingController(text: color),
        size = TextEditingController(text: size),
        sku = TextEditingController(text: sku),
        stock = TextEditingController(text: stock),
        price = TextEditingController(text: price),
        mrp = TextEditingController(text: mrp);

  factory VariantRow.fromVariant(SellerVariant v) => VariantRow(
        id: v.id,
        color: v.color,
        size: v.size,
        sku: v.sku,
        stock: '${v.stock}',
        price: v.price == null ? '' : _plain(v.price!),
        mrp: v.mrp == null ? '' : _plain(v.mrp!),
      );

  void dispose() {
    for (final c in [color, size, sku, stock, price, mrp]) {
      c.dispose();
    }
  }

  /// Parse what was typed. Blank optional prices become null ("use the product's").
  SellerVariant toVariant() => SellerVariant(
        id: id,
        color: color.text.trim(),
        size: size.text.trim(),
        sku: sku.text.trim(),
        stock: int.tryParse(stock.text.trim()) ?? 0,
        price: parseMoney(price.text),
        mrp: parseMoney(mrp.text),
      );

  /// 2499.0 → "2499", 2499.5 → "2499.5".
  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// "1,299.50" → 1299.5; blank or junk → null.
double? parseMoney(String text) {
  final cleaned = text.trim().replaceAll(',', '');
  return cleaned.isEmpty ? null : double.tryParse(cleaned);
}

/// One variant's fields. [errors] holds this row's messages, keyed by field
/// ('sku', 'stock', 'price', 'mrp').
class VariantCard extends StatelessWidget {
  final int index;
  final VariantRow row;
  final Map<String, String> errors;
  final bool enabled;

  /// Null when this is the only variant: a product needs at least one.
  final VoidCallback? onRemove;

  const VariantCard({
    super.key,
    required this.index,
    required this.row,
    required this.errors,
    required this.enabled,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return BxCard(
      padding: const EdgeInsets.all(DsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Variant ${index + 1}',
                    style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.black, color: c.ink)),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove variant ${index + 1}',
                  icon: Icon(Icons.delete_outline, color: c.danger),
                  onPressed: enabled ? onRemove : null,
                ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: BxField(label: 'Colour', hint: 'e.g. Gold', controller: row.color, enabled: enabled)),
              const SizedBox(width: DsSpace.s3),
              Expanded(child: BxField(label: 'Size', hint: 'e.g. M', controller: row.size, enabled: enabled)),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BxField(
                  label: 'Stock',
                  controller: row.stock,
                  keyboardType: TextInputType.number,
                  error: errors['stock'],
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: BxField(
                  label: 'SKU (optional)',
                  controller: row.sku,
                  error: errors['sku'],
                  enabled: enabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BxField(
                  label: 'Price (optional)',
                  hint: 'Product price',
                  controller: row.price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  error: errors['price'],
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: BxField(
                  label: 'MRP (optional)',
                  hint: 'Product MRP',
                  controller: row.mrp,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  error: errors['mrp'],
                  enabled: enabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s1),
          Text(
            'Leave price and MRP blank to use the product\'s.',
            style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
          ),
        ],
      ),
    );
  }
}
