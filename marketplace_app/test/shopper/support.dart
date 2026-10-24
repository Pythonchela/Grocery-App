import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:marketplace_app/design/theme.dart';
import 'package:marketplace_app/data/store_config.dart';
import 'package:marketplace_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

final categories = [
  {
    'id': '1',
    'name': 'Ethnic & Festive',
    'slug': 'ethnic-wear',
    'icon_url': 'Sparkles'
  },
  {
    'id': '2',
    'name': 'Casual & Streetwear',
    'slug': 'casual-wear',
    'icon_url': 'Shirt'
  },
  {
    'id': '3',
    'name': 'Footwear & Sneakers',
    'slug': 'footwear',
    'icon_url': 'Zap'
  },
  {
    'id': '4',
    'name': 'Electronics & Accessories',
    'slug': 'electronics',
    'icon_url': 'Headphones'
  },
  {
    'id': '5',
    'name': 'Beauty & Personal Care',
    'slug': 'wellness',
    'icon_url': 'Leaf'
  },
];

Map<String, dynamic> product(
        {String id = 'p1', int stock = 3, bool options = false}) =>
    {
      'id': id,
      'title': 'Cotton everyday shirt with a long product name',
      'price': 999,
      'mrp': 1999,
      'rating': 4.5,
      'reviews_count': 24,
      'images': ['https://example.com/shirt.png'],
      'is_new': true,
      'in_stock': stock > 0,
      'description': 'A comfortable everyday shirt.',
      'variants': [
        {
          'id': 'v1',
          'color': 'Blue',
          'size': 'M',
          'price': 999,
          'stock': stock
        },
        if (options)
          {
            'id': 'v2',
            'color': 'Red',
            'size': 'L',
            'price': 1099,
            'stock': stock
          },
      ],
    };

final user = {
  'id': 'u1',
  'name': 'Shopper',
  'email': 'shopper@example.com',
  'role': 'CUSTOMER'
};
http.Response response(Object? data, {int status = 200}) =>
    http.Response(jsonEncode({'data': data}), status,
        headers: {'content-type': 'application/json'});

Future<void> resetState() async {
  AppState.staggerStartup = false;
  await initializeDateFormatting('en_IN');
  SharedPreferences.setMockInitialValues({});
  await AppState.instance.load();
  AppState.instance.signOut();
  AppState.instance.clearCart();
  AppState.instance.useStoreConfig(StoreConfig.fallback);
  AppState.instance.setThemeMode(ThemeMode.light);
}

Widget app(Widget child, {double scale = 1, bool dark = false}) => MaterialApp(
      theme: buildMaterialTheme(isDark: dark),
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: DsThemeScope(isDark: dark, child: widget!),
      ),
      home: child,
    );

void phone(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> finishLoad(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
