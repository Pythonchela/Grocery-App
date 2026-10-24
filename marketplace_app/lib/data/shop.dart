import 'api_client.dart';

/// A shop a shopper can browse: a vendor, or the owner's own shop.
class Shop {
  final String id;
  final String name;
  final String slug;
  final String? logoUrl;
  final String? bannerUrl;
  final String? tagline;
  final String? about;

  /// Whether it takes orders right now, and if not, why and until when
  /// ("Opens tomorrow at 9:00 AM").
  final bool isOpen;
  final String? closedText;

  /// The smallest basket it will deliver, in rupees; 0 for none.
  final double minOrder;

  /// Usual minutes to get an order ready, when the shop says.
  final int? prepMinutes;
  final double rating;
  final int reviewsCount;
  final int productCount;

  /// What it mostly sells, for the line under its name.
  final List<String> categories;

  /// {mon: {open: '09:00', close: '21:00'}, tue: null, ...}; empty means always open.
  final Map<String, Map<String, String>?> openingHours;
  final List<String> servicePincodes;
  final String? supportPhone;

  const Shop({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl,
    this.bannerUrl,
    this.tagline,
    this.about,
    this.isOpen = true,
    this.closedText,
    this.minOrder = 0,
    this.prepMinutes,
    this.rating = 0,
    this.reviewsCount = 0,
    this.productCount = 0,
    this.categories = const [],
    this.openingHours = const {},
    this.servicePincodes = const [],
    this.supportPhone,
  });

  static String? _s(Object? v) {
    final s = v == null ? '' : '$v'.trim();
    return s.isEmpty ? null : s;
  }

  factory Shop.fromJson(Map<String, dynamic> j) {
    final hours = <String, Map<String, String>?>{};
    final raw = j['opening_hours'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final slot = e.value;
        hours['${e.key}'] = slot is Map && _s(slot['open']) != null && _s(slot['close']) != null
            ? {'open': '${slot['open']}', 'close': '${slot['close']}'}
            : null;
      }
    }

    return Shop(
      id: '${j['id']}',
      name: '${j['name'] ?? j['display_name'] ?? ''}',
      slug: '${j['slug'] ?? ''}',
      logoUrl: _s(j['logo_url']),
      bannerUrl: _s(j['banner_url']),
      tagline: _s(j['tagline']),
      about: _s(j['about']),
      isOpen: j['is_open'] != false,
      closedText: _s(j['closed_text']),
      minOrder: j['min_order_amount'] is num ? (j['min_order_amount'] as num).toDouble() : 0,
      prepMinutes: j['prep_minutes'] is num ? (j['prep_minutes'] as num).toInt() : null,
      rating: j['rating'] is num ? (j['rating'] as num).toDouble() : 0,
      reviewsCount: j['reviews_count'] is num ? (j['reviews_count'] as num).toInt() : 0,
      productCount: j['product_count'] is num ? (j['product_count'] as num).toInt() : 0,
      categories: ((j['categories'] as List?) ?? const []).map((c) => '$c').toList(),
      openingHours: hours,
      servicePincodes: ((j['service_pincodes'] as List?) ?? const []).map((p) => '$p').toList(),
      supportPhone: _s(j['support_phone']),
    );
  }

  /// "Groceries · Dairy · Snacks", or the tagline when the shop wrote one.
  String get subtitle => tagline ?? categories.join(' · ');

  /// The week as lines to show: "Monday   9:00 AM – 9:00 PM" / "Closed".
  /// Empty when the shop is always open.
  List<(String day, String hours)> get hoursLines {
    if (openingHours.isEmpty) return const [];
    const names = {
      'mon': 'Monday',
      'tue': 'Tuesday',
      'wed': 'Wednesday',
      'thu': 'Thursday',
      'fri': 'Friday',
      'sat': 'Saturday',
      'sun': 'Sunday',
    };

    return [
      for (final e in names.entries)
        (
          e.value,
          openingHours[e.key] == null
              ? 'Closed'
              : '${_clock(openingHours[e.key]!['open']!)} – ${_clock(openingHours[e.key]!['close']!)}',
        ),
    ];
  }

  /// "21:00" -> "9:00 PM".
  static String _clock(String hhmm) {
    final h = int.tryParse(hhmm.substring(0, 2)) ?? 0;
    final m = hhmm.length >= 5 ? hhmm.substring(3, 5) : '00';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m ${h < 12 ? 'AM' : 'PM'}';
  }

  /// "20 mins · Min ₹149" for the card, whichever parts the shop has.
  String metaLine(String Function(num) money) => [
        if (prepMinutes != null && prepMinutes! > 0) '$prepMinutes mins',
        if (minOrder > 0) 'Min ${money(minOrder)}',
      ].join(' · ');
}

/// A category some shops sell in, offered as a filter on the shops list.
/// Whatever the shops sell: groceries, clothing, medicines, food.
class ShopCategory {
  final String slug;
  final String name;
  final int shops;

  const ShopCategory(this.slug, this.name, this.shops);
}

/// A page of shops with the category filters that go with it.
class ShopListing {
  final List<Shop> shops;
  final List<ShopCategory> categories;

  const ShopListing(this.shops, this.categories);
}

/// Reads shops from the API.
abstract final class ShopApi {
  /// Open shops first, then best rated. [pincode] limits to shops that deliver there.
  static Future<List<Shop>> list({String? search, String? pincode, String? category, bool openOnly = false}) async =>
      (await browse(search: search, pincode: pincode, category: category, openOnly: openOnly)).shops;

  /// The same, with the category filters shoppers can pick from.
  static Future<ShopListing> browse({String? search, String? pincode, String? category, bool openOnly = false}) async {
    final query = <String, String>{
      'per_page': '50',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
      if (category != null && category.isNotEmpty) 'category': category,
      if (openOnly) 'open': '1',
    };
    final body = await ApiClient.request('/shops', query: query, envelope: true) as Map<String, dynamic>;

    final shops = ((body['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(Shop.fromJson).toList();
    final facets = (body['facets'] is Map ? (body['facets'] as Map)['categories'] : null) as List?;

    return ShopListing(shops, [
      for (final c in (facets ?? const []).whereType<Map>())
        ShopCategory('${c['slug']}', '${c['name']}', c['shops'] is num ? (c['shops'] as num).toInt() : 0),
    ]);
  }

  static Future<Shop> one(String idOrSlug) async {
    final data = await ApiClient.request('/shops/$idOrSlug');
    return Shop.fromJson(data as Map<String, dynamic>);
  }
}
