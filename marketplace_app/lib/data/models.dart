import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';
import 'product_options.dart';

import '../design/brand.g.dart';

/// Shape normalisers for the Laravel payloads.
///
/// The web client does this in `mapProduct` / `mapOrder` / `mapCategory`; these
/// mirror those field-for-field so a rename on the API surfaces in both clients
/// at the same place.

double _num(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
int _int(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
String _str(dynamic v) => v?.toString() ?? '';

const _fallbackImage =
    'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=800&q=80';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: DsBrand.currencySymbol, decimalDigits: 0);

String formatMoney(num value) => _inr.format(value);

String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  return DateFormat('d MMM yyyy', 'en_IN').format(parsed.toLocal());
}

class Category {
  final String id;
  final String name;
  final String slug;
  final String? iconUrl;

  /// A picture for lists and grids; [iconUrl] (an icon name) is the fallback.
  final String? imageUrl;

  /// Category-specific filter groups the admin defined (e.g. Fabric, Brand).
  final Map<String, dynamic>? filterConfig;
  final int productCount;

  Category({
    required this.id,
    required this.name,
    required this.slug,
    this.iconUrl,
    this.imageUrl,
    this.filterConfig,
    this.productCount = 0,
  });

  Category withImage(String? url) => Category(
        id: id,
        name: name,
        slug: slug,
        iconUrl: iconUrl,
        imageUrl: url,
        filterConfig: filterConfig,
        productCount: productCount,
      );

  /// Gives every category without its own picture a photo of something in it.
  ///
  /// The API does this too (`cover_image_url`), but the app does not wait for
  /// it: whatever products it has already loaded are enough, so the category
  /// buttons show pictures on any server version.
  static List<Category> withCoverPhotos(
      List<Category> categories, Iterable<Product> products) {
    return [
      for (final c in categories)
        if (c.imageUrl != null)
          c
        else
          c.withImage(products
                  .where((p) => p.hasPhoto && p.categoryName == c.name)
                  .map((p) => p.image)
                  .firstOrNull ??
              // A photo found on an earlier screen (the home page) is still good
              // on a page that has only loaded one category's products.
              _coverCache[c.slug]),
    ].map((c) {
      if (c.imageUrl != null) _coverCache[c.slug] = c.imageUrl!;
      return c;
    }).toList();
  }

  static final Map<String, String> _coverCache = {};

  factory Category.fromJson(Map<String, dynamic> j) {
    String? clean(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final config = j['filter_config'];
    return Category(
      id: _str(j['id']),
      name: _str(j['name']),
      slug: _str(j['slug']),
      iconUrl: j['icon_url'] as String?,
      // The admin's own picture, else the photo of something in the category.
      imageUrl: clean(j['image_url']) ?? clean(j['cover_image_url']),
      filterConfig: config is Map<String, dynamic> ? config : null,
      productCount: _int(j['products_count']),
    );
  }
}

class Variant {
  final String id;
  final String color;
  final String size;
  final double? price;
  final int stock;

  /// A swatch colour for [color]; null falls back to a name lookup ("Navy").
  final Color? colorHex;

  /// This colour's own pictures. Empty means the product's gallery is used.
  final List<String> images;

  Variant({
    required this.id,
    required this.color,
    required this.size,
    this.price,
    required this.stock,
    this.colorHex,
    this.images = const [],
  });

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(
        id: _str(j['id']),
        color: _str(j['color']),
        size: _str(j['size']),
        price: j['price'] == null ? null : _num(j['price']),
        stock: _int(j['stock']),
        colorHex: parseHexColor(j['color_hex']),
        images: ((j['images'] as List?) ?? []).map(_str).where((s) => s.isNotEmpty).toList(),
      );

  /// The swatch to draw for this variant's colour, if there is one.
  Color? get swatch => colorHex ?? (color.isEmpty ? null : swatchForName(color));

  String get label => [color, size].where((s) => s.isNotEmpty).join(' · ');
}

/// One row of a product's specification table.
class SpecRow {
  final String label;
  final String value;

