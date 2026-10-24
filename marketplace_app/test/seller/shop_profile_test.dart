import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/seller/document_picker.dart';
import 'package:marketplace_app/seller/seller_models.dart';

import 'support.dart';

/// The seller's shop page: what shoppers see when they browse shops, when the
/// shop is open, and what it asks of an order.
void main() {
  FakeSellerApi seller({ShopProfile shop = const ShopProfile()}) =>
      FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))
        ..profile = SellerProfile(id: 's1', displayName: 'Asha Crafts', commissionRate: 10, shop: shop);

  Future<void> openShopPage(WidgetTester tester, FakeSellerApi api, {FakePicker? picker}) async {
    await pumpSeller(tester, sellerApp(api, picker: picker));
    await tapAndSettle(tester, find.text('Edit shop page'));
  }

  Finder save() => find.widgetWithText(BxButton, 'Save shop page');

  group('what the server sends', () {
    test('reads the shop page fields', () {
      final p = ShopProfile.fromJson({
        'logo_url': 'https://x/logo.png', 'tagline': 'Fresh', 'about': 'Family run.',
        'accepting_orders': false, 'min_order_amount': 199, 'prep_minutes': 25,
        'service_pincodes': ['560038', '560034'], 'is_open': false, 'closed_text': 'Opens tomorrow at 9:00 AM',
        'opening_hours': {'mon': {'open': '09:00', 'close': '21:00'}, 'tue': null},
      });

      expect(p.logoUrl, 'https://x/logo.png');
      expect(p.acceptingOrders, isFalse);
      expect(p.minOrderAmount, 199);
      expect(p.prepMinutes, 25);
      expect(p.servicePincodes, ['560038', '560034']);
      expect(p.isOpen, isFalse);
      expect(p.openingHours!['mon'], const HoursSlot('09:00', '21:00'));
      expect(p.openingHours!['tue'], isNull);
      expect(p.openingHours!['sun'], isNull, reason: 'a day not listed is closed');
    });

    test('no hours means always open', () {
      expect(ShopProfile.fromJson({}).openingHours, isNull);
      expect(ShopProfile.fromJson({'opening_hours': {}}).openingHours, isNull);
      expect(ShopProfile.fromJson({}).acceptingOrders, isTrue);
    });

    test('is sent as the server expects, with "always open" as an empty list', () {
      final json = const ShopProfile(tagline: ' Fresh ', minOrderAmount: 100, servicePincodes: ['560038']).toJson();

      expect(json['tagline'], 'Fresh');
      expect(json['opening_hours'], isEmpty);
      expect(json['about'], isNull, reason: 'empty clears it');
      expect(json['min_order_amount'], 100);
      expect(json['service_pincodes'], ['560038']);
    });

    test('hours are sent day by day, a closed day as null', () {
      final json = ShopProfile(openingHours: {
        for (final d in ShopProfile.days) d: d == 'sun' ? null : const HoursSlot('09:00', '21:00'),
      }).toJson();

      expect((json['opening_hours'] as Map)['mon'], {'open': '09:00', 'close': '21:00'});
      expect((json['opening_hours'] as Map)['sun'], isNull);
    });
  });

  group('the overview card', () {
    testWidgets('says whether the shop is taking orders', (tester) async {
      await pumpSeller(tester, sellerApp(seller()));

      expect(find.text('Shop page'), findsOneWidget);
      expect(find.text('Taking orders'), findsOneWidget);
      expect(find.text('Open now'), findsOneWidget);
    });

    testWidgets('says when it is closed, and when it opens', (tester) async {
      await pumpSeller(tester, sellerApp(seller(shop: const ShopProfile(isOpen: false, closedText: 'Opens tomorrow at 9:00 AM'))));

      expect(find.text('Opens tomorrow at 9:00 AM'), findsOneWidget);
    });

    testWidgets('pausing is one tap and saves straight away', (tester) async {
      final api = seller();
      await pumpSeller(tester, sellerApp(api));

      await tapAndSettle(tester, find.byType(SwitchListTile).first);

      expect(api.calls, contains('updateShop'));
      expect(api.lastShop!.acceptingOrders, isFalse);
    });

    testWidgets('shows the minimum order and how many PIN codes it covers', (tester) async {
      await pumpSeller(tester, sellerApp(seller(shop: const ShopProfile(minOrderAmount: 149, servicePincodes: ['560038', '560034']))));

      expect(find.text('₹149'), findsOneWidget);
      expect(find.text('2 PIN codes'), findsOneWidget);
    });
  });

  group('the shop page', () {
    testWidgets('opens filled in with what is saved', (tester) async {
      final api = seller(
        shop: const ShopProfile(tagline: 'Fresh', about: 'Family run.', minOrderAmount: 149, prepMinutes: 20, servicePincodes: ['560038', '560034']),
      );
      await openShopPage(tester, api);

      expect(find.widgetWithText(TextField, 'Fresh'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Family run.'), findsOneWidget);
      expect(find.widgetWithText(TextField, '149'), findsOneWidget);
      expect(find.widgetWithText(TextField, '20'), findsOneWidget);
      expect(find.widgetWithText(TextField, '560038\n560034'), findsOneWidget);
    });

    testWidgets('saves what was typed', (tester) async {
      final api = seller();
      await openShopPage(tester, api);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Fresh every morning');   // tagline
      await tester.enterText(fields.at(1), 'Family run since 1990.'); // about
      await tester.enterText(fields.at(2), '199');                   // minimum
      await tester.enterText(fields.at(3), '25');                    // ready in
      await tester.enterText(fields.at(4), '560038, 560034\n560038'); // PIN codes
      await tapAndSettle(tester, save());

      final sent = api.lastShop!;
      expect(sent.tagline, 'Fresh every morning');
      expect(sent.about, 'Family run since 1990.');
      expect(sent.minOrderAmount, 199);
      expect(sent.prepMinutes, 25);
      expect(sent.servicePincodes, ['560038', '560034'], reason: 'split and de-duplicated');
      expect(sent.openingHours, isNull, reason: 'untouched: still always open');
    });

    testWidgets('pausing from here is saved too', (tester) async {
      final api = seller();
      await openShopPage(tester, api);

      await tapAndSettle(tester, find.widgetWithText(SwitchListTile, 'Taking orders'));
      await tapAndSettle(tester, save());

      expect(api.lastShop!.acceptingOrders, isFalse);
    });

    testWidgets('bad PIN codes, a bad minimum and a bad prep time are caught before anything is sent', (tester) async {
      final api = seller();
      await openShopPage(tester, api);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), 'lots');
      await tester.enterText(fields.at(3), '5000');
      await tester.enterText(fields.at(4), '12345');
      await tapAndSettle(tester, save());

      expect(find.textContaining('Enter an amount in rupees'), findsOneWidget);
      expect(find.textContaining('up to 1440'), findsOneWidget);
      expect(find.textContaining('six digits'), findsOneWidget);
      expect(api.calls, isNot(contains('updateShop')));
    });

    testWidgets('a server refusal is shown and nothing is lost', (tester) async {
      final api = seller()..shopError = ApiException(422, 'x', errors: {'min_order_amount': ['The minimum order is too high.']});
      await openShopPage(tester, api);

      await tester.enterText(find.byType(TextField).at(2), '99');
      await tapAndSettle(tester, save());

      expect(find.text('The minimum order is too high.'), findsOneWidget);
      expect(find.text('Save shop page'), findsOneWidget, reason: 'still on the page');
    });
  });

  group('opening hours', () {
    testWidgets('start as always open, with no days to set', (tester) async {
      await openShopPage(tester, seller());

      expect(find.text('Always open'), findsOneWidget);
      expect(find.text('Monday'), findsNothing);
    });

    testWidgets('turning that off lets each day be set, and they are saved', (tester) async {
      final api = seller();
      await openShopPage(tester, api);

      await tapAndSettle(tester, find.widgetWithText(SwitchListTile, 'Always open'));
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);

      // Close Sunday.
      final sundaySwitch = find.descendant(
        of: find.ancestor(of: find.text('Sunday'), matching: find.byType(Column)).first,
        matching: find.byType(Switch),
      );
      await tapAndSettle(tester, sundaySwitch.first);
      await tapAndSettle(tester, save());

      final hours = api.lastShop!.openingHours!;
      expect(hours['mon'], const HoursSlot('09:00', '21:00'));
      expect(hours['sun'], isNull);
      expect(hours.keys, ShopProfile.days);
    });

    testWidgets('an opening time can be changed', (tester) async {
      final api = seller(shop: ShopProfile(openingHours: {
        for (final d in ShopProfile.days) d: const HoursSlot('09:00', '21:00'),
      }));
      await openShopPage(tester, api);

      await tester.ensureVisible(find.text('Monday'));
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('8:00 AM').last);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, save());

      expect(api.lastShop!.openingHours!['mon'], const HoursSlot('08:00', '21:00'));
    });

    testWidgets('a day that opens and closes at the same moment is caught', (tester) async {
      final api = seller(shop: ShopProfile(openingHours: {
        for (final d in ShopProfile.days) d: const HoursSlot('09:00', '09:00'),
      }));
      await openShopPage(tester, api);

      await tapAndSettle(tester, save());

      expect(find.textContaining('opens and closes at the same time'), findsOneWidget);
      expect(api.calls, isNot(contains('updateShop')));
    });

    testWidgets('a time the shop already has off the half hour is kept', (tester) async {
      final api = seller(shop: ShopProfile(openingHours: {
        for (final d in ShopProfile.days) d: const HoursSlot('09:15', '21:00'),
      }));
      await openShopPage(tester, api);

      expect(find.text('9:15 AM'), findsWidgets);
      await tapAndSettle(tester, save());

      expect(api.lastShop!.openingHours!['mon']!.open, '09:15');
    });
  });

  group('pictures', () {
    PickedDocument photo([String name = 'logo.png', int bytes = 2048]) => PickedDocument(name: name, bytes: List.filled(bytes, 1));

    testWidgets('a logo is uploaded and saved with the page', (tester) async {
      final api = seller();
      final picker = FakePicker(photo());
      await openShopPage(tester, api, picker: picker);

      await tapAndSettle(tester, find.widgetWithText(BxButton, 'Add').first);
      expect(api.calls, contains('uploadImage:logo.png'));
      await tapAndSettle(tester, save());

      expect(api.lastShop!.logoUrl, startsWith('https://img.test/'));
      expect(api.lastShop!.bannerUrl, isNull);
    });

    testWidgets('a file that is not a picture is refused with no upload', (tester) async {
      final api = seller();
      final picker = FakePicker(photo('notes.txt'));
      await openShopPage(tester, api, picker: picker);

      await tapAndSettle(tester, find.widgetWithText(BxButton, 'Add').first);

      expect(api.calls.where((c) => c.startsWith('uploadImage')), isEmpty);
    });

    testWidgets('a picture can be taken off', (tester) async {
      final api = seller(shop: const ShopProfile(logoUrl: 'https://img.test/old.png'));
      await openShopPage(tester, api);

      await tapAndSettle(tester, find.text('Remove'));
      await tapAndSettle(tester, save());

      expect(api.lastShop!.logoUrl, isNull);
    });
  });
}
