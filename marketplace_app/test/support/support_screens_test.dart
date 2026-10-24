import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/api_client.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/design/theme.dart';
import 'package:marketplace_app/support/support_api.dart';
import 'package:marketplace_app/support/support_screens.dart';

class FakeSupportApi implements SupportApi {
  final calls = <String>[];
  List<SupportTicket> rows;
  ApiException? openError;

  FakeSupportApi([this.rows = const []]);

  SupportTicket _t(String id, {String status = 'OPEN', int? rating, List<SupportMessage>? messages}) => SupportTicket(
        id: id, number: 'TKT-$id', subject: 'Parcel late', status: status, rating: rating,
        messages: messages ?? const [SupportMessage(id: 'm1', fromTeam: false, body: 'It is late')],
      );

  @override
  Future<List<SupportTicket>> tickets() async => rows;

  @override
  Future<SupportTicket> ticket(String id) async => rows.firstWhere((t) => t.id == id);

  @override
  Future<SupportTicket> open({required String category, required String subject, required String message, String? orderId}) async {
    calls.add('open:$category:$subject:${orderId ?? ''}');
    if (openError != null) throw openError!;
    final t = _t('new');
    rows = [t, ...rows];
    return t;
  }

  @override
  Future<SupportTicket> reply(String id, String body) async {
    calls.add('reply:$body');
    final old = rows.firstWhere((t) => t.id == id);
    final t = SupportTicket(id: id, number: old.number, subject: old.subject, status: 'OPEN', messages: [
      ...old.messages,
      SupportMessage(id: 'x', fromTeam: false, body: body),
    ]);
    rows = [for (final r in rows) r.id == id ? t : r];
    return t;
  }

  @override
  Future<SupportTicket> close(String id) async {
    calls.add('close');
    final old = rows.firstWhere((t) => t.id == id);
    final t = SupportTicket(id: id, number: old.number, subject: old.subject, status: 'CLOSED', messages: old.messages);
    rows = [for (final r in rows) r.id == id ? t : r];
    return t;
  }

  @override
  Future<SupportTicket> rate(String id, int rating) async {
    calls.add('rate:$rating');
    final old = rows.firstWhere((t) => t.id == id);
    final t = SupportTicket(id: id, number: old.number, subject: old.subject, status: old.status, rating: rating, messages: old.messages);
    rows = [for (final r in rows) r.id == id ? t : r];
    return t;
  }
}

Widget app(Widget home) => MaterialApp(
      theme: buildMaterialTheme(isDark: false),
      builder: (context, child) => DsThemeScope(isDark: false, child: child ?? const SizedBox.shrink()),
      home: home,
    );

