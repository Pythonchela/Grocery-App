import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/seller/document_picker.dart';
import 'package:marketplace_app/seller/product_validation.dart';
import 'package:marketplace_app/seller/screens/variant_row.dart';
import 'package:marketplace_app/seller/seller_models.dart';

void main() {
  Map<String, String> check({
    String title = 'Brass Lamp',
    String? category = 'c1',
    String mrp = '1200',
    String price = '1000',
    String status = 'DRAFT',
    int photos = 0,
    List<VariantDraft> variants = const [VariantDraft(stock: '5')],
  }) =>
      ProductValidation.validate(
        title: title, categoryId: category, mrp: mrp, price: price, status: status, photoCount: photos, variants: variants,
      );

  group('product validation', () {
    test('a complete draft has no errors', () {
      expect(check(), isEmpty);
    });

    test('name: required and bounded', () {
      expect(check(title: '')['title'], isNotNull);
      expect(check(title: '   ')['title'], isNotNull);
      expect(check(title: 'x' * 256)['title'], isNotNull);
      expect(check(title: 'x' * 255), isEmpty);
    });

    test('category is required', () {
      expect(check(category: null)['category_id'], isNotNull);
      expect(check(category: '')['category_id'], isNotNull);
    });

    test('MRP and price must be positive numbers', () {
      expect(check(mrp: '')['mrp'], isNotNull);
      expect(check(mrp: 'abc')['mrp'], isNotNull);
      expect(check(mrp: '0')['mrp'], isNotNull);
      expect(check(mrp: '-5')['mrp'], isNotNull);
      expect(check(price: '')['price'], isNotNull);
      expect(check(price: '0')['price'], isNotNull);
    });

    test('thousands separators and decimals are understood', () {
      expect(check(mrp: '1,299.50', price: '1,199'), isEmpty);
    });

    test('the price cannot exceed the MRP, but may equal it', () {
      expect(check(mrp: '1000', price: '1001')['price'], contains('higher than the MRP'));
      expect(check(mrp: '1000', price: '1000'), isEmpty);
    });

    test('an unparseable MRP does not also produce a misleading price comparison error', () {
      final errors = check(mrp: 'abc', price: '500');
      expect(errors['mrp'], isNotNull);
      expect(errors['price'], isNull);
    });

    test('going live needs a photo; drafts and out-of-stock do not', () {
      expect(check(status: 'ACTIVE', photos: 0)['photos'], isNotNull);
      expect(check(status: 'ACTIVE', photos: 1), isEmpty);
      expect(check(status: 'DRAFT', photos: 0), isEmpty);
      expect(check(status: 'OUT_OF_STOCK', photos: 0), isEmpty);
      expect(check(status: 'DISCONTINUED', photos: 0), isEmpty);
    });

    test('at least one variant', () {
      expect(check(variants: [])['variants'], isNotNull);
    });

    test('stock: required, whole, not negative', () {
      String? stock(String v) => check(variants: [VariantDraft(stock: v)])['variants.0.stock'];

      expect(stock(''), isNotNull);
      expect(stock('  '), isNotNull);
      expect(stock('abc'), isNotNull);
      expect(stock('2.5'), isNotNull);
      expect(stock('-1'), isNotNull);
      expect(stock('0'), isNull, reason: 'zero stock is valid — it is just sold out');
      expect(stock('250'), isNull);
    });

    test('variant prices are optional, but must be valid when given', () {
      String? p(String v) => check(variants: [VariantDraft(stock: '1', price: v)])['variants.0.price'];

      expect(p(''), isNull);
      expect(p('499'), isNull);
      expect(p('abc'), isNotNull);
      expect(p('-3'), isNotNull);
    });

    test('a variant\'s price cannot exceed its own MRP', () {
      final errors = check(variants: [const VariantDraft(stock: '1', price: '900', mrp: '800')]);
      expect(errors['variants.0.price'], contains('higher than the MRP'));
    });

    test('SKUs: optional, but not repeated (case-insensitively) within a product', () {
      expect(check(variants: [const VariantDraft(stock: '1'), const VariantDraft(stock: '1')]), isEmpty, reason: 'blank SKUs never clash');
      final errors = check(variants: [
        const VariantDraft(stock: '1', sku: 'LAMP-1'),
        const VariantDraft(stock: '1', sku: 'lamp-1'),
        const VariantDraft(stock: '1', sku: 'LAMP-2'),
      ]);
      expect(errors['variants.0.sku'], isNull);
      expect(errors['variants.1.sku'], isNotNull);
      expect(errors['variants.2.sku'], isNull);
    });

    test('a SKU over 80 characters is refused', () {
      expect(check(variants: [VariantDraft(stock: '1', sku: 'x' * 81)])['variants.0.sku'], isNotNull);
    });

    test('errors are keyed the way the API keys its own, per variant', () {
      final errors = check(variants: [const VariantDraft(stock: '1'), const VariantDraft(stock: '')]);
      expect(errors.keys, ['variants.1.stock']);
    });
  });

  group('parsing what was typed', () {
    test('parseMoney', () {
      expect(parseMoney('1,299.50'), 1299.5);
      expect(parseMoney(' 500 '), 500.0);
      expect(parseMoney(''), isNull);
      expect(parseMoney('abc'), isNull);
    });

    test('a variant row round-trips, and blank prices become null', () {
      final row = VariantRow(id: 'v1', color: ' Gold ', size: 'M', sku: ' G-M ', stock: '12', price: '', mrp: '1,000');
      final v = row.toVariant();

      expect(v.id, 'v1');
      expect(v.color, 'Gold');
      expect(v.sku, 'G-M');
      expect(v.stock, 12);
      expect(v.price, isNull, reason: 'blank = use the product\'s price');
      expect(v.mrp, 1000.0);
      row.dispose();
    });

    test('a variant row shows whole numbers without a trailing .0', () {
      final row = VariantRow.fromVariant(const SellerVariant(id: 'v', stock: 3, price: 2499, mrp: 2999.5));
      expect(row.price.text, '2499');
      expect(row.mrp.text, '2999.5');
      expect(row.stock.text, '3');
      row.dispose();
    });
  });

  group('photo rules', () {
    PickedDocument doc(String name, int bytes) => PickedDocument(name: name, bytes: List.filled(bytes, 1));

    test('images only, at most 10 MB', () {
      for (final n in ['a.jpg', 'a.JPEG', 'a.png', 'a.webp']) {
        expect(PhotoRules.problemWith(doc(n, 10)), isNull, reason: n);
      }
      expect(PhotoRules.problemWith(doc('a.pdf', 10)), isNotNull, reason: 'PDFs are for KYC, not product photos');
      expect(PhotoRules.problemWith(doc('a.gif', 10)), isNotNull);
      expect(PhotoRules.problemWith(doc('a.jpg', 0)), isNotNull);
      expect(PhotoRules.problemWith(doc('a.jpg', PhotoRules.maxBytes)), isNull);
      expect(PhotoRules.problemWith(doc('a.jpg', PhotoRules.maxBytes + 1)), isNotNull);
    });
  });

  group('order lines and what can be done to them', () {
    SellerOrderItem line(String fulfilment, String order) =>
        SellerOrderItem(id: 'i', title: 't', fulfilmentStatus: fulfilment, orderStatus: order);

    test('packing: only a pending line on an open order', () {
      expect(line('PENDING', 'CONFIRMED').canPack, isTrue);
      expect(line('PENDING', 'PACKED').canPack, isTrue);
      expect(line('PACKED', 'CONFIRMED').canPack, isFalse);
      expect(line('SHIPPED', 'CONFIRMED').canPack, isFalse);
      expect(line('PENDING', 'CANCELLED').canPack, isFalse);
      expect(line('PENDING', 'DELIVERED').canPack, isFalse);
      expect(line('PENDING', 'SHIPPED').canPack, isFalse);
    });

    test('shipping: a line not yet shipped, on an open order', () {
      expect(line('PENDING', 'CONFIRMED').canShip, isTrue);
      expect(line('PACKED', 'CONFIRMED').canShip, isTrue);
      expect(line('SHIPPED', 'CONFIRMED').canShip, isFalse);
      expect(line('PENDING', 'CANCELLED').canShip, isFalse);
    });

    test('tracking can be corrected until the order is out for delivery', () {
      expect(line('SHIPPED', 'CONFIRMED').canEditTracking, isTrue, reason: 'other sellers have not shipped yet');
      expect(line('SHIPPED', 'SHIPPED').canEditTracking, isTrue);
      expect(line('SHIPPED', 'OUT_FOR_DELIVERY').canEditTracking, isFalse);
      expect(line('SHIPPED', 'DELIVERED').canEditTracking, isFalse);
      expect(line('PENDING', 'CONFIRMED').canEditTracking, isFalse);
    });

    test('fulfilment fields parse, and an old response without them means "pending"', () {
      final full = SellerOrderItem.fromJson({
        'id': 'i', 'fulfilment_status': 'SHIPPED', 'courier': 'Delhivery', 'tracking_no': 'DL1', 'shipped_at': '2026-09-30T10:00:00Z',
        'order': {'status': 'CONFIRMED'},
      });
      expect(full.fulfilmentStatus, 'SHIPPED');
      expect(full.courier, 'Delhivery');
      expect(full.trackingNo, 'DL1');
      expect(full.shippedAt, isNotNull);

      final old = SellerOrderItem.fromJson({'id': 'i', 'order': {'status': 'CONFIRMED'}});
      expect(old.fulfilmentStatus, 'PENDING');
      expect(old.courier, isNull);
    });
  });

  group('products as the API returns them', () {
    test('everything the edit form needs comes from the list record', () {
      final p = SellerProduct.fromJson({
        'id': 'p1', 'title': 'Lamp', 'description': 'Nice.', 'brand': 'Asha', 'mrp': '2999.00', 'price': '2499.00',
        'status': 'ACTIVE', 'category_id': 'c1', 'category': {'name': 'Decor'},
        'images': ['https://img/a.jpg', {'url': 'https://img/b.jpg'}, ''],
        'variants': [
          {'id': 'v1', 'color': 'Gold', 'size': 'M', 'sku': 'G', 'stock': 5, 'price': '2399.00', 'mrp': null},
          {'id': 'v2', 'color': null, 'size': 'L', 'sku': null, 'stock': '3'},
        ],
      });

      expect(p.mrp, 2999.0);
      expect(p.categoryId, 'c1');
      expect(p.images, ['https://img/a.jpg', 'https://img/b.jpg'], reason: 'both image shapes, blanks dropped');
      expect(p.stock, 8);
      expect(p.variants[0].price, 2399.0);
      expect(p.variants[0].mrp, isNull);
      expect(p.variants[1].color, '');
      expect(p.variants[1].sku, '');
      expect(p.variants[1].stock, 3);
      expect(p.variants[0].label, 'Gold · M');
    });

    test('a categories payload', () {
      final c = ProductCategory.fromJson({'id': 'c1', 'name': 'Decor', 'slug': 'decor'});
      expect(c.id, 'c1');
      expect(c.name, 'Decor');
    });

    test('ProductInput serialises variants with and without ids', () {
      final json = const ProductInput(
        title: 'Lamp', description: '', brand: '', categoryId: 'c1', mrp: 100, price: 90, status: 'DRAFT', images: ['u'],
        variants: [SellerVariant(id: 'v1', color: 'Gold', stock: 2, price: 80), SellerVariant(color: 'New', stock: 1)],
      ).toJson();

      final v = json['variants'] as List;
      expect((v[0] as Map)['id'], 'v1');
      expect((v[0] as Map)['price'], 80.0);
      expect((v[1] as Map).containsKey('id'), isFalse);
      expect(json['category_id'], 'c1');
      expect(json['images'], ['u']);
    });
  });
}
