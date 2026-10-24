// Data shapes for the seller area.
//
// Deliberately self-contained: nothing here is imported from the shopper app's
// models, so this folder can move into its own app untouched.

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<dynamic> _list(Object? v) => v is List ? v : const [];
String _s(Object? v) => v?.toString() ?? '';
String? _sn(Object? v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

// ── Onboarding ───────────────────────────────────────────────────────────────

/// The merchant account's standing. Only ACTIVE may sell.
enum SellerStanding { pending, active, suspended }

SellerStanding _standing(String s) => switch (s) {
      'ACTIVE' => SellerStanding.active,
      'SUSPENDED' => SellerStanding.suspended,
      _ => SellerStanding.pending,
    };

/// Where the identity-and-bank-details application is.
enum KycStatus { draft, submitted, approved, rejected }

KycStatus _kycStatus(String s) => switch (s) {
      'SUBMITTED' => KycStatus.submitted,
      'APPROVED' => KycStatus.approved,
      'REJECTED' => KycStatus.rejected,
      _ => KycStatus.draft,
    };

class SellerAccount {
  final String id;
  final String displayName;
  final String slug;
  final SellerStanding standing;
  final String? supportEmail;
  final String? supportPhone;
  final double commissionRate;

  const SellerAccount({
    required this.id,
    required this.displayName,
    required this.slug,
    required this.standing,
    this.supportEmail,
    this.supportPhone,
    this.commissionRate = 0,
  });

  factory SellerAccount.fromJson(Map<String, dynamic> j) => SellerAccount(
        id: _s(j['id']),
        displayName: _s(j['display_name']),
        slug: _s(j['slug']),
        standing: _standing(_s(j['status'])),
        supportEmail: _sn(j['support_email']),
        supportPhone: _sn(j['support_phone']),
        commissionRate: _d(j['commission_rate']),
      );
}

/// The applicant's details as the API returns them: PAN, GSTIN and the account
/// number arrive masked (`XXXXXX234F`), never in full. They are for recognising
/// what was entered, not for editing — see the form, which never pre-fills them.
class KycProfile {
  final String businessType;
  final String legalName;
  final String? panMasked;
  final String? gstinMasked;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final String bankHolder;
  final String? bankAccountMasked;
  final String ifsc;
  final String bankName;
  final KycStatus status;
  final DateTime? submittedAt;
  final String? rejectionReason;

  const KycProfile({
    this.businessType = 'INDIVIDUAL',
    this.legalName = '',
    this.panMasked,
    this.gstinMasked,
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.bankHolder = '',
    this.bankAccountMasked,
    this.ifsc = '',
    this.bankName = '',
    this.status = KycStatus.draft,
    this.submittedAt,
    this.rejectionReason,
  });

  bool get hasGstin => gstinMasked != null;

  /// Company-type entities have to supply a certificate of incorporation.
  bool get isRegisteredEntity => const {'LLP', 'PRIVATE_LIMITED', 'PARTNERSHIP'}.contains(businessType);

  factory KycProfile.fromJson(Map<String, dynamic> j) => KycProfile(
        businessType: _s(j['business_type']).isEmpty ? 'INDIVIDUAL' : _s(j['business_type']),
        legalName: _s(j['legal_name']),
        panMasked: _sn(j['pan']),
        gstinMasked: _sn(j['gstin']),
        line1: _s(j['registered_line1']),
        line2: _s(j['registered_line2']),
        city: _s(j['registered_city']),
        state: _s(j['registered_state']),
        pincode: _s(j['registered_pincode']),
        bankHolder: _s(j['bank_account_holder']),
        bankAccountMasked: _sn(j['bank_account_number']),
        ifsc: _s(j['bank_ifsc']),
        bankName: _s(j['bank_name']),
        status: _kycStatus(_s(j['status'])),
        submittedAt: _dt(j['submitted_at']),
        rejectionReason: _sn(j['rejection_reason']),
      );
}

class KycDocument {
  final String id;
  final String kind;
  final String originalName;
  final int sizeBytes;

  const KycDocument({required this.id, required this.kind, required this.originalName, this.sizeBytes = 0});

  factory KycDocument.fromJson(Map<String, dynamic> j) => KycDocument(
        id: _s(j['id']),
        kind: _s(j['kind']),
        originalName: _s(j['original_name']),
        sizeBytes: _i(j['size_bytes']),
      );
}

/// What the server says is still missing. It is the authority — the app only
/// mirrors its rules to give earlier feedback.
class Checklist {
  final List<String> missingFields;
  final List<String> missingDocuments;
  final bool canSubmit;
  final bool editable;

  const Checklist({
    this.missingFields = const [],
    this.missingDocuments = const [],
    this.canSubmit = false,
    this.editable = true,
  });

  factory Checklist.fromJson(Map<String, dynamic> j) => Checklist(
        missingFields: _list(j['missing_fields']).map(_s).toList(),
        missingDocuments: _list(j['missing_documents']).map(_s).toList(),
        canSubmit: j['can_submit'] == true,
        editable: j['editable'] != false,
      );
}

/// The whole onboarding state in one object; the API sends it after every step.
class Onboarding {
  final SellerAccount account;
  final KycProfile kyc;
  final List<KycDocument> documents;
  final Checklist checklist;
  final List<String> businessTypes;
  final List<String> documentKinds;

  const Onboarding({
    required this.account,
    required this.kyc,
    required this.documents,
    required this.checklist,
    required this.businessTypes,
    required this.documentKinds,
  });

  factory Onboarding.fromJson(Map<String, dynamic> j) => Onboarding(
        account: SellerAccount.fromJson(_map(j['seller'])),
        kyc: KycProfile.fromJson(_map(j['kyc'])),
        documents: _list(j['documents']).map((d) => KycDocument.fromJson(_map(d))).toList(),
        checklist: Checklist.fromJson(_map(j['checklist'])),
        businessTypes: _list(j['business_types']).map(_s).toList(),
        documentKinds: _list(j['accepted_document_kinds']).map(_s).toList(),
      );

  KycDocument? documentOfKind(String kind) {
    for (final d in documents) {
      if (d.kind == kind) return d;
    }
    return null;
  }
}

// ── Dashboard ────────────────────────────────────────────────────────────────

class SellerProfile {
  final String id;
  final String displayName;
  final String? legalName;
  final String? supportEmail;
  final String? supportPhone;
  final double commissionRate;
  final SellerStanding standing;
  final double payoutBalance;
  final int productCount;

  /// Where this shop's goods are collected from. Delivery times and fees are
  /// worked out from here; without it the marketplace's own warehouse is used.
  final PickupAddress pickup;

  /// Its page for shoppers: picture, hours, minimum order, delivery area.
  final ShopProfile shop;

  const SellerProfile({
    required this.id,
    required this.displayName,
    this.legalName,
    this.supportEmail,
    this.supportPhone,
    this.commissionRate = 0,
    this.standing = SellerStanding.active,
    this.payoutBalance = 0,
    this.productCount = 0,
    this.pickup = const PickupAddress(),
    this.shop = const ShopProfile(),
  });

  factory SellerProfile.fromJson(Map<String, dynamic> j) => SellerProfile(
        id: _s(j['id']),
        displayName: _s(j['display_name']),
        legalName: _sn(j['legal_name']),
        supportEmail: _sn(j['support_email']),
        supportPhone: _sn(j['support_phone']),
        commissionRate: _d(j['commission_rate']),
        standing: _standing(_s(j['status'])),
        payoutBalance: _d(j['payout_balance']),
        productCount: _i(j['product_count']),
        pickup: PickupAddress.fromJson(j),
        shop: ShopProfile.fromJson(j),
      );
}

/// One day's opening: "09:00" to "21:00".
class HoursSlot {
  final String open;
  final String close;

  const HoursSlot(this.open, this.close);

  @override
  bool operator ==(Object other) => other is HoursSlot && other.open == open && other.close == close;

  @override
  int get hashCode => Object.hash(open, close);
}

/// How the shop shows to shoppers browsing shops, and when it takes orders:
/// its picture and words, its opening hours, the smallest basket it will
/// deliver and the PIN codes it covers.
class ShopProfile {
  static const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  final String? logoUrl;
  final String? bannerUrl;
  final String tagline;
  final String about;

  /// A slot for each weekday, null meaning closed that day; null altogether
  /// meaning the shop is always open.
  final Map<String, HoursSlot?>? openingHours;

  /// The shop's own pause switch, on top of its hours.
  final bool acceptingOrders;
  final double minOrderAmount;
  final List<String> servicePincodes;
  final int? prepMinutes;

  /// What the server worked out for this moment.
  final bool isOpen;
  final String? closedText;

  /// false: every new order waits for the shop to accept it.
  final bool autoAccept;

  /// A timed pause ("back at 6pm"); null when there is none.
  final DateTime? pausedUntil;

  const ShopProfile({
    this.logoUrl,
    this.bannerUrl,
    this.tagline = '',
    this.about = '',
    this.openingHours,
    this.acceptingOrders = true,
    this.minOrderAmount = 0,
    this.servicePincodes = const [],
    this.prepMinutes,
    this.isOpen = true,
    this.closedText,
    this.autoAccept = true,
    this.pausedUntil,
  });

  factory ShopProfile.fromJson(Map<String, dynamic> j) {
    Map<String, HoursSlot?>? hours;
    final raw = j['opening_hours'];
    if (raw is Map && raw.isNotEmpty) {
      hours = {
        for (final day in days)
          day: raw[day] is Map && _sn(raw[day]['open']) != null && _sn(raw[day]['close']) != null
              ? HoursSlot(_s(raw[day]['open']), _s(raw[day]['close']))
              : null,
      };
    }

    return ShopProfile(
      logoUrl: _sn(j['logo_url']),
      bannerUrl: _sn(j['banner_url']),
      tagline: _s(j['tagline']),
      about: _s(j['about']),
      openingHours: hours,
      acceptingOrders: j['accepting_orders'] != false,
      minOrderAmount: _d(j['min_order_amount']),
      servicePincodes: _list(j['service_pincodes']).map((p) => _s(p)).where((p) => p.isNotEmpty).toList(),
      prepMinutes: j['prep_minutes'] == null ? null : _i(j['prep_minutes']),
      isOpen: j['is_open'] != false,
      closedText: _sn(j['closed_text']),
      autoAccept: j['auto_accept'] != false,
      pausedUntil: _dt(j['paused_until']),
    );
  }

  /// The same shop with its pause switch moved: the one-tap "Taking orders".
  ShopProfile withAccepting(bool accepting) => ShopProfile(
        logoUrl: logoUrl,
        bannerUrl: bannerUrl,
        tagline: tagline,
        about: about,
        openingHours: openingHours,
        acceptingOrders: accepting,
        minOrderAmount: minOrderAmount,
        servicePincodes: servicePincodes,
        prepMinutes: prepMinutes,
        isOpen: isOpen,
        closedText: closedText,
        autoAccept: autoAccept,
        pausedUntil: pausedUntil,
      );

  /// What is sent to save it. Empty fields go as null so the server clears them.
  Map<String, dynamic> toJson() => {
        'logo_url': logoUrl,
        'banner_url': bannerUrl,
        'tagline': tagline.trim().isEmpty ? null : tagline.trim(),
        'about': about.trim().isEmpty ? null : about.trim(),
        // An empty list tells the server "no hours: always open".
        'opening_hours': openingHours == null
            ? []
            : {
                for (final e in openingHours!.entries)
                  e.key: e.value == null ? null : {'open': e.value!.open, 'close': e.value!.close},
              },
        'accepting_orders': acceptingOrders,
        'min_order_amount': minOrderAmount,
        'service_pincodes': servicePincodes,
        'prep_minutes': prepMinutes,
      };
}

/// A shop's pickup address, as the API stores it (`pickup_*`).
class PickupAddress {
  final String? name;
  final String? phone;
  final String? line1;
  final String? city;
  final String? state;
  final String? pincode;

  const PickupAddress({this.name, this.phone, this.line1, this.city, this.state, this.pincode});

  factory PickupAddress.fromJson(Map<String, dynamic> j) => PickupAddress(
        name: _sn(j['pickup_name']),
        phone: _sn(j['pickup_phone']),
        line1: _sn(j['pickup_line1']),
        city: _sn(j['pickup_city']),
        state: _sn(j['pickup_state']),
        pincode: _sn(j['pickup_pincode']),
      );

  /// A street and a valid PIN - the same test the API applies before using it.
  bool get isSet =>
      (line1 ?? '').isNotEmpty && RegExp(r'^[1-9][0-9]{5}$').hasMatch(pincode ?? '');

  /// "12 Koramangala, Bengaluru, Karnataka 560034".
  String get oneLine {
    final place = [city, state].where((s) => (s ?? '').isNotEmpty).join(', ');
    return [line1, place.isEmpty ? null : '$place ${pincode ?? ''}'.trim()]
        .where((s) => (s ?? '').isNotEmpty)
        .join(', ');
  }
}

/// One line the seller sold. A seller never sees the rest of a shared basket.
class SellerOrderItem {
  final String id;
  final String title;
  final String? image;
  final String variantLabel;
  final int quantity;
  final double price;
  final double earning;
  final double commission;
  final String orderNumber;
  final String orderStatus;
  final String paymentStatus;
  final String shipToName;
  final String shipToCity;
  final String shipToPincode;
  final DateTime? createdAt;

  /// This line's own progress: PENDING → PACKED → SHIPPED. Separate from
  /// [orderStatus], because a basket can hold several sellers' goods and each
  /// ships its own parcel.
  final String fulfilmentStatus;
  final String? courier;
  final String? trackingNo;
  final DateTime? shippedAt;

  /// The shop's answer to the order: PENDING (waiting for it), ACCEPTED or REJECTED.
  final String sellerResponse;

  /// When an unanswered order is cancelled by itself, and when the shop said it would be ready.
  final DateTime? acceptBy;
  final DateTime? readyBy;
  final String paymentMethod;
  final String? rejectionReason;
  final String? rejectedBy;

  const SellerOrderItem({
    required this.id,
    required this.title,
    this.image,
    this.variantLabel = '',
    this.quantity = 1,
    this.price = 0,
    this.earning = 0,
    this.commission = 0,
    this.orderNumber = '',
    this.orderStatus = '',
    this.paymentStatus = '',
    this.shipToName = '',
    this.shipToCity = '',
    this.shipToPincode = '',
    this.createdAt,
    this.fulfilmentStatus = 'PENDING',
    this.courier,
    this.trackingNo,
    this.shippedAt,
    this.sellerResponse = 'ACCEPTED',
    this.acceptBy,
    this.readyBy,
    this.paymentMethod = '',
    this.rejectionReason,
    this.rejectedBy,
  });

  /// The order is still with the sellers to pack and ship.
  bool get orderIsOpen => orderStatus == 'CONFIRMED' || orderStatus == 'PACKED';

  /// Waiting for this shop to accept or decline it.
  bool get awaitingAnswer => sellerResponse == 'PENDING' && orderIsOpen;
  bool get isCod => paymentMethod == 'COD';

  bool get canPack => fulfilmentStatus == 'PENDING' && sellerResponse == 'ACCEPTED' && orderIsOpen;
  bool get canShip =>
      fulfilmentStatus != 'SHIPPED' && fulfilmentStatus != 'CANCELLED' && sellerResponse == 'ACCEPTED' && orderIsOpen;

  /// Turned down or cancelled by the shop, before it was shipped.
  bool get canCancel =>
      sellerResponse == 'ACCEPTED' && fulfilmentStatus != 'SHIPPED' && fulfilmentStatus != 'CANCELLED' && orderIsOpen;

  /// Behind the time the shop promised.
  bool get isLate => canPack && readyBy != null && readyBy!.isBefore(DateTime.now());

  /// Tracking can be corrected until the order is handed on for delivery.
  bool get canEditTracking =>
      fulfilmentStatus == 'SHIPPED' && (orderIsOpen || orderStatus == 'SHIPPED');

  factory SellerOrderItem.fromJson(Map<String, dynamic> j) {
    final product = _map(j['product']);
    final variant = _map(j['variant']);
    final order = _map(j['order']);
    final address = _map(order['shipping_address']);

    return SellerOrderItem(
      id: _s(j['id']),
      title: _s(product['title']),
      image: _firstImage(product['images']),
      variantLabel: [_s(variant['color']), _s(variant['size'])].where((e) => e.isNotEmpty).join(' · '),
      quantity: _i(j['quantity']),
      price: _d(j['price']),
      earning: _d(j['seller_earning']),
      commission: _d(j['commission_amount']),
      orderNumber: _s(order['order_number']),
      orderStatus: _s(order['status']),
      paymentStatus: _s(order['payment_status']),
      shipToName: _s(address['name']),
      shipToCity: _s(address['city']),
      shipToPincode: _s(address['pincode']),
      createdAt: _dt(j['created_at']),
      fulfilmentStatus: _s(j['fulfilment_status']).isEmpty ? 'PENDING' : _s(j['fulfilment_status']),
      courier: _sn(j['courier']),
      trackingNo: _sn(j['tracking_no']),
      shippedAt: _dt(j['shipped_at']),
      sellerResponse: _s(j['seller_response']).isEmpty ? 'ACCEPTED' : _s(j['seller_response']),
      acceptBy: _dt(j['accept_by']),
      readyBy: _dt(j['ready_by']),
      paymentMethod: _s(order['payment_method']),
      rejectionReason: _sn(j['rejection_reason']),
      rejectedBy: _sn(j['rejected_by']),
    );
  }
}

/// What the order desk needs to know at a glance, polled while the app is open.
class DeskCounts {
  final int newOrders;
  final int lateToPack;
  final int toPack;
  final double? acceptanceRate;

  const DeskCounts({this.newOrders = 0, this.lateToPack = 0, this.toPack = 0, this.acceptanceRate});

  factory DeskCounts.fromJson(Map<String, dynamic> j) => DeskCounts(
        newOrders: _i(j['new_orders']),
        lateToPack: _i(j['late_to_pack']),
        toPack: _i(j['to_pack']),
        acceptanceRate: j['acceptance_rate_30d'] == null ? null : _d(j['acceptance_rate_30d']),
      );
}

class SellerVariant {
  /// Null for a variant that has not been saved yet.
  final String? id;
  final String color;
  final String size;
  final String sku;
  final int stock;

  /// Optional per-variant prices; blank means "use the product's".
  final double? price;
  final double? mrp;

  const SellerVariant({
    this.id,
    this.color = '',
    this.size = '',
    this.sku = '',
    this.stock = 0,
    this.price,
    this.mrp,
  });

  factory SellerVariant.fromJson(Map<String, dynamic> j) => SellerVariant(
        id: _sn(j['id']),
        color: _s(j['color']),
        size: _s(j['size']),
        sku: _s(j['sku']),
        stock: _i(j['stock']),
        price: j['price'] == null ? null : _d(j['price']),
        mrp: j['mrp'] == null ? null : _d(j['mrp']),
      );

  String get label => [color, size].where((e) => e.isNotEmpty).join(' · ');
}

/// One row of a product's specification table, as a seller edits it.
class SellerSpecRow {
  final String label;
  final String value;

  const SellerSpecRow(this.label, this.value);
}

/// A titled run of specification rows ("General": Brand, Fabric, Fit...).
class SellerSpecGroup {
  final String title;
  final List<SellerSpecRow> rows;

  const SellerSpecGroup(this.title, this.rows);

  static List<SellerSpecGroup> parseList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final g in raw)
        if (g is Map)
          SellerSpecGroup(_s(g['title']), [
            for (final r in (g['rows'] is List ? g['rows'] as List : const []))
              if (r is Map) SellerSpecRow(_s(r['label']), _s(r['value'])),
          ]),
    ];
  }
}

