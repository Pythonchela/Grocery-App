import 'package:flutter/material.dart';

import '../screens/product_detail_screen.dart';

/// Opens a product's page. One place, so widgets that cannot import the screen
/// directly (it imports them) still can.
void openProduct(BuildContext context, String productId) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: productId)),
  );
}
