import 'package:flutter/material.dart';

import 'brand.g.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// The store's mark: the logo the admin uploaded in the web panel, or the
/// two-letter initials mark that ships with the app.
///
/// The picture is a network image, so it can be missing, slow or unreachable;
/// whatever goes wrong, the initials mark is drawn instead and the header is
/// never left with a hole or a broken-image icon.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.logoUrl, this.size = 34});

  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    if (url == null || url.isEmpty) return _initials(context);

    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        key: const Key('brand-logo'),
        fit: BoxFit.contain,
        // A slow link shows the initials until the picture arrives, which also
        // keeps the header from jumping.
        frameBuilder: (context, child, frame, sync) =>
            frame == null && !sync ? _initials(context) : child,
        errorBuilder: (context, _, __) => _initials(context),
      ),
    );
  }

  Widget _initials(BuildContext context) {
    final c = context.ds;
    return Container(
      key: const Key('brand-initials'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.inverse, borderRadius: DsRadius.controlAll),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: DsBrand.logoInitials[0], style: TextStyle(color: c.inkInverse)),
            TextSpan(text: DsBrand.logoInitials[1], style: TextStyle(color: c.accent)),
          ],
        ),
        style: const TextStyle(
          fontFamily: DsFont.display,
          fontSize: DsText.sm,
          fontWeight: DsWeight.black,
        ),
      ),
    );
  }
}
