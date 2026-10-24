import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_api.dart';
import '../seller_format.dart';
import '../seller_models.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/paged_loader.dart';
import '../widgets/seller_widgets.dart';
import 'money_section.dart';

/// What the seller is owed, and how it got there: sales, refunds clawed back,
/// and any manual adjustments, newest first.
class EarningsTab extends StatefulWidget {
  final SellerApi api;

  const EarningsTab({super.key, required this.api});

  @override
  State<EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<EarningsTab> {
  late final PagedLoader<LedgerEntry> _loader;

  @override
  void initState() {
    super.initState();
    _loader = PagedLoader((page) => widget.api.ledger(page: page))..refresh();
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _loader,
      builder: (context, _) {
        final extra = _loader.lastPage?.extra ?? const {};
        final balance = (extra['balance'] as num?)?.toDouble();
        // Older servers do not split the balance; then it is shown whole.
        final pending = (extra['pending'] as num?)?.toDouble();
        final withdrawable = (extra['withdrawable'] as num?)?.toDouble();

        return PagedListView<LedgerEntry>(
          loader: _loader,
          header: [
            _BalanceCard(balance: balance, pending: pending, withdrawable: withdrawable),
            const SizedBox(height: DsSpace.s4),
            MoneySection(api: widget.api, onChanged: _loader.refresh),
            const SizedBox(height: DsSpace.s5),
          ],
          empty: const BxEmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No earnings yet',
            description: 'Each sale, refund and adjustment is recorded here.',
          ),
          itemBuilder: (context, e) => _LedgerRow(entry: e),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double? balance;

  /// Earned on orders that are not delivered yet, or are still inside the return
  /// window, so cannot be paid out; and what can be paid out now.
  final double? pending;
  final double? withdrawable;

  const _BalanceCard({required this.balance, this.pending, this.withdrawable});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return BxCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payout balance', style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
          const SizedBox(height: DsSpace.s1),
          Text(
            balance == null ? '—' : SellerFormat.money(balance!),
            style: TextStyle(fontSize: DsText.x2xl, fontWeight: DsWeight.black, color: c.ink),
          ),
          const SizedBox(height: DsSpace.s1),
          Text(
            'What the marketplace owes you, after commission. Paid out to your bank account.',
            style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
          ),
          if (pending != null && withdrawable != null) ...[
            const SizedBox(height: DsSpace.s3),
            Divider(height: 1, color: c.line),
            const SizedBox(height: DsSpace.s3),
            SellerKeyValue('Payable now', SellerFormat.money(withdrawable!)),
            SellerKeyValue('Pending', SellerFormat.money(pending!)),
            const SizedBox(height: DsSpace.s1),
            Text(
              'Pending money becomes payable once the order is delivered and the 7-day return window has passed.',
              style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
            ),
          ],
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final LedgerEntry entry;

  const _LedgerRow({required this.entry});

  (String, BxTone) get _kind => switch (entry.type) {
        'SALE' => ('Sale', BxTone.success),
        'REFUND' => ('Refund', BxTone.danger),
        'ADJUSTMENT' => ('Adjustment', BxTone.info),
        'PAYOUT' => ('Payout', BxTone.primary),
        _ => (entry.type, BxTone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final (label, tone) = _kind;
    final positive = entry.net >= 0;

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BxBadge(label, tone: tone),
              const SizedBox(width: DsSpace.s3),
              // Shrinks a very large amount rather than overflowing the row.
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${positive ? '+' : '−'}${SellerFormat.money(entry.net.abs())}',
                      style: TextStyle(
                        fontSize: DsText.md,
                        fontWeight: DsWeight.black,
                        color: positive ? c.success : c.danger,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s1),
          Text(
            SellerFormat.dateTime(entry.createdAt),
            style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
          ),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(height: DsSpace.s2),
            Text(entry.note, style: TextStyle(fontSize: DsText.sm, color: c.ink)),
          ],
          const SizedBox(height: DsSpace.s2),
          Text(
            [
              if (entry.gross != 0) 'Sale ${SellerFormat.money(entry.gross.abs())}',
              if (entry.commission != 0) 'Commission ${SellerFormat.money(entry.commission.abs())}',
              'Balance ${SellerFormat.money(entry.balanceAfter)}',
            ].join(' · '),
            style: TextStyle(fontSize: DsText.xs, color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}