  const SpecRow(this.label, this.value);
}

/// A titled run of specification rows ("General": Brand, Fabric, Fit...).
class SpecGroup {
  final String title;
  final List<SpecRow> rows;

  const SpecGroup(this.title, this.rows);

  static List<SpecGroup> parseList(Object? raw) {
    if (raw is! List) return const [];
    final groups = <SpecGroup>[];
    for (final g in raw) {
      if (g is! Map) continue;
      final rows = <SpecRow>[];
      for (final r in (g['rows'] as List? ?? const [])) {
        if (r is! Map) continue;
        final label = _str(r['label']).trim();
        final value = _str(r['value']).trim();
        if (label.isNotEmpty && value.isNotEmpty) rows.add(SpecRow(label, value));
      }
      if (rows.isNotEmpty) {
        final title = _str(g['title']).trim();
        groups.add(SpecGroup(title.isEmpty ? 'General' : title, rows));
      }
    }
    return groups;
  }
}

/// The manufacturer panel's fields, in the order they are shown.
const manufacturerLabels = <String, String>{
  'generic_name': 'Generic name',
  'country_of_origin': 'Country of origin',
  'manufacturer_name': 'Name of the manufacturer',
  'manufacturer_address': 'Address of the manufacturer',
  'packer_name': 'Name of the packer',
  'packer_address': 'Address of the packer',
};

class Product {
  final String id;
  final String title;
  final String brand;
  final String description;

  /// The description with its formatting (cleaned HTML), or null when it was
  /// written as plain text. [description] always holds the plain version.
  final String? descriptionHtml;

  /// The specification table, and the manufacturer panel as label -> value.
  final List<SpecGroup> specifications;
  final Map<String, String> manufacturer;

  /// The shop selling it, for "Sold by" and for keeping a basket to one shop.
  final String? soldBy;
  final String? shopId;
  final String? shopSlug;
  final double price;
  final double mrp;
  final int discount;
  final String image;
  final List<String> images;
  final double rating;
  final int reviewsCount;
  final bool isNew;
  final bool inStock;
  final List<String> badges;
  final List<String> features;
  final List<Variant> variants;
  final String? categoryName;
  final bool codAvailable;

  /// 'veg', 'non_veg' or 'egg' for food; null for everything the mark does not apply to.
  final String? diet;

  /// Custom selection options (portion, add-ons, ...) - this product's own, or
  /// its category's template. Empty for an ordinary product.
  final List<OptionGroup> optionGroups;

  /// How it is delivered - 'instant' (a rider, within hours), 'parcel' (a
  /// courier, days), 'heavy' (a truck) - or null when nothing is set. And the
  /// minutes it takes to get ready first.
  final String? deliveryProfile;
  final int prepMinutes;

  Product({
    required this.id,
    required this.title,
    required this.brand,
    required this.description,
    this.descriptionHtml,
    this.specifications = const [],
    this.manufacturer = const {},
    this.soldBy,
    this.shopId,
    this.shopSlug,
    required this.price,
    required this.mrp,
    required this.discount,
    required this.image,
    required this.images,
    required this.rating,
    required this.reviewsCount,
    required this.isNew,
    required this.inStock,
    required this.badges,
    required this.features,
    required this.variants,
    this.categoryName,
    this.codAvailable = true,
    this.diet,
    this.optionGroups = const [],
    this.deliveryProfile,
    this.prepMinutes = 0,
  });

  /// Whether this product has a real photo, not the stand-in image.
  bool get hasPhoto => image != _fallbackImage;

