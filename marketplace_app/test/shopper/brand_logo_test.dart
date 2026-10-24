import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/design/brand_mark.dart';
import 'package:marketplace_app/state/app_state.dart';

import 'support.dart';

/// The logo an admin uploads on the web is what the app shows in its header.
void main() {
  setUp(resetState);

  Future<http.Response> Function(http.Request) theme(Object? logo) => (request) async {
        if (request.url.path.endsWith('/theme')) {
          return response({'colors': {}, 'colors_dark': {}, 'logo_url': logo});
        }
        return response([]);
      };

  group('what the app learns from /theme', () {
    test('it remembers the logo address the admin set', () async {
      await http.runWithClient(() async {
        await AppState.instance.loadThemeOverrides();
        expect(AppState.instance.logoUrl, 'https://shop.example/storage/branding/logo.png');
      }, () => MockClient(theme('https://shop.example/storage/branding/logo.png')));
    });

    test('no logo set means the shipped mark', () async {
      await http.runWithClient(() async {
        await AppState.instance.loadThemeOverrides();
        expect(AppState.instance.logoUrl, isNull);
      }, () => MockClient(theme(null)));
    });

    test('an address that is not http(s) is never used', () async {
      await http.runWithClient(() async {
        await AppState.instance.loadThemeOverrides();
        expect(AppState.instance.logoUrl, isNull);
      }, () => MockClient(theme('javascript:alert(1)')));
    });

    test('removing the logo on the web removes it in the app', () async {
      await http.runWithClient(() async {
        await AppState.instance.loadThemeOverrides();
        expect(AppState.instance.logoUrl, isNotNull);
      }, () => MockClient(theme('https://shop.example/logo.png')));

      await http.runWithClient(() async {
        await AppState.instance.loadThemeOverrides();
        expect(AppState.instance.logoUrl, isNull);
      }, () => MockClient(theme(null)));
    });
  });

  group('the mark itself', () {
    testWidgets('without a logo it is the two-letter mark', (tester) async {
      await tester.pumpWidget(app(const BrandMark()));

      expect(find.byKey(const Key('brand-initials')), findsOneWidget);
      expect(find.byKey(const Key('brand-logo')), findsNothing);
    });

    testWidgets('with a logo it asks for the picture', (tester) async {
      await tester.pumpWidget(app(const BrandMark(logoUrl: 'https://shop.example/logo.png')));

      expect(find.byKey(const Key('brand-logo')), findsOneWidget);
    });

    testWidgets('a picture that cannot load falls back to the initials, not a broken icon', (tester) async {
      await tester.pumpWidget(app(const BrandMark(logoUrl: 'https://shop.example/missing.png')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byKey(const Key('brand-initials')), findsOneWidget);
      expect(find.byIcon(Icons.broken_image), findsNothing);
    });
  });
}
