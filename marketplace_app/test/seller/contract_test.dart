import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/seller/seller_models.dart';

/// Contract test: the app's models against responses the *real* API produced.
///
/// The fixtures in `fixtures/` were captured from the running Laravel backend
/// during a full seller journey (apply → details → documents → submit → reject →
/// resubmit → approve → sell something), so a field renamed on the server, or a
/// shape the models misread, fails here instead of on a seller's phone.
///
/// Regenerate them by running the live journey script against the API.
void main() {
  Map<String, dynamic> fixture(String name) =>
      jsonDecode(File('test/seller/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

  group('onboarding, at each stage of a real application', () {
    test('just applied: pending, draft, nothing filled in', () {
      final ob = Onboarding.fromJson(fixture('onboarding_draft'));

      expect(ob.account.standing, SellerStanding.pending);
      expect(ob.account.displayName, startsWith('E2E Crafts'));
      expect(ob.account.commissionRate, greaterThan(0), reason: 'the platform sets it');
      expect(ob.kyc.status, KycStatus.draft);
      expect(ob.kyc.panMasked, isNull);
      expect(ob.documents, isEmpty);
      expect(ob.checklist.canSubmit, isFalse);
      expect(ob.checklist.editable, isTrue);
      expect(ob.checklist.missingFields, containsAll(['pan', 'registered_line1', 'bank_account_number', 'bank_ifsc']));
      expect(ob.checklist.missingDocuments, containsAll(['PAN_CARD', 'CANCELLED_CHEQUE']));
      expect(ob.businessTypes, containsAll(['INDIVIDUAL', 'PROPRIETORSHIP', 'PARTNERSHIP', 'LLP', 'PRIVATE_LIMITED']));
      expect(ob.documentKinds, containsAll(['PAN_CARD', 'CANCELLED_CHEQUE', 'GST_CERTIFICATE', 'INCORPORATION_CERT', 'ADDRESS_PROOF']));
    });

    test('details saved: sensitive values arrive masked, never in full', () {
      final ob = Onboarding.fromJson(fixture('onboarding_details_saved'));

      expect(ob.kyc.businessType, 'PROPRIETORSHIP');
      expect(ob.kyc.legalName, 'Asha Rao');
      expect(ob.kyc.panMasked, isNotNull);
      expect(ob.kyc.panMasked!.length, 10);
      expect(RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(ob.kyc.panMasked!), isFalse, reason: 'must not be a whole PAN');
      expect(ob.kyc.bankAccountMasked, endsWith('9012'));
      expect(ob.kyc.bankAccountMasked, isNot('123456789012'));
      expect(ob.kyc.ifsc, 'HDFC0001234', reason: 'normalised to upper case by the server');
      expect(ob.kyc.city, 'Bengaluru');
      expect(ob.kyc.pincode, '560001');
      expect(ob.checklist.missingFields, isEmpty);
      expect(ob.checklist.canSubmit, isFalse, reason: 'documents are still missing');
    });

    test('ready to submit: documents attached, the server says so', () {
      final ob = Onboarding.fromJson(fixture('onboarding_ready'));

      expect(ob.documents.map((d) => d.kind), containsAll(['PAN_CARD', 'CANCELLED_CHEQUE']));
      expect(ob.documentOfKind('PAN_CARD')!.originalName, isNotEmpty);
      expect(ob.documentOfKind('PAN_CARD')!.sizeBytes, greaterThan(0));
      expect(ob.checklist.missingDocuments, isEmpty);
      expect(ob.checklist.canSubmit, isTrue);
    });

    test('submitted: locked, with a submission date', () {
      final ob = Onboarding.fromJson(fixture('onboarding_submitted'));

      expect(ob.kyc.status, KycStatus.submitted);
      expect(ob.kyc.submittedAt, isNotNull);
      expect(ob.checklist.editable, isFalse);
      expect(ob.account.standing, SellerStanding.pending);
    });

    test('rejected: the reviewer\'s reason is carried and the form is open again', () {
      final ob = Onboarding.fromJson(fixture('onboarding_rejected'));

      expect(ob.kyc.status, KycStatus.rejected);
      expect(ob.kyc.rejectionReason, 'The PAN photo is blurry.');
      expect(ob.checklist.editable, isTrue);
    });

    test('approved: the seller is active', () {
      final ob = Onboarding.fromJson(fixture('onboarding_active'));

      expect(ob.account.standing, SellerStanding.active);
      expect(ob.kyc.status, KycStatus.approved);
      expect(ob.kyc.rejectionReason, isNull);
    });
  });

  group('the dashboard, with real data', () {
    test('/seller/me', () {
      final p = SellerProfile.fromJson(fixture('seller_me'));

      expect(p.standing, SellerStanding.active);
      expect(p.commissionRate, greaterThan(0));
      expect(p.displayName, isNotEmpty);
      expect(p.payoutBalance, isA<double>());
      expect(p.productCount, isA<int>());
    });

    test('/seller/products: stock is summed across variants, images and category are read', () {
      final page = ListPage<SellerProduct>.fromEnvelope(fixture('seller_products'), SellerProduct.fromJson);

      expect(page.total, 1);
      final p = page.items.single;
      expect(p.title, isNotEmpty);
      expect(p.price, greaterThan(0));
      expect(p.status, 'ACTIVE');
      expect(p.stock, greaterThan(0));
      expect(p.category, isNotEmpty);
    });

    test('/seller/order-items: the line, where to ship it, and what the seller earns', () {
      final page = ListPage<SellerOrderItem>.fromEnvelope(fixture('seller_order_items'), SellerOrderItem.fromJson);

      expect(page.total, 1);
      final i = page.items.single;
      expect(i.title, isNotEmpty);
      expect(i.quantity, 2);
      expect(i.price, greaterThan(0));
      expect(i.earning, greaterThan(0));
      expect(i.commission, greaterThan(0));
      expect(i.earning + i.commission, closeTo(i.price * i.quantity, 0.01), reason: 'earning + commission = what the line sold for');
      expect(i.orderNumber, startsWith('ORD-'));
      expect(i.orderStatus, 'CONFIRMED');
      expect(i.shipToCity, 'Bengaluru');
      expect(i.shipToPincode, '560038');
      expect(i.createdAt, isNotNull);
    });

    test('/seller/ledger: the sale entry and the running balance beside it', () {
      final page = ListPage<LedgerEntry>.fromEnvelope(fixture('seller_ledger'), LedgerEntry.fromJson);

      expect(page.extra['balance'], isA<num>());
      expect(page.extra['balance'] as num, greaterThan(0));

      final e = page.items.single;
      expect(e.type, 'SALE');
      expect(e.net, greaterThan(0));
      expect(e.gross - e.commission, closeTo(e.net, 0.01));
      expect(e.balanceAfter, closeTo((page.extra['balance'] as num).toDouble(), 0.01));
      expect(e.createdAt, isNotNull);
    });
  });

  group('fulfilment and products, with real data', () {
    test('a line waiting to be packed', () {
      final page = ListPage<SellerOrderItem>.fromEnvelope(fixture('seller_order_items_to_pack'), SellerOrderItem.fromJson);
      final i = page.items.single;

      expect(i.fulfilmentStatus, 'PENDING');
      expect(i.courier, isNull);
      expect(i.trackingNo, isNull);
      expect(i.orderStatus, 'CONFIRMED');
      expect(i.canPack, isTrue);
      expect(i.canShip, isTrue);
      expect(i.canEditTracking, isFalse);
    });

    test('the response to packing a line', () {
      final i = SellerOrderItem.fromJson(fixture('fulfilment_packed'));

      expect(i.fulfilmentStatus, 'PACKED');
      expect(i.canPack, isFalse);
      expect(i.canShip, isTrue);
      expect(i.title, isNotEmpty, reason: 'the response carries the product, for the list to re-render');
      expect(i.orderNumber, startsWith('ORD-'));
    });

    test('the response to shipping a line, with its tracking', () {
      final i = SellerOrderItem.fromJson(fixture('fulfilment_shipped'));

      expect(i.fulfilmentStatus, 'SHIPPED');
      expect(i.courier, 'Delhivery');
      expect(i.trackingNo, startsWith('DL'));
      expect(i.shippedAt, isNotNull);
      expect(i.canShip, isFalse);
    });

    test('a shipped line after a correction', () {
      final page = ListPage<SellerOrderItem>.fromEnvelope(fixture('seller_order_items_shipped'), SellerOrderItem.fromJson);
      final i = page.items.single;

      expect(i.courier, 'Blue Dart', reason: 'the corrected courier, not the first one');
      expect(i.trackingNo, startsWith('BD'));
    });

    test('ship validation errors arrive keyed by field, ready for the sheet', () {
      final e = fixture('fulfilment_ship_validation_error')['errors'] as Map<String, dynamic>;

      expect(e.keys, containsAll(['courier', 'tracking_no']));
      expect((e['courier'] as List).first, isA<String>());
    });

    test('categories for the picker', () {
      final list = (fixture('categories')['data'] as List).map((c) => ProductCategory.fromJson((c as Map).cast<String, dynamic>())).toList();

      expect(list, isNotEmpty);
      expect(list.first.id, isNotEmpty);
      expect(list.first.name, isNotEmpty);
    });

    test('an upload answers with a URL to attach to the product', () {
      final u = fixture('upload_response');

      expect(u['url'], startsWith('http'));
      expect(u['path'], startsWith('uploads/'));
    });

    test('a draft product carries everything the form needs to edit it', () {
      final page = ListPage<SellerProduct>.fromEnvelope(fixture('seller_products_drafts'), SellerProduct.fromJson);

      expect(page.total, 2);
      // Newest first, so the two-variant product is not necessarily the first.
      final p = page.items.firstWhere((p) => p.variants.length == 2);
      expect(p.status, 'DRAFT');
      expect(p.title, startsWith('E2E Brass Lamp'));
      expect(p.description, 'Hand-finished.');
      expect(p.brand, 'Asha Crafts');
      expect(p.mrp, 2999.0);
      expect(p.price, 2499.0);
      expect(p.categoryId, isNotEmpty);
      expect(p.images, hasLength(1));
      expect(p.variants, hasLength(2));
      expect(p.variants.map((v) => v.sku), everyElement(startsWith('E2E-')));
      expect(p.variants.every((v) => v.id != null), isTrue);
      expect(p.stock, 8);
    });

    test('a per-variant price survives the round trip', () {
      final page = ListPage<SellerProduct>.fromEnvelope(fixture('seller_products_drafts'), SellerProduct.fromJson);
      final silver = page.items.expand((p) => p.variants).firstWhere((v) => v.color == 'Silver');

      expect(silver.price, 2399.0);
      expect(silver.mrp, 2999.0);
    });

    test('a duplicate SKU comes back as an error on the variant SKU field', () {
      final e = fixture('product_validation_error')['errors'] as Map<String, dynamic>;

      expect(e.keys, contains('variants.0.sku'));
    });

    test('deleting a product that was ordered explains itself and points to DISCONTINUED', () {
      final j = fixture('product_delete_blocked');

      expect(j['message'], contains('DISCONTINUED'));
    });
  });
}