  factory Product.fromJson(Map<String, dynamic> j) {
    final images = ((j['images'] as List?) ?? []).map(_str).where((s) => s.isNotEmpty).toList();
    final price = _num(j['price']);
    final mrp = _num(j['mrp']);
    final category = j['category'];

    return Product(
      id: _str(j['id']),
      title: _str(j['title']),
      brand: _str(j['brand']),
      description: _str(j['description']),
      descriptionHtml: _str(j['description_html']).trim().isEmpty ? null : _str(j['description_html']),
      specifications: SpecGroup.parseList(j['specifications']),
      manufacturer: j['manufacturer'] is Map
          ? {
              for (final e in manufacturerLabels.entries)
                if (_str((j['manufacturer'] as Map)[e.key]).trim().isNotEmpty)
                  e.value: _str((j['manufacturer'] as Map)[e.key]).trim(),
            }
          : const {},
      soldBy: j['seller'] is Map && _str((j['seller'] as Map)['display_name']).isNotEmpty
          ? _str((j['seller'] as Map)['display_name'])
          : null,
      // The seller object when the API sent one, else the plain column.
      shopId: j['seller'] is Map && _str((j['seller'] as Map)['id']).isNotEmpty
          ? _str((j['seller'] as Map)['id'])
          : (_str(j['seller_id']).isEmpty ? null : _str(j['seller_id'])),
      shopSlug: j['seller'] is Map && _str((j['seller'] as Map)['slug']).isNotEmpty
          ? _str((j['seller'] as Map)['slug'])
          : null,
      price: price,
      mrp: mrp,
      discount: j['discount'] != null
          ? _int(j['discount'])
          : (mrp > price && mrp > 0 ? (((mrp - price) / mrp) * 100).round() : 0),
      image: images.isNotEmpty ? images.first : _fallbackImage,
      images: images.isNotEmpty ? images : [_fallbackImage],
      rating: _num(j['rating']),
      reviewsCount: _int(j['reviews_count']),
      isNew: j['is_new'] == true,
      inStock: j['in_stock'] != false,
      badges: ((j['tags'] as List?) ?? []).map(_str).toList(),
      features: ((j['features'] as List?) ?? []).map(_str).toList(),
      variants: ((j['variants'] as List?) ?? [])
          .map((v) => Variant.fromJson(v as Map<String, dynamic>))
          .toList(),
      categoryName: category is Map ? _str(category['name']) : (category == null ? null : _str(category)),
      codAvailable: j['cod_available'] != false,
      diet: ['veg', 'non_veg', 'egg'].contains(j['diet']) ? j['diet'] as String : null,
      optionGroups: OptionGroup.parseList(j['option_groups']),
      deliveryProfile: j['delivery_info'] is Map
          ? (j['delivery_info'] as Map)['profile'] as String?
          : null,
      prepMinutes: j['delivery_info'] is Map
          ? _int((j['delivery_info'] as Map)['prep_minutes'])
          : 0,
    );
  }
}

/// The API's real status vocabulary — same list the web client keys off.
const orderStages = ['PENDING', 'CONFIRMED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED'];

const stageLabels = {
  'PENDING': 'Pending',
  'CONFIRMED': 'Confirmed',
  'PACKED': 'Packed',
  'SHIPPED': 'Shipped',
  'OUT_FOR_DELIVERY': 'Out for delivery',
  'DELIVERED': 'Delivered',
  'CANCELLED': 'Cancelled',
};

class OrderItem {
  /// The order-item id, not the product id — returns are raised against a
  /// specific line on a specific order, and confusing the two silently returns
  /// the wrong purchase.
  final String id;
  final String productId;

  /// Which variant (size, colour...) was bought, so "buy again" re-orders the
  /// same one.
  final String? variantId;
  final String title;
  final int quantity;
  final double price;
  final String? image;

  /// What was chosen on the product page, as printed lines
  /// ("Portion: Full plate", "Leave out: Onion").
  final List<OptionPick> picks;

  /// The same choices in the form the cart sends, so "Buy again" can repeat them.
  final OptionSelection selection;

  OrderItem({
    required this.id,
    required this.productId,
    this.variantId,
    required this.title,
    required this.quantity,
    required this.price,
    this.image,
    this.picks = const [],
    this.selection = OptionSelection.empty,
    this.cancelledByShop = false,
  });