/// The manufacturer panel's fields: the API's key, and what the form calls it.
const sellerManufacturerFields = <String, String>{
  'generic_name': 'Generic name',
  'country_of_origin': 'Country of origin',
  'manufacturer_name': 'Name of the manufacturer',
  'manufacturer_address': 'Address of the manufacturer',
  'packer_name': 'Name of the packer',
  'packer_address': 'Address of the packer',
};

class SellerProduct {
  final String id;
  final String title;
  final String? image;
  final double price;
  final String status;
  final int stock;
  final String category;

  // Everything below is what the edit form needs. The seller's own product list
  // returns full records, so editing needs no second request.
  final String description;
  final String brand;
  final double mrp;
  final String categoryId;
  final List<String> images;
  final List<SellerVariant> variants;

  /// The "all details" content, as the edit form needs it. The manufacturer panel
  /// is keyed by the API's field names ("generic_name", ...), empty strings kept.
  final List<SellerSpecGroup> specifications;
  final Map<String, String> manufacturer;

  /// What it weighs (grams) and how big it is packed (cm): what couriers price on.
  final int? weightGrams;
  final int? lengthCm;
  final int? widthCm;
  final int? heightCm;

  /// True when the description was written with formatting (on the web admin).
  /// This app edits plain text only; saving a changed description replaces the
  /// formatted version, so the form says so.
  final bool hasFormattedDescription;

