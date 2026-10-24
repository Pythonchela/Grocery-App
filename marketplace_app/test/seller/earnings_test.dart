import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/seller/seller_models.dart';

import 'support.dart';

/// What the seller is owed, what can be paid out now, and what is still waiting
/// on delivery and the return window.
void main() {
  FakeSellerApi seller() => FakeSellerApi(buildOnboarding(seller: 'ACTIVE', kyc: 'APPROVED'));

  Future<void> openEarnings(WidgetTester tester, FakeSellerApi api) async {
    await pumpSeller(tester, sellerApp(api));
    await tapAndSettle(tester, nav('Earnings'));
  }

  testWidgets('splits the balance into payable now and pending', (tester) async {
    final api = seller()
      ..ledgerBalance = 1400
      ..ledgerPending = 900
      ..ledgerWithdrawable = 500;
    await openEarnings(tester, api);

    expect(find.text('Payout balance'), findsOneWidget);
    expect(find.text('Payable now'), findsOneWidget);
    expect(find.text('₹500.00'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('₹900.00'), findsOneWidget);
    expect(find.textContaining('7-day return window'), findsOneWidget);
  });

  testWidgets('against an older server that does not split it, the balance is shown whole', (tester) async {
    final api = seller()..ledgerBalance = 1400;
    await openEarnings(tester, api);

    expect(find.text('Payout balance'), findsOneWidget);
    expect(find.text('Payable now'), findsNothing);
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('a payout is listed as one, as money leaving the balance', (tester) async {
    final api = seller()
      ..ledgerBalance = 1000
      ..ledgerPending = 0
      ..ledgerWithdrawable = 1000
      ..ledgerRows = const [
        LedgerEntry(id: 'l1', type: 'PAYOUT', gross: -400, commission: 0, net: -400, balanceAfter: 1000, note: 'Payout UTR998877'),
        LedgerEntry(id: 'l2', type: 'SALE', gross: 1556, commission: 156, net: 1400, balanceAfter: 1400, note: 'Sale ORD-AAA11111'),
      ];
    await openEarnings(tester, api);

    expect(find.text('Payout'), findsOneWidget);
    expect(find.text('−₹400.00'), findsOneWidget);
    expect(find.text('Payout UTR998877'), findsOneWidget);
    expect(find.text('Sale'), findsOneWidget);
  });
}
