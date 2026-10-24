import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';

/// A bold heading with an optional line of explanation beneath it.
class SellerSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SellerSectionTitle(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: DsText.lg, fontWeight: DsWeight.black, color: c.ink)),
          if (subtitle != null) ...[
            const SizedBox(height: DsSpace.s1),
            Text(subtitle!, style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
          ],
        ],
      ),
    );
  }
}

/// A failed load with a way to try again.
class SellerLoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const SellerLoadError({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DsSpace.s4),
      child: Column(
        children: [
          BxAlert(message, title: 'Something went wrong', tone: BxTone.danger),
          const SizedBox(height: DsSpace.s3),
          BxButton(label: 'Try again', onPressed: onRetry, size: BxButtonSize.sm),
        ],
      ),
    );
  }
}

/// Placeholder rows while a list loads.
class SellerListSkeleton extends StatelessWidget {
  final int rows;

  const SellerListSkeleton({super.key, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          const BxSkeleton(height: 84, radius: DsRadius.cardAll),
          const SizedBox(height: DsSpace.s3),
        ],
      ],
    );
  }
}

/// A label and value on one line, for detail cards.
class SellerKeyValue extends StatelessWidget {
  final String label;
  final String value;

  const SellerKeyValue(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpace.s1 + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(fontSize: DsText.sm, fontWeight: DsWeight.bold, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Product thumbnail with a neutral fallback, since images are optional.
class SellerThumb extends StatelessWidget {
  final String? url;
  final double size;

  const SellerThumb({super.key, this.url, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: DsRadius.controlAll),
      child: Icon(Icons.image_outlined, color: c.inkSubtle, size: size * 0.4),
    );

    if (url == null) return fallback;

    return ClipRRect(
      borderRadius: DsRadius.controlAll,
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