  /// How it is delivered: '' (the category decides), 'instant', 'parcel' or 'heavy'.
  final String deliveryProfile;

  /// Minutes to get it ready; null means the category's.
  final int? prepMinutes;
  final bool codAvailable;

  /// The short "highlights" lines shoppers see under the price.
  final List<String> features;

  const SellerProduct({
    required this.id,
    required this.title,
    this.image,
    this.price = 0,
    this.status = '',
    this.stock = 0,
    this.category = '',
    this.description = '',
    this.brand = '',
    this.mrp = 0,
    this.categoryId = '',
    this.images = const [],
    this.variants = const [],
    this.specifications = const [],
    this.manufacturer = const {},
    this.weightGrams,
    this.lengthCm,
    this.widthCm,
    this.heightCm,
    this.hasFormattedDescription = false,
    this.deliveryProfile = '',
    this.prepMinutes,
    this.codAvailable = true,
    this.features = const [],
  });

  factory SellerProduct.fromJson(Map<String, dynamic> j) {
    final variants = _list(j['variants']).map((v) => SellerVariant.fromJson(_map(v))).toList();

    return SellerProduct(
      id: _s(j['id']),
      title: _s(j['title']),
      image: _firstImage(j['images']),
      price: _d(j['price']),
      status: _s(j['status']),
      stock: variants.fold<int>(0, (sum, v) => sum + v.stock),
      category: _s(_map(j['category'])['name']),
      description: _s(j['description']),
      brand: _s(j['brand']),
      mrp: _d(j['mrp']),
      categoryId: _s(j['category_id']),
      images: _list(j['images']).map((i) => i is Map ? _s(i['url']) : _s(i)).where((u) => u.isNotEmpty).toList(),
      variants: variants,
      specifications: SellerSpecGroup.parseList(j['specifications']),
      manufacturer: {
        for (final key in sellerManufacturerFields.keys) key: _s(_map(j['manufacturer'])[key]),
      },
      weightGrams: j['weight_grams'] == null ? null : _i(j['weight_grams']),
      lengthCm: j['length_cm'] == null ? null : _i(j['length_cm']),
      widthCm: j['width_cm'] == null ? null : _i(j['width_cm']),
      heightCm: j['height_cm'] == null ? null : _i(j['height_cm']),
      hasFormattedDescription: _s(j['description_html']).trim().isNotEmpty,
      deliveryProfile: _s(j['delivery_profile']),
      prepMinutes: j['prep_minutes'] == null ? null : _i(j['prep_minutes']),
      codAvailable: j['cod_available'] != false,
      features: _list(j['features']).map((f) => _s(f)).where((f) => f.isNotEmpty).toList(),
    );
  }
}

