import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';

/// Asks before a basket from one shop is swapped for another's.
///
/// Stores that keep a basket to one shop (food and grocery style) cannot hold
/// two shops' goods, because each shop delivers on its own terms. When the
/// shopper adds from a different shop, this asks "Start a new basket?" and, on
/// yes, empties the old one. Resolves to true when the item may now be added:
/// there was no clash, or the shopper agreed to clear the basket.
///
/// By default the old basket is emptied on yes. A caller that still has a step
/// to go before the item is really added (the customise sheet) passes
/// `clear: false` and empties it only when the item goes in, so backing out of
/// that step keeps the shopper's basket.
Future<bool> confirmShopSwitch(BuildContext context, Product product, {bool clear = true}) async {
  final state = AppState.instance;
  final inBasket = state.shopConflictFor(product);
  if (inBasket == null) return true;

  final startNew = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Start a new basket?'),
      content: Text(
        'Your basket has items from $inBasket. Adding this item from '
        '${product.soldBy ?? 'another shop'} will clear it, because each shop '
        'delivers separately.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep my basket'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Start new basket'),
        ),
      ],
    ),
  );

  if (startNew != true) return false;
  if (clear) state.clearCart();
  return true;
}
