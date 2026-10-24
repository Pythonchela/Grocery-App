import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/seller/document_picker.dart';
import 'package:marketplace_app/seller/seller_models.dart';

import 'support.dart';

/// Adding and editing products from the seller's phone, one step at a time.
void main() {
  const lamp = SellerProduct(
    id: 'p1', title: 'Brass Lamp', price: 1000, mrp: 1200, status: 'ACTIVE', stock: 12,
    category: 'Home Decor', categoryId: 'c1', description: 'Hand finished.', brand: 'Asha Crafts',
    images: ['https://img.test/a.jpg', 'https://img.test/b.jpg'],
    variants: [SellerVariant(id: 'v1', color: 'Gold', size: 'M', sku: 'G-M', stock: 12)],
  );

  FakeSellerApi seller({List<SellerProduct> products = const []}) =>
      FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'))..productRows = products;

  PickedDocument photo([String name = 'lamp.png', int bytes = 2048]) => PickedDocument(name: name, bytes: List.filled(bytes, 1));

  Finder field(int i) => find.byType(TextField).at(i);
  Finder primary(String label) => find.widgetWithText(BxButton, label);

  Future<void> openProducts(WidgetTester tester, FakeSellerApi api, {FakePicker? picker}) async {
    await pumpSeller(tester, sellerApp(api, picker: picker));
    await tapAndSettle(tester, nav('Products'));
  }

  Future<void> openAddForm(WidgetTester tester, FakeSellerApi api, {FakePicker? picker}) async {
    await openProducts(tester, api, picker: picker);
    await tapAndSettle(tester, find.byType(FloatingActionButton));
  }

  Future<void> openEditForm(WidgetTester tester, FakeSellerApi api, {FakePicker? picker, String title = 'Brass Lamp'}) async {
    await openProducts(tester, api, picker: picker);
    await tapAndSettle(tester, find.text(title));
  }

  /// Jumps to a step by its chip: basics, photos, price, delivery, details, review.
  Future<void> jump(WidgetTester tester, String step) async {
    final chip = find.byKey(Key('step-$step'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) => tapAndSettle(tester, find.byKey(const Key('step-primary')));
  Future<void> saveDraft(WidgetTester tester) => tapAndSettle(tester, find.byKey(const Key('save-draft')));

  Future<void> chooseCategory(WidgetTester tester, String label) async {
    await tapAndSettle(tester, find.text('Choose a category'));
    await tapAndSettle(tester, find.text(label));
  }

  /// The basics step filled in: name and category.
  Future<void> fillBasics(WidgetTester tester, {String title = 'Silk Scarf'}) async {
    await tester.enterText(field(0), title);
    await chooseCategory(tester, 'Apparel');
  }

  /// The price step, one plain item: MRP, price, and how many there are.
  Future<void> fillPrice(WidgetTester tester, {String mrp = '1,999', String price = '1499.50', String stock = '7'}) async {
    await jump(tester, 'price');
    await tester.enterText(field(0), mrp);
    await tester.enterText(field(1), price);
    await tester.enterText(field(2), stock);
  }

  group('the products tab', () {
    testWidgets('lists products and offers to add one', (tester) async {
      await openProducts(tester, seller(products: [lamp]));

      expect(find.text('Brass Lamp'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('search narrows a growing product catalogue', (tester) async {
      await openProducts(tester, seller(products: [lamp,
        const SellerProduct(id: 'p2', title: 'Cotton Scarf', price: 500, status: 'ACTIVE', stock: 8),
      ]));
      await tester.enterText(find.byType(TextField).first, 'scarf');
      await tapAndSettle(tester, find.byTooltip('Search products'));

      expect(find.text('Cotton Scarf'), findsOneWidget);
      expect(find.text('Brass Lamp'), findsNothing);
    });

    testWidgets('an empty catalogue invites the first product', (tester) async {
      await openProducts(tester, seller());

      expect(find.text('No products yet'), findsOneWidget);
      expect(find.text('Add a product'), findsOneWidget);
    });

    testWidgets('a draft says "Continue", a live product says "Edit"', (tester) async {
      await openProducts(tester, seller(products: [
        lamp,
        const SellerProduct(id: 'p3', title: 'Half done', status: 'DRAFT', categoryId: 'c1', category: 'Home Decor'),
      ]));

      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });
  });

  group('the steps', () {
    testWidgets('a new product starts on step 1 of 6 with nothing to delete', (tester) async {
      await openAddForm(tester, seller());

      expect(find.text('Add product'), findsWidgets);
      expect(find.text('Step 1 of 6 · Basics'), findsOneWidget);
      expect(find.text('Choose a category'), findsOneWidget);
      expect(find.text('Delete product'), findsNothing);
      expect(find.byKey(const Key('step-back')), findsNothing, reason: 'nothing before the first step');
    });

    testWidgets('Next moves on and Back returns, and the chips jump anywhere', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);

      await next(tester);
      expect(find.text('Step 2 of 6 · Photos'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('step-back')));
      expect(find.text('Step 1 of 6 · Basics'), findsOneWidget);

      await jump(tester, 'review');
      expect(find.text('Step 6 of 6 · Review'), findsOneWidget);
    });

    testWidgets('Basics will not move on without a name and a category', (tester) async {
      final api = seller();
      await openAddForm(tester, api);

      await next(tester);

      expect(find.text('Enter a product name.'), findsOneWidget);
      expect(find.text('Choose a category.'), findsOneWidget);
      expect(find.textContaining('Fix the highlighted fields'), findsOneWidget);
      expect(find.text('Step 1 of 6 · Basics'), findsOneWidget);
      expect(api.calls, isNot(contains('createProduct')));
    });

    testWidgets('Price will not move on without prices and stock, and says what is wrong', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);
      await jump(tester, 'price');

      await next(tester);

      expect(find.text('Enter the MRP.'), findsOneWidget);
      expect(find.text('Enter the selling price.'), findsOneWidget);
      expect(find.text('Enter the stock.'), findsOneWidget);
      expect(find.text('Step 3 of 6 · Price & stock'), findsOneWidget);
    });

    testWidgets('a selling price above the MRP is refused', (tester) async {
      await openAddForm(tester, seller());
      await fillBasics(tester);
      await fillPrice(tester, price: '2500');

      await next(tester);

      expect(find.text('The selling price cannot be higher than the MRP.'), findsOneWidget);
    });

    testWidgets('the discount is shown as it is typed', (tester) async {
      await openAddForm(tester, seller());
      await fillBasics(tester);
      await fillPrice(tester, mrp: '2000', price: '1500');
      await tester.pumpAndSettle();

      expect(find.text('25% off'), findsOneWidget);
    });

    testWidgets('stock must be a whole number', (tester) async {
      await openAddForm(tester, seller());
      await fillBasics(tester);
      await fillPrice(tester, stock: '2.5');

      await next(tester);

      expect(find.text('Stock must be a whole number, 0 or more.'), findsOneWidget);
    });
  });

  group('saving as you go', () {
    testWidgets('Save draft needs only a name and a category, and keeps you where you are', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);

      await saveDraft(tester);

      final sent = api.lastProductInput!;
      expect(api.calls, contains('createProduct'));
      expect(sent.status, 'DRAFT');
      expect(sent.title, 'Silk Scarf');
      expect(sent.price, 0, reason: 'a draft may be saved before it has a price');
      expect(sent.variants.single.stock, 0, reason: 'no stock is invented');
      expect(find.textContaining('Draft saved'), findsOneWidget);
      expect(find.text('Step 1 of 6 · Basics'), findsOneWidget);
    });

    testWidgets('Save draft with no name is refused', (tester) async {
      final api = seller();
      await openAddForm(tester, api);

      await saveDraft(tester);

      expect(find.text('Enter a product name.'), findsOneWidget);
      expect(api.calls, isNot(contains('createProduct')));
    });

    testWidgets('moving on saves the draft quietly, so nothing typed is lost', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);

      await next(tester);
      await tester.pumpAndSettle();

      expect(api.calls.where((c) => c == 'createProduct'), hasLength(1));
      expect(api.lastProductInput!.status, 'DRAFT');
    });

    testWidgets('a second save edits the same product and its variants, instead of adding another', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);
      await saveDraft(tester);

      await tester.enterText(field(0), 'Silk Scarf Deluxe');
      await saveDraft(tester);

      expect(api.calls.where((c) => c == 'createProduct'), hasLength(1));
      expect(api.calls, contains('updateProduct:new-1'));
      expect(api.lastProductInput!.title, 'Silk Scarf Deluxe');
      expect(api.lastProductInput!.variants.single.id, 'new-1-v1', reason: 'the variant is edited in place');
      expect(api.productRows, hasLength(1));
    });

    testWidgets('leaving with something typed offers to keep it as a draft', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);

      await tapAndSettle(tester, find.byTooltip('Back'));
      expect(find.text('Save this as a draft?'), findsOneWidget);

      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save draft'));

      expect(api.productRows.single.status, 'DRAFT');
      expect(find.text('Silk Scarf'), findsOneWidget, reason: 'back on the list, with the draft in it');
    });

    testWidgets('"Discard" leaves without saving, and "Keep editing" stays', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);

      await tapAndSettle(tester, find.byTooltip('Back'));
      await tapAndSettle(tester, find.text('Keep editing'));
      expect(find.text('Step 1 of 6 · Basics'), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip('Back'));
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Discard'));

      expect(api.calls, isNot(contains('createProduct')));
      expect(find.text('No products yet'), findsOneWidget);
    });

    testWidgets('leaving an untouched form asks nothing', (tester) async {
      await openAddForm(tester, seller());

      await tapAndSettle(tester, find.byTooltip('Back'));

      expect(find.text('Save this as a draft?'), findsNothing);
      expect(find.text('No products yet'), findsOneWidget);
    });

    testWidgets('a saved draft is picked up where it was left', (tester) async {
      final api = seller(products: [
        const SellerProduct(id: 'd1', title: 'Half done', status: 'DRAFT', categoryId: 'c1', category: 'Home Decor'),
      ]);
      await openEditForm(tester, api, title: 'Half done');

      expect(find.text('Step 3 of 6 · Price & stock'), findsOneWidget, reason: 'the first thing still missing');
      expect(find.byKey(const Key('save-draft')), findsOneWidget);
    });
  });

  group('going live', () {
    testWidgets('the whole way through: fill in, publish, and it appears in the list', (tester) async {
      final api = seller();
      final picker = FakePicker(photo());
      await openAddForm(tester, api, picker: picker);

      await fillBasics(tester);
      await next(tester);
      await tapAndSettle(tester, find.text('Add').first);
      await next(tester);
      await tester.enterText(field(0), '1,999');
      await tester.enterText(field(1), '1499.50');
      await tester.enterText(field(2), '7');
      await next(tester);
      await next(tester);
      await next(tester);

      expect(find.text('Step 6 of 6 · Review'), findsOneWidget);
      expect(find.text('Ready to go live'), findsOneWidget);

      await tapAndSettle(tester, primary('Publish product'));

      final sent = api.lastProductInput!;
      expect(sent.status, 'ACTIVE');
      expect(sent.title, 'Silk Scarf');
      expect(sent.categoryId, 'c2');
      expect(sent.mrp, 1999.0, reason: 'thousands separators are understood');
      expect(sent.price, 1499.5);
      expect(sent.images, ['https://img.test/1-lamp.png']);
      expect(sent.variants.single.stock, 7);
      expect(find.text('Silk Scarf'), findsOneWidget);
      expect(api.productRows.single.status, 'ACTIVE');
      expect(api.productRows, hasLength(1), reason: 'the draft saved on the way became the live product');
    });

    testWidgets('the review lists what is still needed, and tapping it goes there', (tester) async {
      await openAddForm(tester, seller());
      await fillBasics(tester);
      await jump(tester, 'review');

      expect(find.text('Still needed to go live'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('check-At-least-one-photo')));

      expect(find.text('Step 2 of 6 · Photos'), findsOneWidget);
    });

    testWidgets('going live needs at least one photo', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);
      await fillPrice(tester);
      await jump(tester, 'review');

      await tapAndSettle(tester, primary('Publish product'));

      expect(find.text('Add at least one photo before making this product live.'), findsOneWidget);
      expect(find.text('Step 2 of 6 · Photos'), findsOneWidget, reason: 'taken to the step that needs it');
      expect(api.productRows.where((p) => p.status == 'ACTIVE'), isEmpty);
    });

    testWidgets('going live needs a price', (tester) async {
      final api = seller();
      await openAddForm(tester, api, picker: FakePicker(photo()));
      await fillBasics(tester);
      await jump(tester, 'photos');
      await tapAndSettle(tester, find.text('Add').first);
      await jump(tester, 'review');

      await tapAndSettle(tester, primary('Publish product'));

      expect(find.text('Enter the MRP.'), findsOneWidget);
      expect(find.text('Step 3 of 6 · Price & stock'), findsOneWidget);
    });
  });

  group('photos', () {
    testWidgets('a photo is uploaded straight away and the first one is the cover', (tester) async {
      final api = seller();
      final picker = FakePicker(photo());
      await openAddForm(tester, api, picker: picker);
      await jump(tester, 'photos');

      await tapAndSettle(tester, find.text('Add').first);

      expect(api.calls, contains('uploadImage:lamp.png'));
      expect(picker.lastExtensions, PhotoRules.allowedExtensions, reason: 'photos only, no PDFs');
      expect(find.text('Cover'), findsOneWidget);
    });

    testWidgets('a photo can be removed', (tester) async {
      final api = seller(products: [lamp]);
      await openEditForm(tester, api);
      await jump(tester, 'photos');
      expect(find.text('Cover'), findsOneWidget);

      await tapAndSettle(tester, find.byIcon(Icons.close).first);
      await jump(tester, 'review');
      await tapAndSettle(tester, primary('Save changes'));

      expect(api.lastProductInput!.images, ['https://img.test/b.jpg']);
    });

    testWidgets('a photo of the wrong type is refused before it is uploaded', (tester) async {
      final api = seller();
      await openAddForm(tester, api, picker: FakePicker(photo('doc.pdf')));
      await jump(tester, 'photos');

      await tapAndSettle(tester, find.text('Add').first);

      expect(find.text('Use a JPG, PNG or WebP photo.'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('uploadImage')), isEmpty);
    });

    testWidgets('a photo over 10 MB is refused before it is uploaded', (tester) async {
      final api = seller();
      await openAddForm(tester, api, picker: FakePicker(photo('big.jpg', PhotoRules.maxBytes + 1)));
      await jump(tester, 'photos');

      await tapAndSettle(tester, find.text('Add').first);

      expect(find.textContaining('over 10 MB'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('uploadImage')), isEmpty);
    });

    testWidgets('a failed upload says so and adds nothing', (tester) async {
      final api = seller()..uploadError = ApiException(422, 'The file failed to upload.', errors: {'file': ['The file must be an image.']});
      await openAddForm(tester, api, picker: FakePicker(photo()));
      await jump(tester, 'photos');

      await tapAndSettle(tester, find.text('Add').first);

      expect(find.text('The file must be an image.'), findsOneWidget);
      expect(find.text('Cover'), findsNothing);
    });

    testWidgets('backing out of the picker is not an error', (tester) async {
      final api = seller();
      await openAddForm(tester, api, picker: FakePicker(null));
      await jump(tester, 'photos');

      await tapAndSettle(tester, find.text('Add').first);

      expect(api.calls.where((c) => c.startsWith('uploadImage')), isEmpty);
      expect(find.text('Cover'), findsNothing);
    });
  });

  group('variants', () {
    testWidgets('a plain item has one stock figure and no variant cards', (tester) async {
      await openAddForm(tester, seller());
      await jump(tester, 'price');

      expect(find.text('How many do you have?'), findsOneWidget);
      expect(find.text('Variant 1'), findsNothing);
    });

    testWidgets('switching on sizes or colours shows variant cards, which can be added and removed', (tester) async {
      await openAddForm(tester, seller());
      await jump(tester, 'price');

      await tapAndSettle(tester, find.byKey(const Key('has-variants')));
      expect(find.text('Variant 1'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing, reason: 'the only variant cannot be removed');

      await tapAndSettle(tester, find.text('Add a variant'));
      expect(find.text('Variant 2'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

      await tapAndSettle(tester, find.byTooltip('Remove variant 2'));
      expect(find.text('Variant 2'), findsNothing);
    });

    testWidgets('two variants cannot share a SKU', (tester) async {
      await openAddForm(tester, seller());
      await fillBasics(tester);
      await jump(tester, 'price');
      await tapAndSettle(tester, find.byKey(const Key('has-variants')));
      await tester.enterText(field(0), '1999');
      await tester.enterText(field(1), '1499');
      // Each variant card: colour, size, stock, SKU, price, MRP.
      await tester.enterText(field(4), '5');
      await tester.enterText(field(5), 'SAME');
      await tapAndSettle(tester, find.text('Add a variant'));
      await tester.enterText(field(10), '5');
      await tester.enterText(field(11), 'same');

      await next(tester);

      expect(find.text('This SKU is used by another variant here.'), findsOneWidget);
    });

    testWidgets('editing keeps each existing variant\'s id, so past orders stay attached', (tester) async {
      final api = seller(products: [
        const SellerProduct(
          id: 'p2', title: 'Two Sizes', price: 500, mrp: 600, status: 'ACTIVE', categoryId: 'c1', images: ['https://img.test/x.jpg'],
          variants: [
            SellerVariant(id: 'vA', size: 'S', stock: 3),
            SellerVariant(id: 'vB', size: 'L', stock: 4),
          ],
        ),
      ]);
      await openEditForm(tester, api, title: 'Two Sizes');
      await jump(tester, 'price');

      // colour, size, stock, ... for the first variant: stock is the 3rd after MRP and price.
      await tester.enterText(field(4), '30');
      await jump(tester, 'review');
      await tapAndSettle(tester, primary('Save changes'));

      final variants = api.lastProductInput!.variants;
      expect(variants.map((v) => v.id), ['vA', 'vB']);
      expect(variants.map((v) => v.stock), [30, 4]);
    });
  });

  group('delivery', () {
    testWidgets('the step says why weight and size matter', (tester) async {
      await openAddForm(tester, seller());
      await jump(tester, 'delivery');

      expect(find.textContaining('Without a weight we assume 500 g'), findsOneWidget);
      expect(find.text('Weight (grams)'), findsOneWidget);
    });

    testWidgets('what is typed and chosen is sent with the product', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);
      await jump(tester, 'delivery');

      await tester.enterText(field(0), '750');
      await tester.enterText(field(1), '30');
      await tester.enterText(field(2), '20');
      await tester.enterText(field(3), '15');
      await tester.enterText(field(4), '25');
      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Courier parcel'));
      await tapAndSettle(tester, find.byType(Switch));
      await saveDraft(tester);

      final sent = api.lastProductInput!;
      expect([sent.weightGrams, sent.lengthCm, sent.widthCm, sent.heightCm], [750, 30, 20, 15]);
      expect(sent.prepMinutes, 25);
      expect(sent.deliveryProfile, 'parcel');
      expect(sent.codAvailable, isFalse);
      expect(sent.toJson()['delivery_profile'], 'parcel');
      expect(sent.toJson()['cod_available'], false);
    });

    testWidgets('left empty they go as nothing, so the defaults apply', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);
      await saveDraft(tester);

      final json = api.lastProductInput!.toJson();
      expect(json['weight_grams'], isNull);
      expect(json['prep_minutes'], isNull);
      expect(json['delivery_profile'], isNull);
      expect(json['cod_available'], true);
    });

    testWidgets('editing opens with what is saved', (tester) async {
      final api = seller(products: [
        const SellerProduct(
          id: 'p1', title: 'Brass Lamp', price: 1000, mrp: 1200, status: 'ACTIVE', stock: 12,
          category: 'Home Decor', categoryId: 'c1', brand: 'Asha Crafts',
          images: ['https://img.test/a.jpg'],
          variants: [SellerVariant(id: 'v1', color: 'Gold', size: 'M', sku: 'G-M', stock: 12)],
          weightGrams: 1200, lengthCm: 30, widthCm: 20, heightCm: 15, prepMinutes: 40, deliveryProfile: 'heavy',
        ),
      ]);
      await openEditForm(tester, api);
      await jump(tester, 'delivery');

      expect((tester.widget<TextField>(field(0)).controller!).text, '1200');
      expect((tester.widget<TextField>(field(3)).controller!).text, '15');
      expect((tester.widget<TextField>(field(4)).controller!).text, '40');
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Heavy or bulky')).selected, isTrue);
    });

    testWidgets('a figure that is not a sensible whole number is caught before anything is sent', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);
      await jump(tester, 'delivery');

      await tester.enterText(field(0), '0');
      await tester.enterText(field(1), '9999');
      await tester.enterText(field(2), '2.5');
      await next(tester);

      expect(find.textContaining('whole number from 1 to 200000'), findsOneWidget);
      expect(find.textContaining('whole number from 1 to 500'), findsNWidgets(2));
      expect(find.text('Step 4 of 6 · Delivery'), findsOneWidget, reason: 'stays until it is fixed');
    });
  });

  group('details, specifications and manufacturer info', () {
    testWidgets('a new product offers them all, empty and optional', (tester) async {
      await openAddForm(tester, seller());
      await jump(tester, 'details');

      expect(find.text('Highlights'), findsOneWidget);
      expect(find.text('Specifications'), findsOneWidget);
      expect(find.text('Add specifications'), findsOneWidget);
      expect(find.text('Manufacturer info'), findsOneWidget);
      expect(find.text('Country of origin'), findsOneWidget);
      expect(find.textContaining('set from the web dashboard'), findsOneWidget);
    });

    testWidgets('highlights, rows and manufacturer info typed in are sent with the product', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);
      await jump(tester, 'details');

      await tapAndSettle(tester, find.text('Add a highlight'));
      await tester.enterText(field(0), 'Pure silk');
      await tapAndSettle(tester, find.text('Add specifications'));
      // Highlight (0), then the section title (1), a row's name (2) and value (3), then manufacturer.
      expect((tester.widget<TextField>(field(1)).controller!).text, 'General', reason: 'the first section is named for them');
      await tester.enterText(field(2), 'Fabric');
      await tester.enterText(field(3), 'Silk');
      await tester.enterText(field(4), 'Scarf');
      await tester.enterText(field(5), 'India');
      await saveDraft(tester);

      final sent = api.lastProductInput!;
      expect(sent.features, ['Pure silk']);
      expect(sent.specifications, [
        {'title': 'General', 'rows': [{'label': 'Fabric', 'value': 'Silk'}]},
      ]);
      expect(sent.manufacturer['generic_name'], 'Scarf');
      expect(sent.manufacturer['country_of_origin'], 'India');
    });

    testWidgets('a product with none of it sends nothing for it', (tester) async {
      final api = seller();
      await openAddForm(tester, api);
      await fillBasics(tester);
      await saveDraft(tester);

      expect(api.lastProductInput!.specifications, isEmpty);
      expect(api.lastProductInput!.features, isEmpty);
      expect(api.lastProductInput!.manufacturer.values.every((v) => v.isEmpty), isTrue);
    });

    testWidgets('editing opens with what is saved, and rows can be removed', (tester) async {
      final api = seller(products: [
        const SellerProduct(
          id: 'p1', title: 'Brass Lamp', price: 1000, mrp: 1200, status: 'ACTIVE', stock: 12,
          category: 'Home Decor', categoryId: 'c1', description: 'Hand finished.', brand: 'Asha Crafts',
          images: ['https://img.test/a.jpg'],
          variants: [SellerVariant(id: 'v1', color: 'Gold', size: 'M', sku: 'G-M', stock: 12)],
          specifications: [
            SellerSpecGroup('General', [SellerSpecRow('Material', 'Brass'), SellerSpecRow('Finish', 'Matte')]),
          ],
          manufacturer: {'generic_name': 'Lamp', 'country_of_origin': 'India'},
          features: ['Pure brass'],
        ),
      ]);
      await openEditForm(tester, api);
      await jump(tester, 'details');

      expect(find.widgetWithText(TextField, 'Pure brass'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Brass'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Matte'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Lamp'), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip('Remove row').first);
      expect(find.widgetWithText(TextField, 'Brass'), findsNothing);

      await jump(tester, 'review');
      await tapAndSettle(tester, primary('Save changes'));
      expect(api.lastProductInput!.specifications.single['rows'], [
        {'label': 'Finish', 'value': 'Matte'},
      ]);
    });

    testWidgets('a whole section can be removed', (tester) async {
      final api = seller(products: [
        const SellerProduct(
          id: 'p1', title: 'Brass Lamp', price: 1000, mrp: 1200, status: 'ACTIVE', stock: 12,
          category: 'Home Decor', categoryId: 'c1', brand: 'Asha Crafts',
          variants: [SellerVariant(id: 'v1', color: 'Gold', size: 'M', sku: 'G-M', stock: 12)],
          images: ['https://img.test/a.jpg'],
          specifications: [SellerSpecGroup('General', [SellerSpecRow('Material', 'Brass')])],
        ),
      ]);
      await openEditForm(tester, api);
      await jump(tester, 'details');

      await tapAndSettle(tester, find.byTooltip('Remove this section'));
      expect(find.text('Add specifications'), findsOneWidget);

      await jump(tester, 'review');
      await tapAndSettle(tester, primary('Save changes'));
      expect(api.lastProductInput!.specifications, isEmpty, reason: 'saving clears the table on the server too');
    });

    testWidgets('a description written with formatting says plain text replaces it', (tester) async {
      final api = seller(products: [
        const SellerProduct(
          id: 'p1', title: 'Brass Lamp', price: 1000, mrp: 1200, status: 'ACTIVE', stock: 12,
          category: 'Home Decor', categoryId: 'c1', description: 'Hand finished.', brand: 'Asha Crafts',
          images: ['https://img.test/a.jpg'],
          variants: [SellerVariant(id: 'v1', color: 'Gold', size: 'M', sku: 'G-M', stock: 12)],
          hasFormattedDescription: true,
        ),
      ]);
      await openEditForm(tester, api);
      await jump(tester, 'basics');

      expect(find.textContaining('has formatting'), findsOneWidget);
    });
  });

  group('editing a live product', () {
    testWidgets('opens on the review, with Save changes and no draft or publish buttons', (tester) async {
      await openEditForm(tester, seller(products: [lamp]));

      expect(find.text('Edit product'), findsOneWidget);
      expect(find.text('Step 6 of 6 · Review'), findsOneWidget);
      expect(primary('Save changes'), findsOneWidget);
      expect(find.byKey(const Key('save-draft')), findsNothing, reason: 'a live product is not turned back into a draft by accident');
      expect(primary('Publish product'), findsNothing);
      expect(find.text('Delete product'), findsOneWidget);
    });

    testWidgets('its steps open filled in with the product\'s details', (tester) async {
      await openEditForm(tester, seller(products: [lamp]));

      await jump(tester, 'basics');
      expect((tester.widget<TextField>(field(0)).controller!).text, 'Brass Lamp');
      expect(find.text('Home Decor'), findsOneWidget);

      await jump(tester, 'price');
      expect((tester.widget<TextField>(field(0)).controller!).text, '1200');
      expect((tester.widget<TextField>(field(1)).controller!).text, '1000');
      expect((tester.widget<TextField>(field(2)).controller!).text, 'Gold');
      expect((tester.widget<TextField>(field(4)).controller!).text, '12');
    });

    testWidgets('saving sends the change to the right product and returns to the list', (tester) async {
      final api = seller(products: [lamp]);
      await openEditForm(tester, api);

      await jump(tester, 'price');
      await tester.enterText(field(1), '899');
      await jump(tester, 'review');
      await tapAndSettle(tester, primary('Save changes'));

      expect(api.calls, contains('updateProduct:p1'));
      expect(api.lastProductInput!.price, 899.0);
      expect(api.lastProductInput!.variants.single.id, 'v1');
      expect(find.text('Brass Lamp'), findsOneWidget);
    });

    testWidgets('the status can be changed, including discontinuing', (tester) async {
      final api = seller(products: [lamp]);
      await openEditForm(tester, api);

      await tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Discontinued'));
      await tapAndSettle(tester, primary('Save changes'));

      expect(api.lastProductInput!.status, 'DISCONTINUED');
    });

    testWidgets('leaving with unsaved changes asks, and does not offer a draft', (tester) async {
      final api = seller(products: [lamp]);
      await openEditForm(tester, api);
      await jump(tester, 'basics');
      await tester.enterText(field(0), 'Brass Lamp v2');

      await tapAndSettle(tester, find.byTooltip('Back'));

      expect(find.text('Discard your changes?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save draft'), findsNothing);
      await tapAndSettle(tester, find.text('Discard changes'));
      expect(api.calls, isNot(contains('updateProduct:p1')));
    });
  });

  group('when the server disagrees', () {
    testWidgets('its field errors appear under the fields they belong to, on the right step', (tester) async {
      final api = seller(products: [lamp])
        ..productError = ApiException(422, 'invalid', errors: {
          'variants.0.sku': ['The sku has already been taken.'],
          'title': ['That name is not allowed.'],
        });
      await openEditForm(tester, api);

      await tapAndSettle(tester, primary('Save changes'));

      expect(find.textContaining('Fix the highlighted fields'), findsOneWidget);
      expect(find.text('Edit product'), findsOneWidget, reason: 'stays on the form');
      // The first error is the SKU, which lives on the price step.
      expect(find.text('Step 3 of 6 · Price & stock'), findsOneWidget);
      expect(find.text('The sku has already been taken.'), findsOneWidget);

      await jump(tester, 'basics');
      expect(find.text('That name is not allowed.'), findsOneWidget);
    });

    testWidgets('a general failure is shown as a banner', (tester) async {
      final api = seller()..productError = ApiException(500, 'The server had a problem.');
      await openAddForm(tester, api);
      await fillBasics(tester);

      await saveDraft(tester);

      expect(find.text('The server had a problem.'), findsOneWidget);
    });

    testWidgets('a draft that cannot be saved while moving on keeps what was typed and does not block', (tester) async {
      final api = seller()..productError = ApiException(500, 'The server had a problem.');
      await openAddForm(tester, api);
      await fillBasics(tester);

      await next(tester);

      expect(find.text('Step 2 of 6 · Photos'), findsOneWidget);
      expect(find.textContaining('Could not save the draft yet'), findsOneWidget);
    });
  });

  group('removing', () {
    testWidgets('deleting asks first, then removes the product', (tester) async {
      final api = seller(products: [lamp]);
      await openEditForm(tester, api);

      await tapAndSettle(tester, find.text('Delete product'));
      expect(find.text('Delete this product?'), findsOneWidget);
      expect(api.calls, isNot(contains('deleteProduct:p1')));

      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete'));

      expect(api.calls, contains('deleteProduct:p1'));
      expect(find.text('Brass Lamp'), findsNothing);
      expect(find.text('No products yet'), findsOneWidget);
    });

    testWidgets('"Keep it" deletes nothing', (tester) async {
      final api = seller(products: [lamp]);
      await openEditForm(tester, api);

      await tapAndSettle(tester, find.text('Delete product'));
      await tapAndSettle(tester, find.text('Keep it'));

      expect(api.calls, isNot(contains('deleteProduct:p1')));
      expect(find.text('Edit product'), findsOneWidget);
    });

    testWidgets('a product that has been ordered offers to discontinue instead', (tester) async {
      final api = seller(products: [lamp])
        ..deleteError = ApiException(422, 'This product has been ordered before, so it cannot be deleted. Set its status to DISCONTINUED to remove it from the store.');
      await openEditForm(tester, api);

      await tapAndSettle(tester, find.text('Delete product'));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete'));

      expect(find.text('This product has been ordered'), findsOneWidget);
      expect(find.textContaining('Discontinue it instead?'), findsOneWidget);

      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Discontinue'));

      expect(api.calls, contains('setStatus:p1:DISCONTINUED'));
      expect(find.text('Edit product'), findsNothing, reason: 'returned to the list');
    });

    testWidgets('declining to discontinue leaves the product alone', (tester) async {
      final api = seller(products: [lamp])..deleteError = ApiException(422, 'ordered before');
      await openEditForm(tester, api);

      await tapAndSettle(tester, find.text('Delete product'));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete'));
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Cancel'));

      expect(api.calls.where((c) => c.startsWith('setStatus')), isEmpty);
    });
  });

  group('categories', () {
    testWidgets('a failure to load them can be retried', (tester) async {
      final api = seller()..categoriesError = ApiException(500, 'Could not load categories from the server.');
      await openAddForm(tester, api);

      expect(find.text('Could not load categories from the server.'), findsOneWidget);

      await tapAndSettle(tester, find.text('Retry'));

      expect(find.text('Could not load categories from the server.'), findsNothing);
      await tapAndSettle(tester, find.text('Choose a category'));
      expect(find.text('Home Decor'), findsOneWidget);
    });
  });

  group('small screens', () {
    testWidgets('no step of the product form overflows at 320px', (tester) async {
      final api = seller(products: [lamp]);
      tester.view.physicalSize = const Size(320, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(sellerApp(api));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, nav('Products'));
      await tapAndSettle(tester, find.text('Brass Lamp'));

      for (final step in ['basics', 'photos', 'price', 'delivery', 'details', 'review']) {
        await jump(tester, step);
      }
      await jump(tester, 'price');
      await tapAndSettle(tester, find.text('Add a variant'));
    });

    testWidgets('a product card with a long title and wide status does not overflow at 320px', (tester) async {
      final api = seller(products: [
        const SellerProduct(id: 'p9', title: 'A remarkably long product title that will need to wrap over a couple of lines', price: 123456.5, status: 'OUT_OF_STOCK', stock: 1234567, category: 'Home & Kitchen Appliances'),
      ]);
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(sellerApp(api));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, nav('Products'));
    });
  });
}