class ProductCategory {
  final String id;
  final String name;

  const ProductCategory({required this.id, required this.name});

  factory ProductCategory.fromJson(Map<String, dynamic> j) => ProductCategory(id: _s(j['id']), name: _s(j['name']));
}

/// What the product form sends. Prices are numbers; a blank optional field is
/// left out rather than sent as an empty string.
class ProductInput {
  final String title;
  final String description;
  final String brand;
  final String categoryId;
  final double mrp;
  final double price;
  final String status;
  final List<String> images;
  final List<SellerVariant> variants;

  /// [{title, rows: [{label, value}]}] and {generic_name: ..., ...}. The server
  /// drops anything half-filled, so these can be sent as typed.
  final List<Map<String, dynamic>> specifications;
  final Map<String, String> manufacturer;

  /// Packed weight (grams) and size (cm), when the seller gave them.
  final int? weightGrams;
  final int? lengthCm;
  final int? widthCm;
  final int? heightCm;

  /// '' means "let the category decide".
  final String deliveryProfile;
  final int? prepMinutes;
  final bool codAvailable;
  final List<String> features;

  const ProductInput({
    required this.title,
    required this.description,
    required this.brand,
    required this.categoryId,
    required this.mrp,
    required this.price,
    required this.status,
    required this.images,
    required this.variants,
    this.specifications = const [],
    this.manufacturer = const {},
    this.weightGrams,
    this.lengthCm,
    this.widthCm,
    this.heightCm,
    this.deliveryProfile = '',
    this.prepMinutes,
    this.codAvailable = true,
    this.features = const [],
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'brand': brand,
        'category_id': categoryId,
        'mrp': mrp,
        'price': price,
        'status': status,
        'images': images,
        'specifications': specifications,
        'manufacturer': manufacturer,
        // Empty clears them, so a seller can take a wrong figure back out.
        'weight_grams': weightGrams,
        'length_cm': lengthCm,
        'width_cm': widthCm,
        'height_cm': heightCm,
        'delivery_profile': deliveryProfile.isEmpty ? null : deliveryProfile,
        'prep_minutes': prepMinutes,
        'cod_available': codAvailable,
        'features': features,
        'variants': [
          for (final v in variants)
            {
              if (v.id != null) 'id': v.id,
              'color': v.color,
              'size': v.size,
              'sku': v.sku.isEmpty ? null : v.sku,
              'stock': v.stock,
              if (v.price != null) 'price': v.price,
              if (v.mrp != null) 'mrp': v.mrp,
            },
        ],
      };
}

/// A bank account as the API shows it: never the full number.
class BankSummary {
  final String holder;
  final String bank;
  final String ifsc;
  final String last4;
  final DateTime? requestedAt;

