import 'package:flutter/material.dart';
import '../design/tokens.g.dart';
import 'product_card.dart';

SliverGridDelegate productGridDelegate(BuildContext context) {
  final available = MediaQuery.sizeOf(context).width - DsSpace.s4 * 2;
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final columns = (available / (scale > 1.5 ? 240 : 170)).floor().clamp(2, 4);
  final count = scale > 1.5 && available < 480 ? 1 : columns;
  final width = (available - (count - 1) * DsSpace.s3) / count;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    mainAxisSpacing: DsSpace.s3,
    crossAxisSpacing: DsSpace.s3,
    mainAxisExtent: width + ProductCardTile.extraHeight(context),
  );
}
