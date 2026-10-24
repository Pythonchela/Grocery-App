// Shared fakes and helpers for the seller screen tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/design/theme.dart';
import 'package:marketplace_app/seller/document_picker.dart';
import 'package:marketplace_app/seller/seller_api.dart';
import 'package:marketplace_app/seller/seller_area.dart';
import 'package:marketplace_app/seller/seller_host.dart';
import 'package:marketplace_app/seller/seller_models.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

/// Stands in for the API. Onboarding calls answer with the full new state, the
/// way the real ones do.
class FakeSellerApi implements SellerApi {
  @override
  Future<void> updateStock(Map<String, int> stockByVariantId) async {
    calls.add('stock:${stockByVariantId.length}');
  }
  Onboarding? state;
  Object? onboardingError;
  final calls = <String>[];
  Map<String, String>? lastKycSave;
  ApiException? saveKycError;
  Onboarding? afterSave;
  Onboarding? afterSubmit;
  Onboarding? afterUpload;

  SellerProfile profile = const SellerProfile(
    id: 's1', displayName: 'Asha Crafts', supportEmail: 'asha@example.com',
    commissionRate: 10, payoutBalance: 1234.5, productCount: 7,
  );
  List<SellerOrderItem> orderRows = [];
  List<SellerProduct> productRows = [];
  List<LedgerEntry> ledgerRows = [];
  double ledgerBalance = 0;
  double? ledgerPending;
  double? ledgerWithdrawable;

  FakeSellerApi([this.state]);

  @override
  Future<Onboarding?> onboarding() async {
    calls.add('onboarding');
    if (onboardingError != null) {
      final e = onboardingError!;
      onboardingError = null; // fails once, so a retry can succeed
      throw e;
    }
    return state;
  }

  @override
  Future<Onboarding> apply({required String displayName, String? supportEmail, String? supportPhone}) async {
    calls.add('apply:$displayName');
    return state = buildOnboarding(displayName: displayName);
  }

  PickupAddress? savedPickup;
  ApiException? pickupError;

  @override
  Future<void> updatePickup(PickupAddress address) async {
    calls.add('pickup');
    if (pickupError != null) throw pickupError!;
    savedPickup = address;
  }

  @override
  Future<Onboarding> saveKyc(Map<String, String> fields) async {
    calls.add('saveKyc');
    lastKycSave = fields;
    if (saveKycError != null) throw saveKycError!;
    return state = afterSave ?? state!;
  }

  @override
  Future<Onboarding> uploadDocument(String kind, PickedDocument file) async {
    calls.add('upload:$kind');
    return state = afterUpload ?? state!;
  }

  @override
  Future<Onboarding> deleteDocument(String id) async {
    calls.add('delete:$id');
    return state!;
  }

  @override
  Future<Onboarding> submit() async {
    calls.add('submit');
    return state = afterSubmit ?? state!;
  }

  @override
  Future<SellerProfile> me() async => profile;

  @override
  Future<void> updateProfile({String? displayName, String? supportEmail, String? supportPhone}) async {
    calls.add('updateProfile:$displayName');
  }

  /// Mirrors the server's stage rules, so the tabs behave as they would live.
  @override
  Future<ListPage<SellerOrderItem>> orderItems({String? status, String? stage, int page = 1}) async {
    bool open(SellerOrderItem o) => o.orderStatus == 'CONFIRMED' || o.orderStatus == 'PACKED';

    final rows = orderRows.where((o) {
      if (status != null && status.isNotEmpty && o.orderStatus != status) return false;
      return switch (stage) {
        'new' => o.awaitingAnswer,
        'to_pack' => o.fulfilmentStatus == 'PENDING' && o.sellerResponse == 'ACCEPTED' && open(o),
        'packed' => o.fulfilmentStatus == 'PACKED' && open(o),
        'shipped' => o.fulfilmentStatus == 'SHIPPED' && o.orderStatus != 'DELIVERED' && o.orderStatus != 'CANCELLED',
        'delivered' => o.orderStatus == 'DELIVERED',
        'cancelled' => o.orderStatus == 'CANCELLED' || o.fulfilmentStatus == 'CANCELLED',
        _ => true,
      };
    }).toList();
    return ListPage(items: rows, total: rows.length);
  }