  const BankSummary({this.holder = '', this.bank = '', this.ifsc = '', this.last4 = '', this.requestedAt});

  factory BankSummary.fromJson(Map<String, dynamic> j) => BankSummary(
        holder: _s(j['holder']),
        bank: _s(j['bank']),
        ifsc: _s(j['ifsc']),
        last4: _s(j['account_last4']),
        requestedAt: _dt(j['requested_at']),
      );

  String get line => [holder, '$bank $ifsc'.trim(), if (last4.isNotEmpty) '••••$last4'].where((e) => e.isNotEmpty).join(' · ');
}

/// One request to be paid.
class PayoutRequestRow {
  final String id;
  final double amount;
  final String status; // REQUESTED, PAID, REJECTED, CANCELLED
  final String reference;
  final String decisionNote;
  final DateTime? at;

  const PayoutRequestRow({
    required this.id,
    this.amount = 0,
    this.status = 'REQUESTED',
    this.reference = '',
    this.decisionNote = '',
    this.at,
  });

  factory PayoutRequestRow.fromJson(Map<String, dynamic> j) => PayoutRequestRow(
        id: _s(j['id']),
        amount: _d(j['amount']),
        status: _s(j['status']),
        reference: _s(j['reference']),
        decisionNote: _s(j['decision_note']),
        at: _dt(j['requested_at'] ?? j['created_at']),
      );