  /// The shop could not fulfil this line; it was refunded and is not coming.
  final bool cancelledByShop;

  factory OrderItem.fromJson(Map<String, dynamic> j) {
    final product = j['product'];
    final images = product is Map ? ((product['images'] as List?) ?? []) : const [];
    return OrderItem(
      id: _str(j['id']),
      productId: _str(j['product_id']),
      variantId: j['variant_id']?.toString(),
      title: product is Map ? _str(product['title']) : 'Product',
      quantity: _int(j['quantity']),
      price: _num(j['price']),
      image: images.isNotEmpty ? _str(images.first) : null,
      picks: _picksOf(j['selected_options']),
      selection: _selectionOf(j['selected_options']),
      cancelledByShop: j['seller_response'] == 'REJECTED',
    );
  }

  /// The order stores a summary of each group the shopper touched:
  /// {key, label, type, remove, choices: [{id,label,price}] | value, unit}.
  static List<OptionPick> _picksOf(Object? raw) {
    if (raw is! List) return const [];
    final picks = <OptionPick>[];
    for (final g in raw.whereType<Map>()) {
      final label = '${g['label'] ?? ''}';
      if (g['type'] == 'stepper') {
        final unit = '${g['unit'] ?? ''}';
        final v = g['value'];
        if (v is num) {
          picks.add(OptionPick(
              label, '${formatOptionNumber(v.toDouble())}${unit.isEmpty ? '' : ' $unit'}'));
        }
        continue;
      }
      final names = [
        for (final c in (g['choices'] as List? ?? []).whereType<Map>()) '${c['label']}'
      ];
      if (names.isNotEmpty) {
        picks.add(OptionPick(label, names.join(', '), removal: g['remove'] == true));
      }
    }
    return picks;
  }

  static OptionSelection _selectionOf(Object? raw) {
    if (raw is! List) return OptionSelection.empty;
    final choices = <String, List<String>>{};
    final numbers = <String, double>{};
    for (final g in raw.whereType<Map>()) {
      final key = '${g['key']}';
      if (g['type'] == 'stepper') {
        if (g['value'] is num) numbers[key] = (g['value'] as num).toDouble();
      } else {
        choices[key] = [
          for (final c in (g['choices'] as List? ?? []).whereType<Map>()) '${c['id']}'
        ];
      }
    }
    return OptionSelection(choices: choices, numbers: numbers);
  }
}

class Order {
  final String id;
  final String orderNumber;
  final String status;
  final double totalAmount;
  final String paymentMethod;
  final String createdAt;
  final List<OrderItem> items;
  final String? courier;
  final String? trackingNo;

  Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.totalAmount,
    required this.paymentMethod,
    required this.createdAt,
    required this.items,
    this.courier,
    this.trackingNo,
  });

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: _str(j['id']),
        orderNumber: _str(j['order_number']),
        status: _str(j['status']),
        totalAmount: _num(j['total_amount']),
        paymentMethod: _str(j['payment_method']),
        createdAt: _str(j['created_at']),
        items: ((j['items'] as List?) ?? [])
            .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        courier: j['courier'] as String?,
        trackingNo: j['tracking_no'] as String?,
      );

  String get statusLabel => stageLabels[status] ?? status;
}

class Address {
  final String id;
  final String? tag;
  final String name;
  final String phone;
  final String line1;
  final String? line2;
  final String city;
  final String state;
  final String pincode;
  final bool isDefault;

  Address({
    required this.id,
    this.tag,
    required this.name,
    required this.phone,
    required this.line1,
    this.line2,
    required this.city,
    required this.state,
    required this.pincode,
    this.isDefault = false,
  });

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: _str(j['id']),
        tag: j['tag'] as String?,
        name: _str(j['name']),
        phone: _str(j['phone']),
        line1: _str(j['line1']),
        line2: j['line2'] as String?,
        city: _str(j['city']),
        state: _str(j['state']),
        pincode: _str(j['pincode']),
        isDefault: j['is_default'] == true,
      );

  Map<String, dynamic> toPayload() => {
        'tag': tag,
        'name': name,
        'phone': phone,
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'is_default': isDefault,
      };

  /// What checkout sends as `shipping_address`.
  Map<String, dynamic> toShippingAddress() => {
        'name': name,
        'phone': phone,
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
      };

  String get oneLine =>
      [line1, if (line2 != null && line2!.isNotEmpty) line2, city, state, pincode].join(', ');
}