  // ── Money ──
  SellerMoney moneyState = const SellerMoney(
    balance: 1500, withdrawable: 1500, minimumPayout: 100,
    bank: BankSummary(holder: 'Asha', bank: 'HDFC Bank', ifsc: 'HDFC0001234', last4: '9012'),
  );
  SellerStatement? statementState;

  @override
  Future<SellerMoney> money() async => moneyState;

  @override
  Future<void> requestPayout({double? amount}) async {
    calls.add('requestPayout:${amount ?? 'all'}');
    moneyState = SellerMoney(
      balance: moneyState.balance, withdrawable: moneyState.withdrawable, minimumPayout: moneyState.minimumPayout,
      bank: moneyState.bank,
      requests: [PayoutRequestRow(id: 'r1', amount: amount ?? moneyState.withdrawable)],
    );
  }

  @override
  Future<void> cancelPayout(String id) async {
    calls.add('cancelPayout:$id');
    moneyState = SellerMoney(
      balance: moneyState.balance, withdrawable: moneyState.withdrawable, minimumPayout: moneyState.minimumPayout, bank: moneyState.bank,
    );
  }

  @override
  Future<void> changeBank({required String holder, required String number, required String ifsc, String? bank}) async {
    calls.add('changeBank:$number');
    moneyState = SellerMoney(
      balance: moneyState.balance, withdrawable: moneyState.withdrawable, minimumPayout: moneyState.minimumPayout, bank: moneyState.bank,
      pendingBank: BankSummary(holder: holder, last4: number.substring(number.length - 4)),
    );
  }

  @override
  Future<void> withdrawBankChange() async {
    calls.add('withdrawBank');
  }

  @override
  Future<List<String>> statementMonths() async => ['2026-10', '2026-09'];

  @override
  Future<SellerStatement> statement(String month) async =>
      statementState ?? SellerStatement(month: month, orders: 3, grossSales: 3000, commission: 300, earnings: 2700, closing: 2700);

  // ── Order desk ──
  @override
  Future<DeskCounts> deskCounts() async {
    // Not logged in `calls`: it is polled in the background, and tests assert on the calls they caused.
    return DeskCounts(
      newOrders: orderRows.where((o) => o.awaitingAnswer).length,
      toPack: orderRows.where((o) => o.canPack).length,
    );
  }