  String get statusLabel => switch (status) {
        'REQUESTED' => 'Waiting for the team',
        'PAID' => 'Paid',
        'REJECTED' => 'Declined',
        'CANCELLED' => 'Cancelled',
        _ => status,
      };
}

/// Getting paid: what can be asked for, the bank account, and requests so far.
class SellerMoney {
  final double balance;
  final double pending;
  final double withdrawable;
  final double minimumPayout;

  /// Why a request cannot be made right now; null when it can.
  final String? blocker;
  final BankSummary? bank;
  final BankSummary? pendingBank;
  final List<PayoutRequestRow> requests;

  const SellerMoney({
    this.balance = 0,
    this.pending = 0,
    this.withdrawable = 0,
    this.minimumPayout = 0,
    this.blocker,
    this.bank,
    this.pendingBank,
    this.requests = const [],
  });

  PayoutRequestRow? get open {
    for (final r in requests) {
      if (r.status == 'REQUESTED') return r;
    }
    return null;
  }

  factory SellerMoney.fromJson(Map<String, dynamic> j) => SellerMoney(
        balance: _d(j['balance']),
        pending: _d(j['pending']),
        withdrawable: _d(j['withdrawable']),
        minimumPayout: _d(j['minimum_payout']),
        blocker: _sn(j['blocker']),
        bank: j['bank'] is Map ? BankSummary.fromJson(_map(j['bank'])) : null,
        pendingBank: j['pending_bank'] is Map ? BankSummary.fromJson(_map(j['pending_bank'])) : null,
        requests: _list(j['requests']).map((e) => PayoutRequestRow.fromJson(_map(e))).toList(),
      );
}

/// A month in money, as the API sums it from the ledger.
class SellerStatement {
  final String month;
  final double opening;
  final double closing;
  final int orders;
  final double grossSales;
  final double refunds;
  final double commission;
  final double gst;
  final double tcs;
  final double tds;
  final double earnings;
  final double adjustments;
  final double payouts;

