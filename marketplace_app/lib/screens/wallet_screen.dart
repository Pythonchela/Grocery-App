import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// Wallet balance + transactions and loyalty points + ledger. Two tabs because
/// the web splits them across the same account area.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<String, dynamic>? _wallet;
  Map<String, dynamic>? _loyalty;
  bool _loading = true;
  String? _error;
  String _tab = 'wallet';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = AppState.instance.token;
      final results = await Future.wait([
        ApiClient.request('/wallet', token: token),
        ApiClient.request('/loyalty', token: token),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = results[0] as Map<String, dynamic>;
        _loyalty = results[1] as Map<String, dynamic>;
        _loading = false;
      });
      AppState.instance.refreshUser();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(title: const Text('${DsBrand.walletName} & ${DsBrand.loyaltyName}')),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: BxSkeleton(height: 160, radius: DsRadius.cardAll),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load this page',
                  description: _error,
                  action: BxButton(label: 'Try again', onPressed: _load),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: c.accent,
                  child: ListView(
                    padding: const EdgeInsets.all(DsSpace.s4),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _Hero(
                              icon: Icons.account_balance_wallet_outlined,
                              value: formatMoney(
                                  _num(_wallet!['balance'])),
                              label: DsBrand.walletName,
                              note: 'Usable on your next order at checkout.',
                            ),
                          ),
                          const SizedBox(width: DsSpace.s3),
                          Expanded(
                            child: _Hero(
                              icon: Icons.stars_outlined,
                              value: '${_loyalty!['points'] ?? 0}',
                              label: DsBrand.loyaltyName,
                              note:
                                  'Worth ${formatMoney(_num(_loyalty!['value']))}.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DsSpace.s4),
                      BxTabs(
                        tabs: const [
                          BxTab('wallet', 'Wallet'),
                          BxTab('loyalty', 'Points'),
                        ],
                        value: _tab,
                        onChanged: (v) => setState(() => _tab = v),
                      ),
                      const SizedBox(height: DsSpace.s4),
                      if (_tab == 'wallet')
                        _WalletList(
                            rows: (_wallet!['transactions'] as List? ?? [])
                                .cast<Map<String, dynamic>>())
                      else
                        _LoyaltyList(
                          loyalty: _loyalty!,
                          rows: (_loyalty!['transactions'] as List? ?? [])
                              .cast<Map<String, dynamic>>(),
                        ),
                    ],
                  ),
                ),
    );
  }
}

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;

class _Hero extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String note;

  const _Hero(
      {required this.icon,
      required this.value,
      required this.label,
      required this.note});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.accent),
          const SizedBox(height: DsSpace.s2),
          Text(value,
              style: TextStyle(
                  fontSize: DsText.xl,
                  fontWeight: DsWeight.black,
                  color: c.ink)),
          Text(label,
              style: TextStyle(
                  fontSize: DsText.sm,
                  fontWeight: DsWeight.bold,
                  color: c.inkMuted)),
          const SizedBox(height: DsSpace.s1),
          Text(note,
              style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle)),
        ],
      ),
    );
  }
}

class _WalletList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _WalletList({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const BxEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No wallet transactions yet',
        description: 'Refunds and credits will show up here.',
      );
    }
    final c = context.ds;
    return Column(
      children: rows.map((t) {
        final credit = t['type'] == 'CREDIT';
        return Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s3),
          child: BxCard(
            child: Row(
              children: [
                Icon(credit ? Icons.south_west : Icons.north_east,
                    color: credit ? c.success : c.danger),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['reason']?.toString() ?? '',
                          style: TextStyle(
                              fontSize: DsText.base,
                              fontWeight: DsWeight.bold,
                              color: c.ink)),
                      Text(formatDate(t['created_at']?.toString()),
                          style: TextStyle(
                              fontSize: DsText.xs, color: c.inkSubtle)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        '${credit ? '+' : '−'} ${formatMoney(_num(t['amount']))}',
                        style: TextStyle(
                            fontWeight: DsWeight.black,
                            color: credit ? c.success : c.danger)),
                    Text('Bal ${formatMoney(_num(t['balance_after']))}',
                        style: TextStyle(
                            fontSize: DsText.x2xs, color: c.inkSubtle)),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _LoyaltyList extends StatelessWidget {
  final Map<String, dynamic> loyalty;
  final List<Map<String, dynamic>> rows;
  const _LoyaltyList({required this.loyalty, required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BxAlert(
          'Earn ${loyalty['earn_per_100'] ?? 0} points per ₹100 spent. '
          'Each point is worth ${formatMoney(_num(loyalty['redeem_value']))}, '
          'and can cover up to ${loyalty['max_redeem_percent'] ?? 0}% of an order.',
          tone: BxTone.info,
        ),
        const SizedBox(height: DsSpace.s4),
        if (rows.isEmpty)
          const BxEmptyState(
            icon: Icons.stars_outlined,
            title: 'No points activity yet',
            description: 'Points you earn and redeem will be listed here.',
          )
        else
          ...rows.map((t) {
            final points = (t['points'] as num?)?.toInt() ?? 0;
            final earned = points >= 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s3),
              child: BxCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              (t['reason'] ?? t['type'] ?? 'Points').toString(),
                              style: TextStyle(
                                  fontSize: DsText.base,
                                  fontWeight: DsWeight.bold,
                                  color: c.ink)),
                          Text(formatDate(t['created_at']?.toString()),
                              style: TextStyle(
                                  fontSize: DsText.xs, color: c.inkSubtle)),
                        ],
                      ),
                    ),
                    Text('${earned ? '+' : ''}$points',
                        style: TextStyle(
                            fontWeight: DsWeight.black,
                            color: earned ? c.success : c.danger)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
