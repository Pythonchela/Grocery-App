import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/seller/document_picker.dart';
import 'package:marketplace_app/seller/seller_models.dart';

import 'support.dart';

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('routing: the gate shows the screen the account belongs on', () {
    testWidgets('no merchant account -> apply', (tester) async {
      await pumpSeller(tester, sellerApp(FakeSellerApi(null)));

      expect(find.text('Sell on BazaarX'), findsOneWidget);
      expect(find.text('Start application'), findsOneWidget);
    });

    testWidgets('unfinished details -> the guided application', (tester) async {
      await pumpSeller(tester, sellerApp(FakeSellerApi(buildOnboarding(missingFields: allKycFields))));

      expect(find.text('Your seller application'), findsOneWidget);
      expect(find.text('About your business'), findsOneWidget);
    });

    testWidgets('submitted -> under review', (tester) async {
      final api = FakeSellerApi(buildOnboarding(kyc: 'SUBMITTED', kycOverrides: {'submitted_at': '2026-09-30T10:00:00Z'}));
      await pumpSeller(tester, sellerApp(api));

      expect(find.text('Your application is under review'), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
      expect(find.text('Asha Crafts'), findsOneWidget);
    });

    testWidgets('approved but not yet switched on -> verified, waiting', (tester) async {
      await pumpSeller(tester, sellerApp(FakeSellerApi(buildOnboarding(kyc: 'APPROVED'))));

      expect(find.text('You are verified'), findsOneWidget);
    });

    testWidgets('suspended -> says so and points to support', (tester) async {
      await pumpSeller(tester, sellerApp(FakeSellerApi(buildOnboarding(seller: 'SUSPENDED', kyc: 'APPROVED'))));

      expect(find.text('Your seller account is suspended'), findsOneWidget);
      expect(find.textContaining('support@bazaarx.in'), findsOneWidget);
    });

    testWidgets('active -> the dashboard', (tester) async {
      await pumpSeller(tester, sellerApp(FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))));

      expect(find.text('Overview'), findsWidgets);
      expect(nav('Earnings'), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final api = FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))
        ..onboardingError = ApiException(500, 'The server had a problem.');
      await pumpSeller(tester, sellerApp(api));

      expect(find.text('The server had a problem.'), findsOneWidget);

      await tapAndSettle(tester, find.text('Try again'));

      expect(find.text('The server had a problem.'), findsNothing);
      expect(nav('Earnings'), findsOneWidget);
    });
  });

  group('applying', () {
    testWidgets('a shop name is required, and nothing is sent without one', (tester) async {
      final api = FakeSellerApi(null);
      await pumpSeller(tester, sellerApp(api));

      await tapAndSettle(tester, find.text('Start application'));

      expect(find.text('Enter your shop name.'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('apply')), isEmpty);
    });

    testWidgets('a malformed support email is caught before any request', (tester) async {
      final api = FakeSellerApi(null);
      await pumpSeller(tester, sellerApp(api));

      await tester.enterText(find.byType(TextField).at(0), 'Asha Crafts');
      await tester.enterText(find.byType(TextField).at(1), 'not-an-email');
      await tapAndSettle(tester, find.text('Start application'));

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('apply')), isEmpty);
    });

    testWidgets('applying moves straight into the application', (tester) async {
      final api = FakeSellerApi(null);
      await pumpSeller(tester, sellerApp(api));

      await tester.enterText(find.byType(TextField).at(0), 'Asha Crafts');
      await tapAndSettle(tester, find.text('Start application'));

      expect(api.calls, contains('apply:Asha Crafts'));
      expect(find.text('Your seller application'), findsOneWidget);
    });
  });

  group('the application: business step', () {
    testWidgets('a PAN is required the first time', (tester) async {
      final api = FakeSellerApi(buildOnboarding(missingFields: allKycFields));
      await pumpSeller(tester, sellerApp(api));

      await tapAndSettle(tester, find.text('Save and continue'));

      expect(find.text('Enter your PAN.'), findsOneWidget);
      expect(api.calls, isNot(contains('saveKyc')));
    });

    testWidgets('a badly formed PAN is caught before any request', (tester) async {
      final api = FakeSellerApi(buildOnboarding(missingFields: allKycFields));
      await pumpSeller(tester, sellerApp(api));

      await tester.enterText(find.byType(TextField).at(1), 'ABCDE12345');
      await tapAndSettle(tester, find.text('Save and continue'));

      expect(find.textContaining('does not look like a PAN'), findsOneWidget);
      expect(api.calls, isNot(contains('saveKyc')));
    });

    testWidgets('a valid PAN is sent upper-cased and the seller moves on to the address', (tester) async {
      final api = FakeSellerApi(buildOnboarding(missingFields: allKycFields))
        ..afterSave = buildOnboarding(missingFields: allKycFields.sublist(3), kycOverrides: {'pan': 'XXXXXX234F'});
      await pumpSeller(tester, sellerApp(api));

      await tester.enterText(find.byType(TextField).at(1), 'abcde1234f');
      await tapAndSettle(tester, find.text('Save and continue'));

      expect(api.lastKycSave!['pan'], 'ABCDE1234F');
      expect(api.lastKycSave!['business_type'], 'INDIVIDUAL');
      expect(find.text('Registered address'), findsOneWidget);
    });

    testWidgets('a saved PAN is shown masked, never filled in, and leaving it blank keeps it', (tester) async {
      final api = FakeSellerApi(buildOnboarding(
        missingFields: allKycFields.sublist(3),
        kycOverrides: {'pan': 'XXXXXX234F'},
      ));
      await pumpSeller(tester, sellerApp(api));

      // The application resumes at the first incomplete step (address); go back.
      await tapAndSettle(tester, find.text('Business'));

      expect(find.text('Saved: XXXXXX234F — leave blank to keep'), findsOneWidget);
      expect((tester.widget<TextField>(find.byType(TextField).at(1)).controller!).text, isEmpty);

      await tapAndSettle(tester, find.text('Save and continue'));

      expect(api.lastKycSave!.containsKey('pan'), isFalse, reason: 'a blank masked field must not overwrite the saved PAN');
    });

    testWidgets('the server\'s field error appears under the field it belongs to', (tester) async {
      final api = FakeSellerApi(buildOnboarding(missingFields: allKycFields))
        ..saveKycError = ApiException(
          422,
          'This PAN is already registered to another seller account.',
          errors: {'pan': ['This PAN is already registered to another seller account.']},
        );
      await pumpSeller(tester, sellerApp(api));

      await tester.enterText(find.byType(TextField).at(1), 'ABCDE1234F');
      await tapAndSettle(tester, find.text('Save and continue'));

      expect(find.text('This PAN is already registered to another seller account.'), findsOneWidget);
      expect(find.text('About your business'), findsOneWidget, reason: 'stays on the step until it is fixed');
    });

    testWidgets('a rejected application shows the reviewer\'s reason', (tester) async {
      final api = FakeSellerApi(buildOnboarding(
        kyc: 'REJECTED',
        missingFields: const [],
        kycOverrides: {'rejection_reason': 'The PAN photo is blurry.', 'pan': 'XXXXXX234F'},
      ));
      await pumpSeller(tester, sellerApp(api));

      expect(find.text('Changes needed'), findsOneWidget);
      expect(find.text('The PAN photo is blurry.'), findsOneWidget);
    });
  });

  group('the application: address and bank steps', () {
    testWidgets('address: PIN code rules are enforced', (tester) async {
      final api = FakeSellerApi(buildOnboarding(missingFields: allKycFields.sublist(3), kycOverrides: {'pan': 'XXXXXX234F'}));
      await pumpSeller(tester, sellerApp(api));

      await tester.enterText(find.byType(TextField).at(0), '12 MG Road');
      await tester.enterText(find.byType(TextField).at(2), 'Bengaluru');
      await tester.enterText(find.byType(TextField).at(3), 'Karnataka');
      await tester.enterText(find.byType(TextField).at(4), '060001');
      await tapAndSettle(tester, find.text('Save and continue'));

      expect(find.textContaining('PIN code is 6 digits'), findsOneWidget);
      expect(api.calls, isNot(contains('saveKyc')));
    });

    testWidgets('bank: account number and IFSC are checked, and the account number is required', (tester) async {
      final api = FakeSellerApi(buildOnboarding(
        missingFields: ['bank_account_holder', 'bank_account_number', 'bank_ifsc'],
        kycOverrides: {'pan': 'XXXXXX234F', 'registered_line1': 'x', 'registered_city': 'x', 'registered_state': 'x', 'registered_pincode': '560001'},
      ));
      await pumpSeller(tester, sellerApp(api));

      expect(find.text('Where should we pay you?'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Asha Rao');
      await tester.enterText(find.byType(TextField).at(2), 'BAD');
      await tapAndSettle(tester, find.text('Save and continue'));

      expect(find.text('Enter your bank account number.'), findsOneWidget);
      expect(find.textContaining('IFSC'), findsWidgets);
      expect(api.calls, isNot(contains('saveKyc')));
    });
  });

  group('the application: documents', () {
    Onboarding docsStep({List<Map<String, dynamic>> documents = const [], List<String>? missing}) => buildOnboarding(
          missingDocuments: missing ?? ['PAN_CARD', 'CANCELLED_CHEQUE'],
          kycOverrides: {
            'pan': 'XXXXXX234F', 'registered_line1': 'x', 'registered_city': 'x', 'registered_state': 'x',
            'registered_pincode': '560001', 'bank_account_holder': 'x', 'bank_account_number': 'XXXX6789', 'bank_ifsc': 'HDFC0001234',
          },
          documents: documents,
        );

    testWidgets('resumes at documents when only they are missing, and marks what is required', (tester) async {
      await pumpSeller(tester, sellerApp(FakeSellerApi(docsStep())));

      expect(find.text('Upload your documents'), findsOneWidget);
      expect(find.text('PAN card'), findsOneWidget);
      expect(find.text('Cancelled cheque'), findsOneWidget);
      expect(find.text('Required'), findsNWidgets(2));
      expect(find.text('Optional'), findsWidgets);
    });

    testWidgets('a good file is uploaded against the right document kind', (tester) async {
      final api = FakeSellerApi(docsStep())
        ..afterUpload = docsStep(
          documents: [
            {'id': 'd1', 'kind': 'PAN_CARD', 'original_name': 'pan.jpg', 'size_bytes': 2048},
          ],
          missing: ['CANCELLED_CHEQUE'],
        );
      final picker = FakePicker(PickedDocument(name: 'pan.jpg', bytes: List.filled(2048, 1)));
      await pumpSeller(tester, sellerApp(api, picker: picker));

      await tapAndSettle(tester, find.text('Choose file').first);

      expect(api.calls, contains('upload:PAN_CARD'));
      expect(find.textContaining('pan.jpg'), findsOneWidget);
      expect(find.text('Uploaded'), findsOneWidget);
    });

    testWidgets('a file that is too big is refused before it is uploaded', (tester) async {
      final api = FakeSellerApi(docsStep());
      final picker = FakePicker(PickedDocument(name: 'huge.pdf', bytes: List.filled(DocumentRules.maxBytes + 1, 1)));
      await pumpSeller(tester, sellerApp(api, picker: picker));

      await tapAndSettle(tester, find.text('Choose file').first);

      expect(find.textContaining('over 5 MB'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('upload')), isEmpty);
    });

    testWidgets('the wrong file type is refused before it is uploaded', (tester) async {
      final api = FakeSellerApi(docsStep());
      final picker = FakePicker(PickedDocument(name: 'malware.exe', bytes: List.filled(100, 1)));
      await pumpSeller(tester, sellerApp(api, picker: picker));

      await tapAndSettle(tester, find.text('Choose file').first);

      expect(find.textContaining('JPG, PNG, WebP or PDF'), findsWidgets);
      expect(api.calls.where((c) => c.startsWith('upload')), isEmpty);
    });

    testWidgets('backing out of the file dialog is not an error', (tester) async {
      final api = FakeSellerApi(docsStep());
      await pumpSeller(tester, sellerApp(api, picker: FakePicker(null)));

      await tapAndSettle(tester, find.text('Choose file').first);

      expect(api.calls.where((c) => c.startsWith('upload')), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a GSTIN makes the GST certificate required; a company makes the incorporation certificate required', (tester) async {
      final api = FakeSellerApi(buildOnboarding(
        missingDocuments: ['GST_CERTIFICATE', 'INCORPORATION_CERT'],
        kycOverrides: {
          'business_type': 'PRIVATE_LIMITED', 'gstin': 'XXXXXXXXXXX1Z5',
          'pan': 'XXXXXX234F', 'registered_line1': 'x', 'registered_city': 'x', 'registered_state': 'x',
          'registered_pincode': '560001', 'bank_account_holder': 'x', 'bank_account_number': 'XXXX6789', 'bank_ifsc': 'HDFC0001234',
        },
        documents: [
          {'id': 'd1', 'kind': 'PAN_CARD', 'original_name': 'p.jpg', 'size_bytes': 1},
          {'id': 'd2', 'kind': 'CANCELLED_CHEQUE', 'original_name': 'c.jpg', 'size_bytes': 1},
        ],
      ));
      await pumpSeller(tester, sellerApp(api));

      expect(find.text('GST certificate'), findsOneWidget);
      expect(find.text('Certificate of incorporation'), findsOneWidget);
      expect(find.text('Required'), findsNWidgets(2));
    });
  });

  group('the application: review and submit', () {
    testWidgets('an incomplete application cannot be submitted, and says what is missing', (tester) async {
      final api = FakeSellerApi(buildOnboarding(
        missingDocuments: ['CANCELLED_CHEQUE'],
        kycOverrides: {'pan': 'XXXXXX234F'},
        documents: [
          {'id': 'd1', 'kind': 'PAN_CARD', 'original_name': 'p.jpg', 'size_bytes': 1},
        ],
      ));
      await pumpSeller(tester, sellerApp(api));
      await tapAndSettle(tester, find.text('Review'));

      expect(find.text('Almost there'), findsOneWidget);
      expect(find.text('Cancelled cheque (document)'), findsOneWidget);

      await tapAndSettle(tester, find.text('Submit for review'));
      expect(api.calls, isNot(contains('submit')), reason: 'the button is disabled');
    });

    testWidgets('a complete application can be submitted, after confirming', (tester) async {
      final api = FakeSellerApi(readyToSubmit())
        ..afterSubmit = buildOnboarding(kyc: 'SUBMITTED', kycOverrides: {'submitted_at': '2026-09-30T10:00:00Z'});
      await pumpSeller(tester, sellerApp(api));
      await tapAndSettle(tester, find.text('Review'));

      expect(find.text('Almost there'), findsNothing);
      expect(find.text('XXXXXX234F'), findsOneWidget, reason: 'the PAN is shown masked');

      await tapAndSettle(tester, find.text('Submit for review'));
      expect(find.text('Submit for review?'), findsOneWidget);
      expect(api.calls, isNot(contains('submit')), reason: 'nothing is sent until the dialog is confirmed');

      await tapAndSettle(tester, find.text('Submit'));

      expect(api.calls, contains('submit'));
      expect(find.text('Your application is under review'), findsOneWidget);
    });

    testWidgets('choosing "Not yet" in the dialog sends nothing', (tester) async {
      final api = FakeSellerApi(readyToSubmit());
      await pumpSeller(tester, sellerApp(api));
      await tapAndSettle(tester, find.text('Review'));

      await tapAndSettle(tester, find.text('Submit for review'));
      await tapAndSettle(tester, find.text('Not yet'));

      expect(api.calls, isNot(contains('submit')));
      expect(find.text('Review and submit'), findsOneWidget);
    });
  });

  group('the dashboard', () {
    FakeSellerApi active() => FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))
      ..orderRows = [
        const SellerOrderItem(
          id: 'i1', title: 'Brass Lamp', variantLabel: 'Gold', quantity: 2, price: 1000, earning: 1800,
          orderNumber: 'ORD-AAA11111', orderStatus: 'CONFIRMED', shipToName: 'Priya', shipToCity: 'Bengaluru', shipToPincode: '560038',
        ),
        const SellerOrderItem(
          id: 'i2', title: 'Silk Scarf', quantity: 1, price: 500, earning: 450,
          orderNumber: 'ORD-BBB22222', orderStatus: 'DELIVERED', shipToCity: 'Pune',
        ),
      ]
      ..productRows = [
        const SellerProduct(id: 'p1', title: 'Brass Lamp', price: 1000, status: 'ACTIVE', stock: 12, category: 'Decor'),
        const SellerProduct(id: 'p2', title: 'Draft Item', price: 99, status: 'DRAFT', stock: 0),
      ]
      ..ledgerBalance = 2250
      ..ledgerRows = [
        const LedgerEntry(id: 'l1', type: 'SALE', gross: 2000, commission: 200, net: 1800, balanceAfter: 1800, note: 'Sale ORD-AAA11111'),
        const LedgerEntry(id: 'l2', type: 'REFUND', gross: -500, commission: -50, net: -450, balanceAfter: 1350),
      ];

    testWidgets('overview shows the balance, the count to pack and the commission', (tester) async {
      await pumpSeller(tester, sellerApp(active()));

      expect(find.text('₹1,235'), findsOneWidget); // 1234.5 rounded for the headline
      expect(find.text('Payout balance'), findsOneWidget);
      expect(find.text('To pack'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // one CONFIRMED item to ship
      expect(find.text('7'), findsOneWidget); // product count
      expect(find.text('10%'), findsOneWidget);
    });

    testWidgets('overview lists recent orders and the shop details', (tester) async {
      await pumpSeller(tester, sellerApp(active()));

      expect(find.text('Brass Lamp'), findsWidgets);
      expect(find.text('asha@example.com'), findsOneWidget);
      expect(find.text('Edit details'), findsOneWidget);
    });

    testWidgets('orders tab lists lines with where to ship them and what the seller earns', (tester) async {
      await pumpSeller(tester, sellerApp(active()));
      await tapAndSettle(tester, nav('Orders'));

      expect(find.textContaining('ORD-AAA11111'), findsWidgets);
      expect(find.textContaining('Priya, Bengaluru, 560038'), findsOneWidget);
      expect(find.text('₹1,800.00'), findsWidgets);
      expect(find.textContaining('Pack each item'), findsOneWidget);
    });

    testWidgets('orders can be filtered by status', (tester) async {
      await pumpSeller(tester, sellerApp(active()));
      await tapAndSettle(tester, nav('Orders'));
      await tapAndSettle(tester, find.text('Delivered'));

      expect(find.text('Silk Scarf'), findsOneWidget);
      expect(find.text('Brass Lamp'), findsNothing);
    });

    testWidgets('an empty filter says so instead of showing a blank page', (tester) async {
      await pumpSeller(tester, sellerApp(active()));
      await tapAndSettle(tester, nav('Orders'));
      await tapAndSettle(tester, find.text('Cancelled'));

      expect(find.text('No orders here'), findsOneWidget);
    });

    testWidgets('products tab shows status and stock', (tester) async {
      await pumpSeller(tester, sellerApp(active()));
      await tapAndSettle(tester, nav('Products'));

      expect(find.text('Brass Lamp'), findsOneWidget);
      expect(find.text('12 in stock'), findsOneWidget);
      expect(find.text('Live'), findsWidgets);
      expect(find.text('Draft'), findsWidgets);
      expect(find.text('Add product'), findsOneWidget);
    });

    testWidgets('earnings tab shows the balance and each ledger entry with its sign', (tester) async {
      await pumpSeller(tester, sellerApp(active()));
      await tapAndSettle(tester, nav('Earnings'));

      expect(find.text('₹2,250.00'), findsOneWidget);
      expect(find.text('Sale'), findsOneWidget);
      expect(find.text('Refund'), findsOneWidget);
      expect(find.text('+₹1,800.00'), findsOneWidget);
      expect(find.text('−₹450.00'), findsOneWidget);
    });

    testWidgets('editing the shop details saves through the API', (tester) async {
      final api = active();
      await pumpSeller(tester, sellerApp(api));

      await tapAndSettle(tester, find.text('Edit details'));
      await tester.enterText(find.byType(TextField).at(0), 'Asha Crafts & Co');
      await tapAndSettle(tester, find.text('Save'));

      expect(api.calls, contains('updateProfile:Asha Crafts & Co'));
    });

    testWidgets('a shop with no pickup address is told delivery will use the warehouse', (tester) async {
      await pumpSeller(tester, sellerApp(active()));

      expect(find.text('Pickup address'), findsOneWidget);
      expect(find.textContaining('collected from the marketplace warehouse'), findsOneWidget);
      expect(find.text('Add pickup address'), findsOneWidget);
    });

    testWidgets('a shop with a pickup address shows it', (tester) async {
      final api = active()
        ..profile = const SellerProfile(
          id: 's1', displayName: 'Asha Crafts', commissionRate: 10,
          pickup: PickupAddress(line1: '12 Koramangala', city: 'Bengaluru', state: 'Karnataka', pincode: '560034', phone: '9811111111'),
        );
      await pumpSeller(tester, sellerApp(api));

      expect(find.text('12 Koramangala, Bengaluru, Karnataka 560034'), findsOneWidget);
      expect(find.text('Change pickup address'), findsOneWidget);
      expect(find.textContaining('collected from the marketplace warehouse'), findsNothing);
    });

    testWidgets('adding a pickup address saves it through the API', (tester) async {
      final api = active();
      await pumpSeller(tester, sellerApp(api));

      await tapAndSettle(tester, find.text('Add pickup address'));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '12 Koramangala');
      await tester.enterText(fields.at(1), 'Bengaluru');
      await tester.enterText(fields.at(2), 'Karnataka');
      await tester.enterText(fields.at(3), '560034');
      await tapAndSettle(tester, find.text('Save'));

      expect(api.calls, contains('pickup'));
      expect(api.savedPickup?.pincode, '560034');
      expect(api.savedPickup?.line1, '12 Koramangala');
    });

    testWidgets('a pickup address needs a street, a city and a real PIN', (tester) async {
      final api = active();
      await pumpSeller(tester, sellerApp(api));

      await tapAndSettle(tester, find.text('Add pickup address'));
      await tester.enterText(find.byType(TextField).at(3), '1234');
      await tapAndSettle(tester, find.text('Save'));

      expect(api.calls, isNot(contains('pickup')));
      expect(find.textContaining('street address'), findsOneWidget);
      expect(find.textContaining('PIN'), findsWidgets);
    });

    testWidgets('an empty shop shows friendly empty states rather than blank lists', (tester) async {
      final api = FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'));
      await pumpSeller(tester, sellerApp(api));

      expect(find.textContaining('No orders yet'), findsOneWidget);

      await tapAndSettle(tester, nav('Products'));
      expect(find.text('No products yet'), findsOneWidget);

      await tapAndSettle(tester, nav('Earnings'));
      expect(find.text('No earnings yet'), findsOneWidget);
    });
  });

  group('small screens', () {
    // 320 logical pixels wide is the narrowest phone still in use. Overflow is a
    // layout error that only shows up at real widths, so every screen is rendered
    // there and any exception fails the test.
    // A layout overflow fails the test on its own and Flutter prints exactly
    // which widget overflowed, so nothing here needs to assert on it.
    Future<void> pumpNarrow(WidgetTester tester, Widget app) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
    }

    testWidgets('the dashboard tabs do not overflow', (tester) async {
      final api = FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))
        ..orderRows = [
          const SellerOrderItem(
            id: 'i1', title: 'A rather long product title that will need to wrap onto a second line', variantLabel: 'Midnight Blue · XL',
            quantity: 12, price: 123456.5, earning: 111111.11, orderNumber: 'ORD-AAA11111', orderStatus: 'OUT_FOR_DELIVERY',
            shipToName: 'A Person With A Long Name', shipToCity: 'Thiruvananthapuram', shipToPincode: '695001',
          ),
        ]
        ..productRows = [
          const SellerProduct(id: 'p1', title: 'A rather long product title that will need to wrap', price: 123456.5, status: 'OUT_OF_STOCK', stock: 1234567, category: 'Home & Kitchen Appliances'),
        ]
        ..ledgerBalance = 9999999.99
        ..ledgerRows = [
          const LedgerEntry(id: 'l1', type: 'ADJUSTMENT', gross: 123456.5, commission: 12345.65, net: 111110.85, balanceAfter: 9999999.99, note: 'A long note explaining exactly why the marketplace adjusted this balance'),
        ];
      await pumpNarrow(tester, sellerApp(api));

      for (final tab in ['Orders', 'Products', 'Earnings']) {
        await tapAndSettle(tester, nav(tab));
      }
    });

    testWidgets('the application steps do not overflow', (tester) async {
      final api = FakeSellerApi(buildOnboarding(missingFields: allKycFields));
      await pumpNarrow(tester, sellerApp(api));

      for (final step in ['Address', 'Bank', 'Documents', 'Review']) {
        await tapAndSettle(tester, find.text(step));
      }
    });

    testWidgets('the apply and status screens do not overflow', (tester) async {
      await pumpNarrow(tester, sellerApp(FakeSellerApi(null)));

      await pumpNarrow(tester, sellerApp(FakeSellerApi(buildOnboarding(kyc: 'SUBMITTED'))));

      await pumpNarrow(tester, sellerApp(FakeSellerApi(buildOnboarding(seller: 'SUSPENDED', kyc: 'APPROVED'))));
    });
  });
}
