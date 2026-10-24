/// The home-page layout an admin builds in the web panel's Storefront Builder
/// (`GET /storefront/sections`). The API returns only visible sections, already
/// in the order the admin chose.
enum HomeSectionType { hero, categoryGrid, productRow, banner, reels, trust }

class HomeSection {
  final String id;
  final HomeSectionType type;
  final String title;
  final String subtitle;

  /// `trending`, `new`, `personalized`, `deals` or `category` (PRODUCT_ROW only).
  final String source;
  final String? categoryId;
  final String? imageUrl;
  final String? linkUrl;

  const HomeSection({
    required this.id,
    required this.type,
    this.title = '',
    this.subtitle = '',
    this.source = 'trending',
    this.categoryId,
    this.imageUrl,
    this.linkUrl,
  });

  static HomeSectionType? _type(String? raw) => switch (raw) {
        'HERO' => HomeSectionType.hero,
        'CATEGORY_GRID' => HomeSectionType.categoryGrid,
        'PRODUCT_ROW' => HomeSectionType.productRow,
        'BANNER' => HomeSectionType.banner,
        'REELS' => HomeSectionType.reels,
        'TRUST' => HomeSectionType.trust,
        // A section type added to the web later is skipped here, not an error —
        // an older app keeps working against a newer admin panel.
        _ => null,
      };

  static HomeSection? tryParse(Map<String, dynamic> j) {
    final type = _type(j['type']?.toString());
    if (type == null) return null;

    String? clean(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return HomeSection(
      id: '${j['id']}',
      type: type,
      title: clean(j['title']) ?? '',
      subtitle: clean(j['subtitle']) ?? '',
      source: clean(j['source']) ?? 'trending',
      categoryId: clean(j['category_id']),
      imageUrl: clean(j['image_url']),
      linkUrl: clean(j['link_url']),
    );
  }

  static List<HomeSection> parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(HomeSection.tryParse)
        .whereType<HomeSection>()
        .toList();
  }
}

/// Where a section's `link_url` points, in terms the app can open.
sealed class HomeLink {
  const HomeLink();

  /// Understands the same paths the web storefront uses (`/category/<slug>`,
  /// `/product/<id>`, `/search?...`, `/reels`), with or without the site origin.
  static HomeLink? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;

    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    switch (parts.first) {
      case 'category' when parts.length > 1:
        return CategoryLink(parts[1]);
      case 'product' when parts.length > 1:
        return ProductLink(parts[1]);
      case 'search':
        return SearchLink(uri.queryParameters['q'] ??
            uri.queryParameters['search'] ??
            '');
      case 'reels':
        return const ReelsLink();
      default:
        return null;
    }
  }
}

class CategoryLink extends HomeLink {
  final String slug;
  const CategoryLink(this.slug);
}

class ProductLink extends HomeLink {
  final String id;
  const ProductLink(this.id);
}

class SearchLink extends HomeLink {
  final String query;
  const SearchLink(this.query);
}

class ReelsLink extends HomeLink {
  const ReelsLink();
}
