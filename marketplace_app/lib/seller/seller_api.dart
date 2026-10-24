import '../data/api_client.dart';
import 'document_picker.dart';
import 'seller_host.dart';
import 'seller_models.dart';

/// Every call the seller area makes. An interface so screens can be exercised
/// against a fake, and so a standalone seller app could talk to a different
/// transport without touching a screen.
abstract class SellerApi {
  /// Null means this account has no merchant account yet (the API answers 403).
  Future<Onboarding?> onboarding();

  Future<Onboarding> apply({required String displayName, String? supportEmail, String? supportPhone});

  /// Saves whichever KYC fields are given; the rest are left as they were.
  Future<Onboarding> saveKyc(Map<String, String> fields);

  Future<Onboarding> uploadDocument(String kind, PickedDocument file);
  Future<Onboarding> deleteDocument(String id);
  Future<Onboarding> submit();

  Future<SellerProfile> me();
  Future<void> updateProfile({String? displayName, String? supportEmail, String? supportPhone});

  /// Where the shop's goods are collected from (see [PickupAddress]).
  Future<void> updatePickup(PickupAddress address);

  /// The shop's page for shoppers: picture, words, hours, minimum order, PIN codes.
  Future<void> updateShop(ShopProfile shop);

  /// [status] filters on the order's status; [stage] on where the line is in the
  /// seller's own workflow: to_pack, packed, shipped, delivered or cancelled.
  Future<ListPage<SellerOrderItem>> orderItems({String? status, String? stage, int page = 1});

  /// How many orders wait for an answer, how many are late: polled while the app is open.
  Future<DeskCounts> deskCounts();

  /// Take an order on, promising it will be ready in [prepMinutes].
  Future<SellerOrderItem> acceptItem(String id, {int? prepMinutes});

  /// Turn an order down, or cancel it before it ships. [reason] is one of
  /// OUT_OF_STOCK, SHOP_CLOSED, CANNOT_PREPARE, DAMAGED, OTHER.
  Future<SellerOrderItem> rejectItem(String id, String reason, {String? note});

  /// Switch one item on or off for a while without touching its stock.
  Future<void> setAvailability(String productId, {required bool available, DateTime? until});

  /// Close the shop for [minutes] (0 reopens it now).
  Future<void> pauseShop(int minutes);

  /// Whether new orders are accepted automatically or wait for the shop.
  Future<void> setAutoAccept(bool auto);

  /// Balance, bank account and payout requests, for the Earnings screen.
  Future<SellerMoney> money();

  /// Ask to be paid [amount] (null: everything payable).
  Future<void> requestPayout({double? amount});

  Future<void> cancelPayout(String id);

  /// Ask to change the payout bank account; staff confirm it before it takes effect.
  Future<void> changeBank({required String holder, required String number, required String ifsc, String? bank});

  Future<void> withdrawBankChange();

  /// Months with activity, newest first.
  Future<List<String>> statementMonths();

  Future<SellerStatement> statement(String month);

  /// Mark one of the seller's lines packed. Saying it twice changes nothing.
  Future<SellerOrderItem> packItem(String id);

  /// Hand a line to a courier. Saying it again corrects the tracking details.
  ///
  /// With no [courier] or [trackingNo] the server books the courier itself and
  /// fills both in; with both, they are recorded as typed.
  Future<SellerOrderItem> shipItem(String id, {String? courier, String? trackingNo});

  Future<ListPage<SellerProduct>> products({String? status, String? search, int page = 1});
  Future<List<ProductCategory>> categories();
  Future<List<Map<String, dynamic>>> categoryRequests();
  Future<void> requestCategory(String name, String reason);
  Future<Map<String, dynamic>> previewImport(String raw);
  Future<int> commitImport(List<Map<String, dynamic>> rows, String status);

  /// Uploads a product photo and returns the URL to attach to the product.
  Future<String> uploadImage(PickedDocument file);

  Future<SellerProduct> createProduct(ProductInput input);
  Future<SellerProduct> updateProduct(String id, ProductInput input);

  /// Just the status — used to publish, unpublish or discontinue from a list.
  Future<void> setProductStatus(String id, String status);

  /// Change only stock counts, preserving product details and past variant ids.
  Future<void> updateStock(Map<String, int> stockByVariantId);

  /// Fails (422) for a product that has been ordered; discontinue it instead.
  Future<void> deleteProduct(String id);

  Future<ListPage<LedgerEntry>> ledger({int page = 1});
}

/// Talks to the marketplace's Laravel API.
class HttpSellerApi implements SellerApi {
  final SellerHost host;

  const HttpSellerApi(this.host);

  static const _perPage = '20';