  @override
  Future<SellerOrderItem> acceptItem(String id, {int? prepMinutes}) async {
    calls.add('accept:$id:${prepMinutes ?? ''}');
    if (fulfilmentError != null) throw fulfilmentError!;
    final o = _line(id);
    final updated = SellerOrderItem(
      id: o.id, title: o.title, quantity: o.quantity, price: o.price, earning: o.earning,
      orderNumber: o.orderNumber, orderStatus: o.orderStatus, paymentMethod: o.paymentMethod,
      fulfilmentStatus: o.fulfilmentStatus, sellerResponse: 'ACCEPTED',
      readyBy: prepMinutes == null ? null : DateTime.now().add(Duration(minutes: prepMinutes)),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<SellerOrderItem> rejectItem(String id, String reason, {String? note}) async {
    calls.add('reject:$id:$reason');
    if (fulfilmentError != null) throw fulfilmentError!;
    final o = _line(id);
    final updated = SellerOrderItem(
      id: o.id, title: o.title, quantity: o.quantity, price: o.price, earning: o.earning,
      orderNumber: o.orderNumber, orderStatus: 'CANCELLED', paymentMethod: o.paymentMethod,
      fulfilmentStatus: 'CANCELLED', sellerResponse: 'REJECTED', rejectionReason: reason, rejectedBy: 'SELLER',
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<void> setAvailability(String productId, {required bool available, DateTime? until}) async {
    calls.add('availability:$productId:$available');
  }

  @override
  Future<void> pauseShop(int minutes) async {
    calls.add('pause:$minutes');
  }

  @override
  Future<void> setAutoAccept(bool auto) async {
    calls.add('autoAccept:$auto');
  }

  /// Set to make the next pack/ship fail, as the server would.
  ApiException? fulfilmentError;

  void _replace(SellerOrderItem updated) {
    final i = orderRows.indexWhere((o) => o.id == updated.id);
    if (i >= 0) orderRows[i] = updated;
  }

  SellerOrderItem _line(String id) => orderRows.firstWhere((o) => o.id == id);

  static SellerOrderItem withFulfilment(SellerOrderItem o, {String? status, String? courier, String? tracking, String? orderStatus}) =>
      SellerOrderItem(
        id: o.id, title: o.title, image: o.image, variantLabel: o.variantLabel, quantity: o.quantity,
        price: o.price, earning: o.earning, commission: o.commission, orderNumber: o.orderNumber,
        orderStatus: orderStatus ?? o.orderStatus, paymentStatus: o.paymentStatus, shipToName: o.shipToName,
        shipToCity: o.shipToCity, shipToPincode: o.shipToPincode, createdAt: o.createdAt,
        fulfilmentStatus: status ?? o.fulfilmentStatus, courier: courier ?? o.courier,
        trackingNo: tracking ?? o.trackingNo, shippedAt: status == 'SHIPPED' ? DateTime(2026, 9, 30, 12) : o.shippedAt,
      );

  @override
  Future<SellerOrderItem> packItem(String id) async {
    calls.add('pack:$id');
    if (fulfilmentError != null) throw fulfilmentError!;
    final updated = withFulfilment(_line(id), status: 'PACKED');
    _replace(updated);
    return updated;
  }

  ShopProfile? lastShop;
  ApiException? shopError;

  @override
  Future<void> updateShop(ShopProfile shop) async {
    calls.add('updateShop');
    if (shopError != null) throw shopError!;
    lastShop = shop;
  }

  @override
  Future<SellerOrderItem> shipItem(String id, {String? courier, String? trackingNo}) async {
    calls.add('ship:$id:${courier ?? 'auto'}:${trackingNo ?? 'auto'}');
    if (fulfilmentError != null) throw fulfilmentError!;
    // With nothing typed the server books the courier and supplies both.
    final updated = withFulfilment(_line(id),
        status: 'SHIPPED', courier: courier ?? 'Delhivery Surface', tracking: trackingNo ?? 'AWB-AUTO-1');
    _replace(updated);
    return updated;
  }

  // ── Products ──────────────────────────────────────────────────────────────

  List<ProductCategory> categoryRows = const [
    ProductCategory(id: 'c1', name: 'Home Decor'),
    ProductCategory(id: 'c2', name: 'Apparel'),
  ];
  ProductInput? lastProductInput;
  String? lastProductId;
  ApiException? productError;
  ApiException? deleteError;
  ApiException? uploadError;
  int uploads = 0;

  @override
  Future<ListPage<SellerProduct>> products({String? status, String? search, int page = 1}) async {
    final rows = productRows.where((p) => (status == null || status.isEmpty || p.status == status) &&
        (search == null || search.isEmpty || p.title.toLowerCase().contains(search.toLowerCase()) ||
          p.variants.any((v) => v.sku.toLowerCase().contains(search.toLowerCase())))).toList();
    return ListPage(items: rows, total: rows.length);
  }

  /// Fails once, so a retry can succeed.
  Object? categoriesError;

  @override
  Future<List<ProductCategory>> categories() async {
    calls.add('categories');
    if (categoriesError != null) {
      final e = categoriesError!;
      categoriesError = null;
      throw e;
    }
    return categoryRows;
  }

  final List<Map<String, dynamic>> requestedCategories = [];

  @override
  Future<List<Map<String, dynamic>>> categoryRequests() async => requestedCategories;

  @override
  Future<void> requestCategory(String name, String reason) async {
    calls.add('requestCategory:$name');
    requestedCategories.add({'id': '$name-request', 'name': name, 'reason': reason, 'status': 'PENDING'});
  }

  @override
  Future<Map<String, dynamic>> previewImport(String raw) async {
    calls.add('previewImport');
    return {'rows': <Map<String, dynamic>>[], 'categories': <Map<String, dynamic>>[], 'total': 0};
  }

  @override
  Future<int> commitImport(List<Map<String, dynamic>> rows, String status) async {
    calls.add('commitImport:$status');
    return rows.length;
  }

  @override
  Future<String> uploadImage(PickedDocument file) async {
    calls.add('uploadImage:${file.name}');
    if (uploadError != null) throw uploadError!;
    return 'https://img.test/${++uploads}-${file.name}';
  }

  @override
  Future<SellerProduct> createProduct(ProductInput input) async {
    calls.add('createProduct');
    lastProductInput = input;
    if (productError != null) throw productError!;
    final created = _toProduct('new-${productRows.length + 1}', input);
    productRows = [created, ...productRows];
    return created;
  }

  @override
  Future<SellerProduct> updateProduct(String id, ProductInput input) async {
    calls.add('updateProduct:$id');
    lastProductInput = input;
    lastProductId = id;
    if (productError != null) throw productError!;
    final updated = _toProduct(id, input);
    productRows = [for (final p in productRows) p.id == id ? updated : p];
    return updated;
  }

  @override
  Future<void> setProductStatus(String id, String status) async {
    calls.add('setStatus:$id:$status');
    productRows = [
      for (final p in productRows)
        p.id == id
            ? SellerProduct(id: p.id, title: p.title, price: p.price, status: status, stock: p.stock, category: p.category)
            : p,
    ];
  }

  @override
  Future<void> deleteProduct(String id) async {
    calls.add('deleteProduct:$id');
    if (deleteError != null) throw deleteError!;
    productRows = productRows.where((p) => p.id != id).toList();
  }

  SellerProduct _toProduct(String id, ProductInput i) => SellerProduct(
        id: id, title: i.title, price: i.price, mrp: i.mrp, status: i.status, description: i.description,
        brand: i.brand, categoryId: i.categoryId, images: i.images, image: i.images.isEmpty ? null : i.images.first,
        // Like the server, give every variant an id, so a later save edits it in place.
        variants: [
          for (var n = 0; n < i.variants.length; n++)
            i.variants[n].id != null
                ? i.variants[n]
                : SellerVariant(
                    id: '$id-v${n + 1}', color: i.variants[n].color, size: i.variants[n].size, sku: i.variants[n].sku,
                    stock: i.variants[n].stock, price: i.variants[n].price, mrp: i.variants[n].mrp),
        ],
        stock: i.variants.fold<int>(0, (s, v) => s + v.stock),
        category: categoryRows.where((c) => c.id == i.categoryId).map((c) => c.name).firstOrNull ?? '',
        weightGrams: i.weightGrams, lengthCm: i.lengthCm, widthCm: i.widthCm, heightCm: i.heightCm,
        specifications: [for (final g in i.specifications) SellerSpecGroup((g['title'] ?? '') as String, [for (final r in (g['rows'] as List)) SellerSpecRow((r as Map)['label'] as String, r['value'] as String)])],
        manufacturer: i.manufacturer,
        deliveryProfile: i.deliveryProfile, prepMinutes: i.prepMinutes, codAvailable: i.codAvailable, features: i.features,
      );

  @override
  Future<ListPage<LedgerEntry>> ledger({int page = 1}) async =>
      ListPage(items: ledgerRows, total: ledgerRows.length, extra: {
        'balance': ledgerBalance,
        if (ledgerPending != null) 'pending': ledgerPending,
        if (ledgerWithdrawable != null) 'withdrawable': ledgerWithdrawable,
      });
}

class FakePicker implements DocumentPicker {
  PickedDocument? next;
  int picks = 0;
  List<String>? lastExtensions;

  FakePicker([this.next]);

  @override
  Future<PickedDocument?> pick({List<String> extensions = DocumentRules.allowedExtensions}) async {
    picks++;
    lastExtensions = extensions;
    return next;
  }
}

/// Builds the payload the real `/seller/onboarding` returns.
Onboarding buildOnboarding({
  String displayName = 'Asha Crafts',
  String seller = 'PENDING',
  String kyc = 'DRAFT',
  List<String> missingFields = const [],
  List<String> missingDocuments = const [],
  bool canSubmit = false,
  Map<String, dynamic> kycOverrides = const {},
  List<Map<String, dynamic>> documents = const [],
}) =>
    Onboarding.fromJson({
      'seller': {
        'id': 's1', 'display_name': displayName, 'slug': 'asha', 'status': seller,
        'support_email': null, 'support_phone': null, 'commission_rate': 10,
      },
      'kyc': {
        'business_type': 'INDIVIDUAL', 'legal_name': 'Asha Rao', 'pan': null, 'gstin': null,
        'registered_line1': '', 'registered_line2': '', 'registered_city': '', 'registered_state': '',
        'registered_pincode': '', 'bank_account_holder': '', 'bank_account_number': null,
        'bank_ifsc': '', 'bank_name': '', 'status': kyc, 'submitted_at': null, 'rejection_reason': null,
        ...kycOverrides,
      },
      'documents': documents,
      'checklist': {
        'missing_fields': missingFields, 'missing_documents': missingDocuments,
        'can_submit': canSubmit, 'editable': kyc == 'DRAFT' || kyc == 'REJECTED',
      },
      'accepted_document_kinds': ['PAN_CARD', 'GST_CERTIFICATE', 'CANCELLED_CHEQUE', 'ADDRESS_PROOF', 'INCORPORATION_CERT'],
      'business_types': ['INDIVIDUAL', 'PROPRIETORSHIP', 'PARTNERSHIP', 'LLP', 'PRIVATE_LIMITED'],
    });

/// Every KYC field the checklist can list as missing.
const allKycFields = [
  'business_type', 'legal_name', 'pan', 'registered_line1', 'registered_city', 'registered_state',
  'registered_pincode', 'bank_account_holder', 'bank_account_number', 'bank_ifsc',
];

/// A fully filled-in draft, ready to submit.
Onboarding readyToSubmit() => buildOnboarding(
      canSubmit: true,
      kycOverrides: {
        'pan': 'XXXXXX234F', 'registered_line1': '12 MG Road', 'registered_city': 'Bengaluru',
        'registered_state': 'Karnataka', 'registered_pincode': '560001', 'bank_account_holder': 'Asha Rao',
        'bank_account_number': 'XXXXXXXX6789', 'bank_ifsc': 'HDFC0001234',
      },
      documents: [
        {'id': 'd1', 'kind': 'PAN_CARD', 'original_name': 'pan.jpg', 'size_bytes': 2048},
        {'id': 'd2', 'kind': 'CANCELLED_CHEQUE', 'original_name': 'cheque.pdf', 'size_bytes': 4096},
      ],
    );

const sellerHost = SellerHost(
  token: _testToken,
  onSignOut: _noopSignOut,
  marketplaceName: 'BazaarX',
  supportEmail: 'support@bazaarx.in',
);

String? _testToken() => 'test-token';
void _noopSignOut() {}

Widget sellerApp(SellerApi api, {DocumentPicker? picker}) => MaterialApp(
      theme: buildMaterialTheme(isDark: false),
      builder: (context, child) => DsThemeScope(isDark: false, child: child ?? const SizedBox.shrink()),
      home: SellerArea(host: sellerHost, api: api, picker: picker ?? FakePicker()),
    );

Future<void> pumpSeller(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// A bottom-navigation destination. Plain `find.text('Products')` is ambiguous
/// because the overview has a "Products" card too.
Finder nav(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

