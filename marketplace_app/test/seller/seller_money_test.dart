import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/design/components.dart';
import 'package:marketplace_app/seller/seller_models.dart';

import 'support.dart';

/// Getting paid from the Earnings tab: ask for a payout, change the bank account,
/// read a monthly statement.
void main() {
  FakeSellerApi seller() => FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'));

  Future<void> openEarnings(WidgetTester tester, FakeSellerApi api) async {
    await pumpSeller(tester, sellerApp(api));
    await tapAndSettle(tester, nav('Earnings'));
  }

  testWidgets('shows the bank account without its full number and offers a payout request', (tester) async {
    await openEarnings(tester, seller());

    expect(find.text('Get paid'), findsOneWidget);
    expect(find.textContaining('••••9012'), findsOneWidget);
    expect(find.widgetWithText(BxButton, 'Request payout'), findsOneWidget);
  });

  testWidgets('requesting everything payable sends no amount, then offers to cancel it', (tester) async {
    final api = seller();
    await openEarnings(tester, api);

    await tapAndSettle(tester, find.widgetWithText(BxButton, 'Request payout'));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Request'));

    expect(api.calls, contains('requestPayout:all'));
    expect(find.widgetWithText(BxButton, 'Cancel request'), findsOneWidget);

    await tapAndSettle(tester, find.widgetWithText(BxButton, 'Cancel request'));
    expect(api.calls, contains('cancelPayout:r1'));
  });

  testWidgets('a typed amount is sent as that amount', (tester) async {
    final api = seller();
    await openEarnings(tester, api);

    await tapAndSettle(tester, find.widgetWithText(BxButton, 'Request payout'));
    await tester.enterText(find.byType(TextField), '750');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Request'));

    expect(api.calls, contains('requestPayout:750.0'));
  });

  testWidgets('when something blocks a request the reason is shown instead of a button', (tester) async {
    final api = seller()
      ..moneyState = const SellerMoney(balance: 500, withdrawable: 0, blocker: 'Add and verify your bank account before asking to be paid.');
    await openEarnings(tester, api);

    expect(find.text('Add and verify your bank account before asking to be paid.'), findsOneWidget);
    expect(find.widgetWithText(BxButton, 'Request payout'), findsNothing);
  });

  testWidgets('changing the bank account says it waits for confirmation', (tester) async {
    final api = seller();
    await openEarnings(tester, api);

    await tapAndSettle(tester, find.widgetWithText(BxButton, 'Change bank account'));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Asha');
    await tester.enterText(fields.at(1), '999988887777');
    await tester.enterText(fields.at(2), 'SBIN0000001');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Send'));

    expect(api.calls, contains('changeBank:999988887777'));
    expect(find.textContaining('waiting to be confirmed'), findsOneWidget);
    expect(find.widgetWithText(BxButton, 'Change bank account'), findsNothing);
  });

  testWidgets('the statement screen lists the month and its totals', (tester) async {
    await openEarnings(tester, seller());

    await tapAndSettle(tester, find.widgetWithText(BxButton, 'Monthly statements'));

    expect(find.text('Gross sales'), findsOneWidget);
    expect(find.text('Closing balance'), findsOneWidget);
    expect(find.textContaining('not tax advice'), findsOneWidget);
  });

  test('a payout request row words its status for a seller', () {
    expect(const PayoutRequestRow(id: 'a', status: 'REQUESTED').statusLabel, 'Waiting for the team');
    expect(const PayoutRequestRow(id: 'a', status: 'PAID').statusLabel, 'Paid');
    expect(SellerMoney.fromJson({'requests': [{'id': 'a', 'status': 'REQUESTED', 'amount': '10'}]}).open?.amount, 10);
  });
}