  Future<dynamic> _call(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
    bool envelope = false,
  }) =>
      ApiClient.request(path, method: method, body: body, token: host.token(), query: query, envelope: envelope);

  Onboarding _onboarding(dynamic data) => Onboarding.fromJson((data as Map).cast<String, dynamic>());

  @override
  Future<Onboarding?> onboarding() async {
    try {
      return _onboarding(await _call('/seller/onboarding'));
    } on ApiException catch (e) {
      // "This area is for registered sellers": the account simply hasn't
      // applied yet. Any other 403 is a real refusal and should surface.
      if (e.status == 403) return null;
      rethrow;
    }
  }

  @override
  Future<Onboarding> apply({required String displayName, String? supportEmail, String? supportPhone}) async {
    final data = await _call('/sellers/apply', method: 'POST', body: {
      'display_name': displayName,
      if (supportEmail != null && supportEmail.isNotEmpty) 'support_email': supportEmail,
      if (supportPhone != null && supportPhone.isNotEmpty) 'support_phone': supportPhone,
    });
    return _onboarding(data);
  }

  @override
  Future<Onboarding> saveKyc(Map<String, String> fields) async =>
      _onboarding(await _call('/seller/onboarding/kyc', method: 'PUT', body: fields));

  @override
  Future<Onboarding> uploadDocument(String kind, PickedDocument file) async {
    final data = await ApiClient.upload(
      '/seller/onboarding/documents',
      fileField: 'file',
      bytes: file.bytes,
      filename: file.name,
      contentType: file.contentType,
      fields: {'kind': kind},
      token: host.token(),
    );
    // The upload answers with both the stored document and the fresh state.
    return _onboarding((data as Map)['onboarding']);
  }

  @override
  Future<Onboarding> deleteDocument(String id) async =>
      _onboarding(await _call('/seller/onboarding/documents/$id', method: 'DELETE'));

  @override
  Future<Onboarding> submit() async => _onboarding(await _call('/seller/onboarding/submit', method: 'POST'));

  @override
  Future<SellerProfile> me() async =>
      SellerProfile.fromJson(((await _call('/seller/me')) as Map).cast<String, dynamic>());

  @override
  Future<void> updateProfile({String? displayName, String? supportEmail, String? supportPhone}) async {
    await _call('/seller/me', method: 'PUT', body: {
      if (displayName != null) 'display_name': displayName,
      // Empty string clears the field; the API treats these as nullable.
      if (supportEmail != null) 'support_email': supportEmail.isEmpty ? null : supportEmail,
      if (supportPhone != null) 'support_phone': supportPhone.isEmpty ? null : supportPhone,
    });
  }

  @override
  Future<void> updatePickup(PickupAddress address) async {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await _call('/seller/me', method: 'PUT', body: {
      'pickup_name': clean(address.name),
      'pickup_phone': clean(address.phone),
      'pickup_line1': clean(address.line1),
      'pickup_city': clean(address.city),
      'pickup_state': clean(address.state),
      'pickup_pincode': clean(address.pincode),
    });
  }

  @override
  Future<void> updateShop(ShopProfile shop) => _call('/seller/me', method: 'PUT', body: shop.toJson());

  Future<ListPage<T>> _page<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    required int page,
    String? status,
    String? stage,
    String? search,
  }) async {
    final body = await _call(path, query: {
      'page': '$page',
      'per_page': _perPage,
      if (status != null && status.isNotEmpty) 'status': status,
      if (stage != null && stage.isNotEmpty) 'stage': stage,
      if (search != null && search.isNotEmpty) 'search': search,
    }, envelope: true);
    return ListPage.fromEnvelope((body as Map).cast<String, dynamic>(), parse);
  }

  @override
  Future<ListPage<SellerOrderItem>> orderItems({String? status, String? stage, int page = 1}) =>
      _page('/seller/order-items', SellerOrderItem.fromJson, page: page, status: status, stage: stage);

  @override
  Future<DeskCounts> deskCounts() async =>
      DeskCounts.fromJson(((await _call('/seller/overview')) as Map).cast<String, dynamic>());

  @override
  Future<SellerOrderItem> acceptItem(String id, {int? prepMinutes}) async =>
      SellerOrderItem.fromJson(((await _call('/seller/order-items/$id/accept', method: 'POST', body: {
        if (prepMinutes != null) 'prep_minutes': prepMinutes,
      })) as Map)
          .cast<String, dynamic>());

  @override
  Future<SellerOrderItem> rejectItem(String id, String reason, {String? note}) async =>
      SellerOrderItem.fromJson(((await _call('/seller/order-items/$id/reject', method: 'POST', body: {
        'reason': reason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      })) as Map)
          .cast<String, dynamic>());

  @override
  Future<void> setAvailability(String productId, {required bool available, DateTime? until}) async {
    await _call('/seller/products/$productId/availability', method: 'PUT', body: {
      'available': available,
      if (!available && until != null) 'until': until.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> pauseShop(int minutes) async {
    await _call('/seller/me', method: 'PUT', body: {'pause_minutes': minutes});
  }

  @override
  Future<void> setAutoAccept(bool auto) async {
    await _call('/seller/me', method: 'PUT', body: {'auto_accept': auto});
  }

  @override
  Future<SellerMoney> money() async => SellerMoney.fromJson(((await _call('/seller/money')) as Map).cast<String, dynamic>());

  @override
  Future<void> requestPayout({double? amount}) async {
    await _call('/seller/payout-requests', method: 'POST', body: {if (amount != null) 'amount': amount});
  }

  @override
  Future<void> cancelPayout(String id) async {
    await _call('/seller/payout-requests/$id', method: 'DELETE');
  }

  @override
  Future<void> changeBank({required String holder, required String number, required String ifsc, String? bank}) async {
    await _call('/seller/bank', method: 'POST', body: {
      'bank_account_holder': holder,
      'bank_account_number': number,
      'bank_ifsc': ifsc,
      if (bank != null && bank.isNotEmpty) 'bank_name': bank,
    });
  }

  @override
  Future<void> withdrawBankChange() async {
    await _call('/seller/bank/pending', method: 'DELETE');
  }

  @override
  Future<List<String>> statementMonths() async =>
      [for (final m in (await _call('/seller/statements')) as List) '$m'];

  @override
  Future<SellerStatement> statement(String month) async =>
      SellerStatement.fromJson(((await _call('/seller/statements/$month')) as Map).cast<String, dynamic>());

  @override
  Future<SellerOrderItem> packItem(String id) async => SellerOrderItem.fromJson(
      ((await _call('/seller/order-items/$id/pack', method: 'POST')) as Map).cast<String, dynamic>());

  @override
  Future<SellerOrderItem> shipItem(String id, {String? courier, String? trackingNo}) async =>
      SellerOrderItem.fromJson(((await _call('/seller/order-items/$id/ship', method: 'POST', body: {
        if (courier != null) 'courier': courier,
        if (trackingNo != null) 'tracking_no': trackingNo,
      })) as Map)
          .cast<String, dynamic>());

  @override
  Future<ListPage<SellerProduct>> products({String? status, String? search, int page = 1}) =>
      _page('/seller/products', SellerProduct.fromJson, page: page, status: status, search: search);

  @override
  Future<List<ProductCategory>> categories() async {
    final data = await _call('/categories');
    return (data as List).map((c) => ProductCategory.fromJson((c as Map).cast<String, dynamic>())).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> categoryRequests() async {
    final data = await _call('/seller/category-requests');
    return (data as List).map((row) => (row as Map).cast<String, dynamic>()).toList();
  }

  @override
  Future<void> requestCategory(String name, String reason) async {
    await _call('/seller/category-requests', method: 'POST', body: {
      'name': name,
      if (reason.isNotEmpty) 'reason': reason,
    });
  }

  @override
  Future<Map<String, dynamic>> previewImport(String raw) async =>
      (await _call('/seller/products/import/preview', method: 'POST', body: {'raw': raw}) as Map).cast<String, dynamic>();

  @override
  Future<int> commitImport(List<Map<String, dynamic>> rows, String status) async {
    final data = (await _call('/seller/products/import/commit', method: 'POST', body: {
      'status': status, 'rows': rows,
    }) as Map).cast<String, dynamic>();
    return (data['created'] as num).toInt();
  }

  @override
  Future<String> uploadImage(PickedDocument file) async {
    final data = await ApiClient.upload(
      '/uploads',
      fileField: 'file',
      bytes: file.bytes,
      filename: file.name,
      contentType: file.contentType,
      token: host.token(),
    );
    return ((data as Map)['url'] as String);
  }

  @override
  Future<SellerProduct> createProduct(ProductInput input) async => SellerProduct.fromJson(
      ((await _call('/products', method: 'POST', body: input.toJson())) as Map).cast<String, dynamic>());

  @override
  Future<SellerProduct> updateProduct(String id, ProductInput input) async => SellerProduct.fromJson(
      ((await _call('/products/$id', method: 'PUT', body: input.toJson())) as Map).cast<String, dynamic>());

  @override
  Future<void> setProductStatus(String id, String status) async {
    await _call('/products/$id', method: 'PUT', body: {'status': status});
  }

  @override
  Future<void> updateStock(Map<String, int> stockByVariantId) async {
    await _call('/inventory', method: 'PUT', body: {
      'items': [
        for (final entry in stockByVariantId.entries)
          {'variant_id': entry.key, 'stock': entry.value},
      ],
    });
  }

  @override
  Future<void> deleteProduct(String id) async {
    await _call('/products/$id', method: 'DELETE');
  }

  @override
  Future<ListPage<LedgerEntry>> ledger({int page = 1}) => _page('/seller/ledger', LedgerEntry.fromJson, page: page);
}