/// One bookable delivery option from `POST /delivery/quote`.
///
/// The carrier is deliberately along for the ride rather than the headline: a
/// customer is choosing a speed and a price. Which partner fulfils it is the
/// allocator's business, and it can change between quote and dispatch.
class DeliveryOption {
  final String carrier;
  final String carrierLabel;
  final String serviceLevel;
  final String label;
  final String description;
  final double price;
  final String etaLabel;
  final int etaMinutes;
  final bool codSupported;
  final String? freeReason;
  final bool sandbox;

  DeliveryOption({
    required this.carrier,
    required this.carrierLabel,
    required this.serviceLevel,
    required this.label,
    required this.description,
    required this.price,
    required this.etaLabel,
    required this.etaMinutes,
    required this.codSupported,
    this.freeReason,
    this.sandbox = false,
  });

  factory DeliveryOption.fromJson(Map<String, dynamic> j) => DeliveryOption(
        carrier: _str(j['carrier']),
        carrierLabel: _str(j['carrier_label']),
        serviceLevel: _str(j['service_level']),
        label: _str(j['label']),
        description: _str(j['description']),
        price: _num(j['price']),
        etaLabel: _str(j['eta_label']),
        etaMinutes: _int(j['eta_minutes']),
        codSupported: j['cod_supported'] == true,
        freeReason: j['free_reason'] as String?,
        sandbox: j['sandbox'] == true,
      );

  bool get isFree => price == 0;
}

/// Live tracking for a dispatched order.
/// One step in a shipment's history, in our words whichever courier reported it.
class ShipmentEvent {
  final String status;
  final String label;
  final String? description;
  final String location;
  final String at;

  const ShipmentEvent({
    required this.status,
    required this.label,
    this.description,
    this.location = '',
    this.at = '',
  });

  factory ShipmentEvent.fromJson(Map<String, dynamic> j) => ShipmentEvent(
        status: _str(j['status']),
        label: _str(j['label']),
        description: j['description'] as String?,
        location: _str(j['location']),
        at: _str(j['at']),
      );
}

class TrackingInfo {
  final String? trackingNo;
  final String currentStatus;
  final String? courier;
  final String? serviceLabel;
  final int? etaMinutes;
  final double? lat;
  final double? lng;
  final String? riderName;
  final String? riderPhone;
  final List<({String status, String location, String at})> scans;
  final String? message;
  final bool sandbox;

  /// ISO time the order was promised by at checkout.
  final String? promisedBy;

  /// 'live_map' (a rider is bringing it within hours) or 'status_updates'
  /// (a parcel in the courier network: show where it is and when it is due).
  final String mode;

  /// Our normalised status (IN_TRANSIT, OUT_FOR_DELIVERY, DELAYED...) and its label.
  final String? shipmentStatus;
  final String? statusLabel;
  final List<ShipmentEvent> events;
  final String? expectedBy;
  final String? trackUrl;
  final String? carrierLabel;

  TrackingInfo({
    this.trackingNo,
    required this.currentStatus,
    this.courier,
    this.serviceLabel,
    this.etaMinutes,
    this.lat,
    this.lng,
    this.riderName,
    this.riderPhone,
    this.scans = const [],
    this.message,
    this.sandbox = false,
    this.promisedBy,
    this.mode = 'live_map',
    this.shipmentStatus,
    this.statusLabel,
    this.events = const [],
    this.expectedBy,
    this.trackUrl,
    this.carrierLabel,
  });

