import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/seller/document_picker.dart';
import 'package:marketplace_app/seller/seller_format.dart';
import 'package:marketplace_app/seller/seller_models.dart';
import 'package:marketplace_app/seller/validators.dart';

/// The pure logic under the seller screens: the rules mirrored from the API, and
/// how its JSON becomes objects. Sample payloads here are the shapes the real
/// endpoints return (checked against the running API).
void main() {
  group('validators mirror the API rules', () {
    test('PAN', () {
      expect(SellerValidators.pan('ABCDE1234F'), isNull);
      expect(SellerValidators.pan('abcde1234f'), isNull, reason: 'lower case is still a PAN');
      expect(SellerValidators.pan(' ABCDE1234F '), isNull);
      expect(SellerValidators.pan('ABCDE12345'), isNotNull);
      expect(SellerValidators.pan('ABCD1234F'), isNotNull);
      expect(SellerValidators.pan(''), isNotNull);
    });

    test('GSTIN is optional but must be well formed when given', () {
      expect(SellerValidators.gstin(''), isNull);
      expect(SellerValidators.gstin('29ABCDE1234F1Z5'), isNull);
      expect(SellerValidators.gstin('29abcde1234f1z5'), isNull);
      expect(SellerValidators.gstin('29ABCDE1234F1X5'), isNotNull, reason: 'the 14th character must be Z');
      expect(SellerValidators.gstin('nonsense'), isNotNull);
    });

    test('IFSC', () {
      expect(SellerValidators.ifsc('HDFC0001234'), isNull);
      expect(SellerValidators.ifsc('hdfc0001234'), isNull);
      expect(SellerValidators.ifsc('HDFC1001234'), isNotNull, reason: 'the fifth character is always 0');
      expect(SellerValidators.ifsc('HDF0001234'), isNotNull);
    });

    test('bank account number is 9 to 18 digits', () {
      expect(SellerValidators.accountNumber('123456789'), isNull);
      expect(SellerValidators.accountNumber('123456789012345678'), isNull);
      expect(SellerValidators.accountNumber('12345678'), isNotNull);
      expect(SellerValidators.accountNumber('1234567890123456789'), isNotNull);
      expect(SellerValidators.accountNumber('1234-5678-90'), isNotNull);
    });

    test('PIN code is six digits and never starts with 0', () {
      expect(SellerValidators.pincode('560038'), isNull);
      expect(SellerValidators.pincode('060038'), isNotNull);
      expect(SellerValidators.pincode('56003'), isNotNull);
      expect(SellerValidators.pincode('5600381'), isNotNull);
    });

    test('optional contact fields accept blanks but reject malformed values', () {
      expect(SellerValidators.optionalEmail(''), isNull);
      expect(SellerValidators.optionalEmail('shop@example.com'), isNull);
      expect(SellerValidators.optionalEmail('not-an-email'), isNotNull);
      expect(SellerValidators.optionalPhone(''), isNull);
      expect(SellerValidators.optionalPhone('9876543210'), isNull);
      expect(SellerValidators.optionalPhone('abc'), isNotNull);
    });

    test('normalise trims and upper-cases', () {
      expect(SellerValidators.normalise('  abcde1234f '), 'ABCDE1234F');
    });
  });

  group('document rules', () {
    PickedDocument doc(String name, int bytes) => PickedDocument(name: name, bytes: List.filled(bytes, 1));

    test('accepts images and PDFs', () {
      for (final n in ['a.jpg', 'a.JPEG', 'a.png', 'a.webp', 'a.pdf']) {
        expect(DocumentRules.problemWith(doc(n, 100)), isNull, reason: n);
      }
    });

    test('rejects other types, empty files and files over 5 MB', () {
      expect(DocumentRules.problemWith(doc('a.exe', 100)), isNotNull);
      expect(DocumentRules.problemWith(doc('noextension', 100)), isNotNull);
      expect(DocumentRules.problemWith(doc('a.pdf', 0)), isNotNull);
      expect(DocumentRules.problemWith(doc('a.pdf', DocumentRules.maxBytes + 1)), isNotNull);
      expect(DocumentRules.problemWith(doc('a.pdf', DocumentRules.maxBytes)), isNull);
    });

    test('declares a sensible content type', () {
      expect(doc('a.pdf', 1).contentType, 'application/pdf');
      expect(doc('a.png', 1).contentType, 'image/png');
      expect(doc('a.jpg', 1).contentType, 'image/jpeg');
    });
  });

  group('models parse the API payloads', () {
    final onboardingJson = {
      'seller': {
        'id': 's1', 'display_name': 'Asha Crafts', 'slug': 'asha-crafts', 'status': 'PENDING',
        'support_email': 'asha@example.com', 'support_phone': null, 'commission_rate': 10,
      },
      'kyc': {
        'business_type': 'PROPRIETORSHIP', 'legal_name': 'Asha Rao', 'pan': 'XXXXXX234F', 'gstin': null,
        'registered_line1': '12 MG Road', 'registered_line2': null, 'registered_city': 'Bengaluru',
        'registered_state': 'Karnataka', 'registered_pincode': '560001',
        'bank_account_holder': 'Asha Rao', 'bank_account_number': 'XXXXXXXX6789', 'bank_ifsc': 'HDFC0001234',
        'bank_name': null, 'status': 'REJECTED', 'submitted_at': '2026-09-30T10:00:00.000000Z',
        'reviewed_at': null, 'rejection_reason': 'The PAN photo is blurry.',
      },
      'documents': [
        {'id': 'd1', 'kind': 'PAN_CARD', 'original_name': 'pan.jpg', 'size_bytes': 2048, 'uploaded_at': '2026-09-30T10:00:00Z'},
      ],
      'checklist': {
        'missing_fields': [], 'missing_documents': ['CANCELLED_CHEQUE'], 'can_submit': false, 'editable': true,
      },
      'accepted_document_kinds': ['PAN_CARD', 'GST_CERTIFICATE', 'CANCELLED_CHEQUE', 'ADDRESS_PROOF', 'INCORPORATION_CERT'],
      'business_types': ['INDIVIDUAL', 'PROPRIETORSHIP', 'PARTNERSHIP', 'LLP', 'PRIVATE_LIMITED'],
    };

    test('onboarding overview', () {
      final ob = Onboarding.fromJson(onboardingJson);

      expect(ob.account.displayName, 'Asha Crafts');
      expect(ob.account.standing, SellerStanding.pending);
      expect(ob.account.supportPhone, isNull);
      expect(ob.account.commissionRate, 10.0);
      expect(ob.kyc.status, KycStatus.rejected);
      expect(ob.kyc.rejectionReason, 'The PAN photo is blurry.');
      expect(ob.kyc.panMasked, 'XXXXXX234F');
      expect(ob.kyc.hasGstin, isFalse);
      expect(ob.kyc.isRegisteredEntity, isFalse);
      expect(ob.checklist.missingDocuments, ['CANCELLED_CHEQUE']);
      expect(ob.checklist.canSubmit, isFalse);
      expect(ob.documentOfKind('PAN_CARD')?.originalName, 'pan.jpg');
      expect(ob.documentOfKind('CANCELLED_CHEQUE'), isNull);
    });

    test('registered entities are recognised, for the incorporation certificate rule', () {
      for (final t in ['LLP', 'PRIVATE_LIMITED', 'PARTNERSHIP']) {
        expect(KycProfile.fromJson({'business_type': t}).isRegisteredEntity, isTrue, reason: t);
      }
      for (final t in ['INDIVIDUAL', 'PROPRIETORSHIP']) {
        expect(KycProfile.fromJson({'business_type': t}).isRegisteredEntity, isFalse, reason: t);
      }
    });

    test('unknown statuses fall back safely instead of crashing', () {
      expect(SellerAccount.fromJson({'status': 'SOMETHING_NEW'}).standing, SellerStanding.pending);
      expect(KycProfile.fromJson({'status': null}).status, KycStatus.draft);
    });

    test('an order item, including money that arrives as strings', () {
      final item = SellerOrderItem.fromJson({
        'id': 'i1', 'quantity': 2, 'price': '1000.00', 'seller_earning': '1800.00', 'commission_amount': '200.00',
        'created_at': '2026-09-30T10:00:00Z',
        'product': {'title': 'Brass Lamp', 'images': ['https://img/x.jpg']},
        'variant': {'color': 'Gold', 'size': 'M'},
        'order': {
          'order_number': 'ORD-ABC12345', 'status': 'CONFIRMED', 'payment_status': 'PAID',
          'shipping_address': {'name': 'Priya', 'city': 'Bengaluru', 'pincode': '560038'},
        },
      });

      expect(item.price, 1000.0);
      expect(item.earning, 1800.0);
      expect(item.variantLabel, 'Gold · M');
      expect(item.image, 'https://img/x.jpg');
      expect(item.orderNumber, 'ORD-ABC12345');
      expect(item.shipToCity, 'Bengaluru');
    });

    test('an order item with missing relations does not crash', () {
      final item = SellerOrderItem.fromJson({'id': 'i2', 'quantity': 1});
      expect(item.title, '');
      expect(item.image, isNull);
      expect(item.shipToCity, '');
    });

    test('a product sums stock across its variants and tolerates object-style images', () {
      final p = SellerProduct.fromJson({
        'id': 'p1', 'title': 'Lamp', 'price': '2499.00', 'status': 'ACTIVE',
        'images': [
          {'url': 'https://img/a.jpg'},
        ],
        'variants': [
          {'stock': 4},
          {'stock': 6},
        ],
        'category': {'name': 'Decor'},
      });

      expect(p.stock, 10);
      expect(p.price, 2499.0);
      expect(p.image, 'https://img/a.jpg');
      expect(p.category, 'Decor');
    });

    test('a ledger page keeps the balance the endpoint adds beside the rows', () {
      final page = ListPage<LedgerEntry>.fromEnvelope({
        'status': 'success',
        'count': 45,
        'balance': 1234.5,
        'data': [
          {'id': 'l1', 'type': 'SALE', 'gross': '900.00', 'commission': '90.00', 'net': '810.00', 'balance_after': '810.00', 'note': 'Sale'},
        ],
        'meta': {'current_page': 1, 'last_page': 3, 'per_page': 20, 'total': 45},
      }, LedgerEntry.fromJson);

      expect(page.items.single.net, 810.0);
      expect(page.total, 45);
      expect(page.hasMore, isTrue);
      expect(page.extra['balance'], 1234.5);
    });

    test('a page with no meta is a single page', () {
      final page = ListPage<LedgerEntry>.fromEnvelope({'data': []}, LedgerEntry.fromJson);
      expect(page.hasMore, isFalse);
      expect(page.page, 1);
    });
  });

  group('ApiException carries per-field errors', () {
    test('the first message for a field', () {
      final e = ApiException(422, 'x', errors: {'pan': ['Bad PAN.', 'Also bad.'], 'bank_ifsc': ['Bad IFSC.']});
      expect(e.fieldError('pan'), 'Bad PAN.');
      expect(e.fieldError('bank_ifsc'), 'Bad IFSC.');
      expect(e.fieldError('other'), isNull);
    });

    test('no errors map is fine', () {
      expect(ApiException(500, 'boom').fieldError('pan'), isNull);
    });
  });

  group('formatting', () {
    test('rupees use Indian grouping', () {
      expect(SellerFormat.money(1234567.5), '₹12,34,567.50');
      expect(SellerFormat.moneyWhole(1234567.5), contains('12,34,568'));
    });

    test('sizes', () {
      expect(SellerFormat.size(500), '500 B');
      expect(SellerFormat.size(2048), '2 KB');
      expect(SellerFormat.size(3 * 1024 * 1024), '3.0 MB');
    });

    test('missing fields have readable names', () {
      expect(SellerFormat.field('bank_ifsc'), 'IFSC code');
      expect(SellerFormat.field('registered_pincode'), 'PIN code');
      expect(SellerFormat.field('some_new_field'), 'some new field');
    });
  });
}
