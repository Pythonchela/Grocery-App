import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/product_options.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import 'option_picker.dart';

/// Opens the "customise" sheet for a product that needs a choice first (a size,
/// a portion, add-ons) so the shopper adds it without leaving the list they
/// were browsing. Resolves to true when something was added.
///
/// [initialVariant] and [initialSelection] let "+" on an item already in the
/// cart start from what was added last, so repeating it is one tap.
Future<bool> showCustomiseSheet(
  BuildContext context,
  Product product, {
  Variant? initialVariant,
  OptionSelection? initialSelection,
}) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => CustomiseSheet(
      product: product,
      initialVariant: initialVariant,
      initialSelection: initialSelection,
    ),
  );
  return added ?? false;
}

class CustomiseSheet extends StatefulWidget {
  final Product product;
  final Variant? initialVariant;
  final OptionSelection? initialSelection;

  const CustomiseSheet({
    super.key,
    required this.product,
    this.initialVariant,
    this.initialSelection,
  });

  @override
  State<CustomiseSheet> createState() => _CustomiseSheetState();
}

class _CustomiseSheetState extends State<CustomiseSheet> {
  late Variant? _variant;
  late OptionSelection _selection;
  String? _message;

  Product get _p => widget.product;

  @override
  void initState() {
    super.initState();
    _variant = widget.initialVariant ??
        _p.variants.where((v) => v.stock > 0).firstOrNull ??
        _p.variants.firstOrNull;
    _selection =
        widget.initialSelection ?? OptionSelection.defaults(_p.optionGroups);
  }

  void _add() {
    final problem = ProductOptionMath.problem(_p.optionGroups, _selection);
    if (problem != null) {
      setState(() => _message = problem);
      return;
    }

    final state = AppState.instance;
    final ok = state.addToCart(_p, variant: _variant, selection: _selection);
    if (!ok) {
      setState(() => _message = 'Maximum available quantity reached');
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final basePrice = _variant?.price ?? _p.price;
    final price =
        ProductOptionMath.unitPrice(basePrice, _p.optionGroups, _selection);
    final inStock = _variant == null ? _p.inStock : _variant!.stock > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, 0, DsSpace.s4, DsSpace.s2),
            child: Text(_p.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: DsText.lg,
                    fontWeight: DsWeight.bold,
                    color: c.ink)),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_p.variants.length > 1)
                    VariantPicker(
                      variants: _p.variants,
                      selected: _variant,
                      onChanged: (v) => setState(() {
                        _variant = v;
                        _message = null;
                      }),
                    ),
                  if (_p.optionGroups.isNotEmpty)
                    OptionPicker(
                      groups: _p.optionGroups,
                      selection: _selection,
                      onChanged: (next) => setState(() {
                        _selection = next;
                        _message = null;
                      }),
                    ),
                  const SizedBox(height: DsSpace.s4),
                ],
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.s4, 0, DsSpace.s4, DsSpace.s2),
              child: Text(_message!,
                  style: TextStyle(fontSize: DsText.sm, color: c.danger)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s2, DsSpace.s4, DsSpace.s4),
            child: BxButton(
              label: inStock ? 'Add item · ${formatMoney(price)}' : 'Out of stock',
              size: BxButtonSize.lg,
              fullWidth: true,
              onPressed: inStock ? _add : null,
            ),
          ),
        ],
      ),
    );
  }
}