Future<void> pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty list says so and offers a new request', (tester) async {
    await pump(tester, app(SupportScreen(api: FakeSupportApi())));

    expect(find.text('No requests yet'), findsOneWidget);
    expect(find.byKey(const Key('new-ticket')), findsOneWidget);
  });

  testWidgets('lists tickets with their status', (tester) async {
    final api = FakeSupportApi([
      const SupportTicket(id: 'a', number: 'TKT-A', subject: 'Wrong item', status: 'WAITING_ON_REQUESTER'),
      const SupportTicket(id: 'b', number: 'TKT-B', subject: 'Refund', status: 'RESOLVED', orderNumber: 'ORD-1'),
    ]);
    await pump(tester, app(SupportScreen(api: api)));

    expect(find.text('Wrong item'), findsOneWidget);
    expect(find.text('Waiting for your reply'), findsOneWidget);
    expect(find.textContaining('order ORD-1'), findsOneWidget);
  });

  testWidgets('a shopper cannot pick seller-only categories', (tester) async {
    await pump(tester, app(NewTicketScreen(api: FakeSupportApi())));
    await tap(tester, find.byKey(const Key('ticket-category')));
    expect(find.text('Payouts and earnings'), findsNothing);
    expect(find.text('Delivery or tracking'), findsWidgets);
  });

  testWidgets('a seller cannot pick shopper-only categories', (tester) async {
    await pump(tester, app(NewTicketScreen(api: FakeSupportApi(), seller: true)));
    await tap(tester, find.byKey(const Key('ticket-category')));
    expect(find.text('My account'), findsNothing);
    expect(find.text('Payouts and earnings'), findsWidgets);
  });

  testWidgets('a new request needs a subject and a message, then opens its conversation', (tester) async {
    final api = FakeSupportApi();
    await pump(tester, app(SupportScreen(api: api)));
    await tap(tester, find.byKey(const Key('new-ticket')));

    await tap(tester, find.widgetWithText(BxButton, 'Send request'));
    expect(find.textContaining('Add a short subject'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.enterText(find.byType(TextField).at(0), 'Parcel late');
    await tester.enterText(find.byType(TextField).at(1), 'It has been a week');
    await tap(tester, find.widgetWithText(BxButton, 'Send request'));

    expect(api.calls, ['open:ORDER_ISSUE:Parcel late:']);
    expect(find.text('TKT-new'), findsOneWidget);
    expect(find.text('It is late'), findsOneWidget);
  });

  testWidgets('opened from an order, the request is about that order', (tester) async {
    final api = FakeSupportApi();
    await pump(tester, app(SupportScreen(api: api, orderId: 'order-uuid', orderNumber: 'ORD-9')));

    expect(find.text('About order ORD-9'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Missing item');
    await tester.enterText(find.byType(TextField).at(1), 'Box was empty');
    await tap(tester, find.widgetWithText(BxButton, 'Send request'));

    expect(api.calls.single, 'open:ORDER_ISSUE:Missing item:order-uuid');
  });

  testWidgets('the server\'s reason for refusing is shown', (tester) async {
    final api = FakeSupportApi()..openError = ApiException(422, 'That order is not yours.', errors: {'order_id': ['That order is not yours.']});
    await pump(tester, app(NewTicketScreen(api: api, orderId: 'x')));
    await tester.enterText(find.byType(TextField).at(0), 'Subject here');
    await tester.enterText(find.byType(TextField).at(1), 'Message here');
    await tap(tester, find.widgetWithText(BxButton, 'Send request'));

    expect(find.text('That order is not yours.'), findsOneWidget);
  });

  testWidgets('replying adds your message to the thread', (tester) async {
    final api = FakeSupportApi([
      const SupportTicket(id: 'a', number: 'TKT-A', subject: 'Parcel late', status: 'WAITING_ON_REQUESTER', messages: [
        SupportMessage(id: '1', fromTeam: false, body: 'It is late'),
        SupportMessage(id: '2', fromTeam: true, body: 'Checking with the courier'),
      ]),
    ]);
    await pump(tester, app(TicketScreen(api: api, ticket: api.rows.first)));

    expect(find.text('Checking with the courier'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ticket-reply')), 'Thanks, any news?');
    await tap(tester, find.widgetWithText(BxButton, 'Send'));

    expect(api.calls, ['reply:Thanks, any news?']);
    expect(find.text('Thanks, any news?'), findsOneWidget);
  });

  testWidgets('a resolved ticket can be rated', (tester) async {
    final api = FakeSupportApi([const SupportTicket(id: 'a', number: 'TKT-A', subject: 'Parcel late', status: 'RESOLVED', messages: [SupportMessage(id: '1', fromTeam: true, body: 'Fixed')])]);
    await pump(tester, app(TicketScreen(api: api, ticket: api.rows.first)));

    expect(find.text('How did we do?'), findsOneWidget);
    await tap(tester, find.widgetWithText(ActionChip, '5★'));
    expect(api.calls, ['rate:5']);
    expect(find.textContaining('rated this 5 out of 5'), findsOneWidget);
  });

  testWidgets('a closed ticket takes no more replies', (tester) async {
    final closed = FakeSupportApi([const SupportTicket(id: 'c', number: 'TKT-C', subject: 'Old', status: 'CLOSED')]);
    await pump(tester, app(TicketScreen(api: closed, ticket: closed.rows.first)));
    expect(find.byKey(const Key('ticket-reply')), findsNothing);
  });

  testWidgets('an open ticket can be closed by the requester', (tester) async {
    final api = FakeSupportApi([const SupportTicket(id: 'a', number: 'TKT-A', subject: 'Parcel late', status: 'OPEN')]);
    await pump(tester, app(TicketScreen(api: api, ticket: api.rows.first)));

    await tap(tester, find.widgetWithText(BxButton, "It's sorted"));
    expect(api.calls, ['close']);
    expect(find.byKey(const Key('ticket-reply')), findsNothing);
  });
}