  const SellerStatement({
    required this.month,
    this.opening = 0,
    this.closing = 0,
    this.orders = 0,
    this.grossSales = 0,
    this.refunds = 0,
    this.commission = 0,
    this.gst = 0,
    this.tcs = 0,
    this.tds = 0,
    this.earnings = 0,
    this.adjustments = 0,
    this.payouts = 0,
  });

  factory SellerStatement.fromJson(Map<String, dynamic> j) => SellerStatement(
        month: _s(j['month']),
        opening: _d(j['opening_balance']),
        closing: _d(j['closing_balance']),
        orders: _i(j['orders']),
        grossSales: _d(j['gross_sales']),
        refunds: _d(j['refunds']),
        commission: _d(j['commission']),
        gst: _d(j['gst_on_commission']),
        tcs: _d(j['tcs']),
        tds: _d(j['tds']),
        earnings: _d(j['earnings']),
        adjustments: _d(j['adjustments']),
        payouts: _d(j['payouts']),
      );
}

class LedgerEntry {
  final String id;
  final String type; // SALE, REFUND, ADJUSTMENT
  final double gross;
  final double commission;
  final double net;
  final double balanceAfter;
  final String note;
  final DateTime? createdAt;

  const LedgerEntry({
    required this.id,
    required this.type,
    this.gross = 0,
    this.commission = 0,
    this.net = 0,
    this.balanceAfter = 0,
    this.note = '',
    this.createdAt,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: _s(j['id']),
        type: _s(j['type']),
        gross: _d(j['gross']),
        commission: _d(j['commission']),
        net: _d(j['net']),
        balanceAfter: _d(j['balance_after']),
        note: _s(j['note']),
        createdAt: _dt(j['created_at']),
      );
}

/// One page of a paginated list, with the API's paging metadata.
class ListPage<T> {
  final List<T> items;
  final int page;
  final int lastPage;
  final int total;

  /// Extra top-level values the endpoint returned (a ledger's `balance`).
  final Map<String, dynamic> extra;

  const ListPage({required this.items, this.page = 1, this.lastPage = 1, this.total = 0, this.extra = const {}});

  bool get hasMore => page < lastPage;

  factory ListPage.fromEnvelope(Map<String, dynamic> body, T Function(Map<String, dynamic>) parse) {
    final meta = _map(body['meta']);
    return ListPage(
      items: _list(body['data']).map((e) => parse(_map(e))).toList(),
      page: _i(meta['current_page']) == 0 ? 1 : _i(meta['current_page']),
      lastPage: _i(meta['last_page']) == 0 ? 1 : _i(meta['last_page']),
      total: _i(meta['total']),
      extra: body,
    );
  }
}

/// Product images are stored as a list of URLs, or of `{url: …}` objects.
String? _firstImage(Object? images) {
  final list = _list(images);
  if (list.isEmpty) return null;
  final first = list.first;
  if (first is String) return first.isEmpty ? null : first;
  if (first is Map) return _sn(first['url']);
  return null;
}