  factory TrackingInfo.fromJson(Map<String, dynamic> j) {
    final position = j['position'] as Map<String, dynamic>?;
    final rider = j['rider'] as Map<String, dynamic>?;

    return TrackingInfo(
      trackingNo: j['tracking_no'] as String?,
      currentStatus: _str(j['current_status']),
      courier: j['courier'] as String?,
      serviceLabel: j['service_label'] as String?,
      etaMinutes: j['eta_minutes'] == null ? null : _int(j['eta_minutes']),
      lat: position?['lat'] == null ? null : _num(position!['lat']),
      lng: position?['lng'] == null ? null : _num(position!['lng']),
      riderName: rider?['name'] as String?,
      riderPhone: rider?['phone'] as String?,
      scans: ((j['scans'] as List?) ?? [])
          .map((s) => (
                status: _str(s['status']),
                location: _str(s['location']),
                at: _str(s['at']),
              ))
          .toList(),
      message: j['message'] as String?,
      sandbox: j['sandbox'] == true,
      promisedBy: j['promised_by'] as String?,
      mode: j['mode'] == 'status_updates' ? 'status_updates' : 'live_map',
      shipmentStatus: j['status'] as String?,
      statusLabel: j['status_label'] as String?,
      events: ((j['events'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ShipmentEvent.fromJson)
          .toList(),
      expectedBy: j['expected_by'] as String?,
      trackUrl: j['track_url'] as String?,
      carrierLabel: j['carrier_label'] as String?,
    );
  }

  bool get showsMap => mode == 'live_map';
  bool get isDispatched => trackingNo != null;
  bool get hasLivePosition => lat != null && lng != null;
}

class CartLine {
  final Product product;
  final Variant? variant;
  int quantity;

  /// Portion, add-ons, a weight... as picked on the product page.
  final OptionSelection selection;

  CartLine({
    required this.product,
    this.variant,
    this.quantity = 1,
    this.selection = OptionSelection.empty,
  });

  /// The price of one, options included. Display only - the server prices the order.
  double get unitPrice => ProductOptionMath.unitPrice(
      variant?.price ?? product.price, product.optionGroups, selection);

  /// What a plain variant of this product costs, for strike-through comparisons.
  double get listPrice => variant?.price ?? product.price;

  /// The struck-through "was" price for one: the product's MRP, carried up with
  /// a dearer option the way the server does, never below what is charged.
  double get unitMrp {
    final base = listPrice;
    final mrp = product.mrp;
    if (unitPrice == base || base <= 0) return mrp > unitPrice ? mrp : unitPrice;
    final scaled = mrp * unitPrice / base;
    return scaled > unitPrice ? scaled : unitPrice;
  }

  double get lineTotal => unitPrice * quantity;

  /// Same product and variant with different picks are different lines.
  String get key => selection.isEmpty
      ? '${product.id}:${variant?.id ?? ''}'
      : '${product.id}:${variant?.id ?? ''}:${selection.signature}';

  List<OptionPick> get picks =>
      ProductOptionMath.summary(product.optionGroups, selection);

  /// What the API takes for one cart line.
  Map<String, dynamic> toRequest() => {
        'product_id': product.id,
        'variant_id': variant?.id,
        'quantity': quantity,
        if (!selection.isEmpty) 'options': selection.toJson(),
      };
}

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final double walletBalance;
  final int loyaltyPoints;

  AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.role = 'CUSTOMER',
    this.phone,
    this.walletBalance = 0,
    this.loyaltyPoints = 0,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: _str(j['id']),
        name: _str(j['name']),
        email: _str(j['email']),
        role: _str(j['role']).isEmpty ? 'CUSTOMER' : _str(j['role']),
        phone: j['phone'] as String?,
        walletBalance: _num(j['wallet_balance']),
        loyaltyPoints: _int(j['loyalty_points']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'phone': phone,
        'wallet_balance': walletBalance,
        'loyalty_points': loyaltyPoints,
      };
}
