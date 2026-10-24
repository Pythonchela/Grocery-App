import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/vendor/vendor_app.dart';
import 'package:marketplace_app/vendor/vendor_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../seller/support.dart';

/// The seller app on its own: sign in, then the seller area.
void main() {
  const shop = {'id': 'u1', 'name': 'Asha Rao', 'email': 'asha@example.com', 'role': 'SELLER'};

  http.Response json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  /// A server that knows one account, and a store of the given kind.
  Future<http.Response> Function(http.Request) server({
    String mode = 'hybrid',
    Map<String, dynamic> user = shop,
    List<String>? log,
  }) =>
      (request) async {
        final path = request.url.path;
        log?.add('${request.method} $path');
        if (path.endsWith('/auth/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['password'] != 'secret-pass') return json({'message': 'These credentials do not match our records.'}, status: 401);
          return json({'data': {'token': 'tok', 'user': user}});
        }
        if (path.endsWith('/auth/register')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['email'] == 'taken@example.com') {
            return json({'message': 'The email has already been taken.', 'errors': {'email': ['That email is already registered.']}}, status: 422);
          }
          return json({'data': {'token': 'tok2', 'user': {...user, 'name': body['name'], 'email': body['email'], 'role': 'CUSTOMER'}}}, status: 201);
        }
        if (path.endsWith('/config')) return json({'data': {'mode': mode, 'store_name': 'Corner Shop'}});
        if (path.endsWith('/theme')) return json({'data': {'colors': {}, 'colors_dark': {}, 'logo_url': null}});
        return json({'data': []});
      };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    VendorSession.instance.resetForTest();
    await VendorSession.instance.load();
  });

  Future<void> pumpVendor(WidgetTester tester, {FakeSellerApi? api}) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(VendorApp(api: api ?? FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED')), picker: FakePicker()));
    await tester.pumpAndSettle();
  }

  Future<void> fillAndSubmit(WidgetTester tester, {String email = 'asha@example.com', String password = 'secret-pass'}) async {
    await tester.enterText(find.byKey(const Key('vendor-email')), email);
    await tester.enterText(find.byKey(const Key('vendor-password')), password);
    await tester.tap(find.byKey(const Key('vendor-submit')));
    await tester.pumpAndSettle();
  }

  group('the session', () {
    test('signing in keeps the token and user, and a restart finds them', () async {
      await http.runWithClient(() async {
        await VendorSession.instance.signIn('asha@example.com', 'secret-pass');
        expect(VendorSession.instance.isSignedIn, isTrue);
        expect(VendorSession.instance.user!.name, 'Asha Rao');

        // A new launch: nothing in memory, everything on the phone.
        VendorSession.instance.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bazaarx_auth_token', 'tok');
        await prefs.setString('bazaarx_auth_user', jsonEncode(shop));
        await VendorSession.instance.load();

        expect(VendorSession.instance.isSignedIn, isTrue);
        expect(VendorSession.instance.token, 'tok');
      }, () => MockClient(server()));
    });

    test('the token is kept where the background order check looks for it', () async {
      await http.runWithClient(() async {
        await VendorSession.instance.signIn('asha@example.com', 'secret-pass');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('bazaarx_auth_token'), 'tok');
      }, () => MockClient(server()));
    });

    test('signing out forgets everything and tells the app', () async {
      String? ended;
      await http.runWithClient(() async {
        VendorSession.instance.onEnding = (token) => ended = token;
        await VendorSession.instance.signIn('asha@example.com', 'secret-pass');
        VendorSession.instance.signOut();
        VendorSession.instance.onEnding = null;

        expect(VendorSession.instance.isSignedIn, isFalse);
        expect(ended, 'tok');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('bazaarx_auth_token'), isNull);
        expect(prefs.getString('bazaarx_auth_user'), isNull);
      }, () => MockClient(server()));
    });

    test('a half-saved session (token, no user) is not a session', () async {
      SharedPreferences.setMockInitialValues({'bazaarx_auth_token': 'tok'});
      await VendorSession.instance.load();

      expect(VendorSession.instance.isSignedIn, isFalse);
    });

    test('staff are recognised, shop owners and shoppers are not', () {
      for (final role in ['ADMIN', 'SUPER_ADMIN', 'SUB_ADMIN']) {
        expect(VendorUser.fromJson({...shop, 'role': role}).isStaff, isTrue, reason: role);
      }
      for (final role in ['SELLER', 'CUSTOMER']) {
        expect(VendorUser.fromJson({...shop, 'role': role}).isStaff, isFalse, reason: role);
      }
    });
  });

  group('the sign-in screen', () {
    testWidgets('a signed-out phone shows the seller sign-in, not a shop', (tester) async {
      await http.runWithClient(() async {
        await pumpVendor(tester);

        expect(find.text('BazaarX Seller'), findsOneWidget);
        expect(find.byKey(const Key('vendor-submit')), findsOneWidget);
        expect(find.text('Categories'), findsNothing);
        expect(find.text('Cart'), findsNothing);
      }, () => MockClient(server()));
    });

    testWidgets('nothing is sent until the email and password look right', (tester) async {
      final log = <String>[];
      await http.runWithClient(() async {
        await pumpVendor(tester);
        await tester.tap(find.byKey(const Key('vendor-submit')));
        await tester.pumpAndSettle();

        expect(find.text('Enter a valid email address.'), findsOneWidget);
        expect(find.text('Enter your password.'), findsOneWidget);
        expect(log.where((l) => l.contains('/auth/')), isEmpty);
      }, () => MockClient(server(log: log)));
    });

    testWidgets('a wrong password says so and stays on the screen', (tester) async {
      await http.runWithClient(() async {
        await pumpVendor(tester);
        await fillAndSubmit(tester, password: 'wrong-password');

        expect(find.text('These credentials do not match our records.'), findsOneWidget);
        expect(find.byKey(const Key('vendor-submit')), findsOneWidget);
        expect(VendorSession.instance.isSignedIn, isFalse);
      }, () => MockClient(server()));
    });

    testWidgets('a shop owner signs in and lands on the dashboard', (tester) async {
      await http.runWithClient(() async {
        await pumpVendor(tester);
        await fillAndSubmit(tester);

        expect(find.byKey(const Key('vendor-submit')), findsNothing);
        expect(nav('Earnings'), findsOneWidget);
        expect(find.text('Categories'), findsNothing);
      }, () => MockClient(server()));
    });

    testWidgets('creating an account asks for a name and a password of 8 or more', (tester) async {
      await http.runWithClient(() async {
        await pumpVendor(tester);
        await tester.tap(find.byKey(const Key('vendor-switch-mode')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('vendor-name')), findsOneWidget);

        await tester.enterText(find.byKey(const Key('vendor-email')), 'new@example.com');
        await tester.enterText(find.byKey(const Key('vendor-password')), 'short');
        await tester.tap(find.byKey(const Key('vendor-submit')));
        await tester.pumpAndSettle();

        expect(find.text('Enter your name.'), findsOneWidget);
        expect(find.text('Use at least 8 characters.'), findsOneWidget);
      }, () => MockClient(server()));
    });

    testWidgets('a new account goes straight to applying to sell', (tester) async {
      await http.runWithClient(() async {
        await pumpVendor(tester, api: FakeSellerApi(null));
        await tester.tap(find.byKey(const Key('vendor-switch-mode')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('vendor-name')), 'Ravi Kumar');
        await tester.enterText(find.byKey(const Key('vendor-email')), 'ravi@example.com');
        await tester.enterText(find.byKey(const Key('vendor-password')), 'long-enough-pass');
        await tester.tap(find.byKey(const Key('vendor-submit')));
        await tester.pumpAndSettle();

        expect(find.text('Start application'), findsOneWidget);
      }, () => MockClient(server()));
    });

    testWidgets('a taken email is explained under the email field', (tester) async {
      await http.runWithClient(() async {
        await pumpVendor(tester);
        await tester.tap(find.byKey(const Key('vendor-switch-mode')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('vendor-name')), 'Ravi Kumar');
        await tester.enterText(find.byKey(const Key('vendor-email')), 'taken@example.com');
        await tester.enterText(find.byKey(const Key('vendor-password')), 'long-enough-pass');
        await tester.tap(find.byKey(const Key('vendor-submit')));
        await tester.pumpAndSettle();

        expect(find.text('That email is already registered.'), findsOneWidget);
        expect(VendorSession.instance.isSignedIn, isFalse);
      }, () => MockClient(server()));
    });
  });

  group('where each account lands', () {
    Future<void> signedInAs(WidgetTester tester, Map<String, dynamic> user, {String mode = 'hybrid', FakeSellerApi? api}) async {
      SharedPreferences.setMockInitialValues({'bazaarx_auth_token': 'tok', 'bazaarx_auth_user': jsonEncode(user)});
      await VendorSession.instance.load();
      await pumpVendor(tester, api: api);
    }

    testWidgets('an approved shop owner: the dashboard', (tester) async {
      await http.runWithClient(() async {
        await signedInAs(tester, shop);
        expect(nav('Earnings'), findsOneWidget);
      }, () => MockClient(server()));
    });

    testWidgets('someone who has not applied: the application', (tester) async {
      await http.runWithClient(() async {
        await signedInAs(tester, {...shop, 'role': 'CUSTOMER'}, api: FakeSellerApi(null));
        expect(find.text('Start application'), findsOneWidget);
      }, () => MockClient(server()));
    });

    testWidgets('a shop in review: its status', (tester) async {
      await http.runWithClient(() async {
        await signedInAs(tester, shop,
            api: FakeSellerApi(buildOnboarding(kyc: 'SUBMITTED', kycOverrides: {'submitted_at': '2026-09-30T10:00:00Z'})));
        expect(find.text('Your application is under review'), findsOneWidget);
      }, () => MockClient(server()));
    });

    testWidgets('staff of a marketplace are pointed to the website', (tester) async {
      await http.runWithClient(() async {
        await signedInAs(tester, {...shop, 'role': 'ADMIN'}, mode: 'multi');
        expect(find.text('This is a staff account'), findsOneWidget);
        expect(nav('Earnings'), findsNothing);
      }, () => MockClient(server(mode: 'multi')));
    });

    testWidgets('staff of a single-business store land on its shop', (tester) async {
      await http.runWithClient(() async {
        await signedInAs(tester, {...shop, 'role': 'ADMIN'}, mode: 'single');
        expect(find.text('This is a staff account'), findsNothing);
        expect(nav('Earnings'), findsOneWidget);
        expect(find.text('Corner Shop'), findsWidgets);
      }, () => MockClient(server(mode: 'single', user: {...shop, 'role': 'ADMIN'})));
    });

    testWidgets('staff can retry when the store details could not be loaded', (tester) async {
      var online = false;
      await http.runWithClient(() async {
        await signedInAs(tester, {...shop, 'role': 'ADMIN'});
        expect(find.byKey(const Key('staff-retry')), findsOneWidget);

        online = true;
        await tester.tap(find.byKey(const Key('staff-retry')));
        await tester.pumpAndSettle();

        expect(find.text('This is a staff account'), findsOneWidget);
        expect(find.byKey(const Key('staff-retry')), findsNothing);
      }, () => MockClient((request) async {
            if (!online) return json({'message': 'down'}, status: 500);
            return server(mode: 'multi')(request);
          }));
    });
  });

  group('signing out', () {
    testWidgets('from the menu goes back to the sign-in', (tester) async {
      await http.runWithClient(() async {
        SharedPreferences.setMockInitialValues({'bazaarx_auth_token': 'tok', 'bazaarx_auth_user': jsonEncode(shop)});
        await VendorSession.instance.load();
        await pumpVendor(tester);

        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('menu-sign-out')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('vendor-submit')), findsOneWidget);
        expect(VendorSession.instance.isSignedIn, isFalse);
      }, () => MockClient(server()));
    });

    testWidgets('there is no way across to a shop: this app has none', (tester) async {
      await http.runWithClient(() async {
        SharedPreferences.setMockInitialValues({'bazaarx_auth_token': 'tok', 'bazaarx_auth_user': jsonEncode(shop)});
        await VendorSession.instance.load();
        await pumpVendor(tester);

        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('menu-shop-as-customer')), findsNothing);
      }, () => MockClient(server()));
    });
  });
}
