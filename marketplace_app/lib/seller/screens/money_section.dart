import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_api.dart';
import '../seller_format.dart';
import '../seller_models.dart';
import '../widgets/seller_widgets.dart';

/// Getting paid, under the balance: ask for a payout, see and change the bank
/// account (staff confirm a change), and open monthly statements.
class MoneySection extends StatefulWidget {
  final SellerApi api;

  /// Called when something changed that the balance above depends on.
  final VoidCallback? onChanged;

  const MoneySection({super.key, required this.api, this.onChanged});

  @override
  State<MoneySection> createState() => _MoneySectionState();
}

class _MoneySectionState extends State<MoneySection> {
  SellerMoney? _money;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final money = await widget.api.money();
      if (mounted) setState(() { _money = money; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load payout details.');
    }
  }

  Future<void> _run(Future<void> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      await call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      widget.onChanged?.call();
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fieldError('amount') ?? e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach the server. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(SellerMoney money) async {
    final amount = await showDialog<double?>(context: context, builder: (_) => _RequestDialog(money: money));
    if (amount == null || !mounted) return;
    await _run(() => widget.api.requestPayout(amount: amount < 0 ? null : amount), 'Payout requested.');
  }

  Future<void> _changeBank() async {
    final values = await showDialog<(String, String, String, String)>(context: context, builder: (_) => const _BankDialog());
    if (values == null || !mounted) return;
    await _run(
      () => widget.api.changeBank(holder: values.$1, number: values.$2, ifsc: values.$3, bank: values.$4),
      'Sent for confirmation. Payouts continue to the current account until then.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final money = _money;

    if (money == null) {
      return _error == null
          ? const SizedBox.shrink()
          : Text(_error!, style: TextStyle(color: c.danger, fontSize: DsText.sm));
    }

    final open = money.open;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      BxCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Get paid', style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink)),
          const SizedBox(height: DsSpace.s2),
          if (open != null) ...[
            Text('You asked for ${SellerFormat.money(open.amount)}. The team will send it and add the bank reference here.',
                style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
            const SizedBox(height: DsSpace.s3),
            BxButton(
              label: 'Cancel request',
              variant: BxButtonVariant.secondary,
              size: BxButtonSize.sm,
              onPressed: _busy ? null : () => _run(() => widget.api.cancelPayout(open.id), 'Request cancelled.'),
            ),
          ] else if (money.blocker != null)
            Text(money.blocker!, style: TextStyle(fontSize: DsText.sm, color: c.inkMuted))
          else ...[
            Text('Payable now ${SellerFormat.money(money.withdrawable)}.', style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
            const SizedBox(height: DsSpace.s3),
            BxButton(
              label: 'Request payout',
              leadingIcon: Icons.account_balance_outlined,
              size: BxButtonSize.sm,
              onPressed: _busy || money.withdrawable <= 0 ? null : () => _request(money),
            ),
          ],
          for (final r in money.requests.take(5))
            Padding(
              padding: const EdgeInsets.only(top: DsSpace.s2),
              child: Text(
                '${SellerFormat.money(r.amount)} · ${r.statusLabel}'
                '${r.reference.isNotEmpty ? ' · ${r.reference}' : ''}'
                '${r.decisionNote.isNotEmpty ? ' · ${r.decisionNote}' : ''}',
                style: TextStyle(fontSize: DsText.xs, color: c.inkMuted),
              ),
            ),
        ]),
      ),
      const SizedBox(height: DsSpace.s3),
      BxCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bank account', style: TextStyle(fontSize: DsText.base, fontWeight: DsWeight.bold, color: c.ink)),
          const SizedBox(height: DsSpace.s2),
          Text(money.bank?.line ?? 'No bank account on file.', style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
          if (money.pendingBank != null) ...[
            const SizedBox(height: DsSpace.s2),
            Text('New account ending ${money.pendingBank!.last4} is waiting to be confirmed. Payouts stay on the current account until then.',
                style: TextStyle(fontSize: DsText.xs, color: c.warning)),
            TextButton(
              onPressed: _busy ? null : () => _run(widget.api.withdrawBankChange, 'Change withdrawn.'),
              child: const Text('Withdraw change'),
            ),
          ] else if (money.bank != null) ...[
            const SizedBox(height: DsSpace.s2),
            BxButton(
              label: 'Change bank account',
              variant: BxButtonVariant.secondary,
              size: BxButtonSize.sm,
              onPressed: _busy ? null : _changeBank,
            ),
          ],
        ]),
      ),
      const SizedBox(height: DsSpace.s3),
      BxButton(
        label: 'Monthly statements',
        leadingIcon: Icons.receipt_long_outlined,
        variant: BxButtonVariant.secondary,
        size: BxButtonSize.sm,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatementsScreen(api: widget.api))),
      ),
    ]);
  }
}

/// A month's takings and deductions, from the ledger.
class StatementsScreen extends StatefulWidget {
  final SellerApi api;

  const StatementsScreen({super.key, required this.api});

  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> {
  List<String> _months = [];
  String? _month;
  SellerStatement? _statement;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final months = await widget.api.statementMonths();
      if (!mounted) return;
      setState(() => _months = months);
      if (months.isNotEmpty) await _open(months.first);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load statements.');
    }
  }

  Future<void> _open(String month) async {
    setState(() {
      _month = month;
      _statement = null;
    });
    try {
      final s = await widget.api.statement(month);
      if (mounted) setState(() => _statement = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this statement.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final s = _statement;

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly statements')),
      body: ListView(padding: const EdgeInsets.all(DsSpace.s4), children: [
        if (_error != null) Text(_error!, style: TextStyle(color: c.danger)),
        if (_months.isNotEmpty)
          DropdownButtonFormField<String>(
            key: const Key('statement-month'),
            initialValue: _month,
            decoration: const InputDecoration(labelText: 'Month'),
            items: [for (final m in _months) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: (m) {
              if (m != null) _open(m);
            },
          ),
        const SizedBox(height: DsSpace.s4),
        if (s == null && _error == null) const Center(child: CircularProgressIndicator()),
        if (s != null)
          BxCard(
            child: Column(children: [
              SellerKeyValue('Opening balance', SellerFormat.money(s.opening)),
              SellerKeyValue('Orders', '${s.orders}'),
              SellerKeyValue('Gross sales', SellerFormat.money(s.grossSales)),
              SellerKeyValue('Refunds', '−${SellerFormat.money(s.refunds)}'),
              SellerKeyValue('Commission', '−${SellerFormat.money(s.commission)}'),
              SellerKeyValue('GST on commission', '−${SellerFormat.money(s.gst)}'),
              SellerKeyValue('TCS', '−${SellerFormat.money(s.tcs)}'),
              SellerKeyValue('TDS', '−${SellerFormat.money(s.tds)}'),
              SellerKeyValue('Earnings', SellerFormat.money(s.earnings)),
              SellerKeyValue('Adjustments', SellerFormat.money(s.adjustments)),
              SellerKeyValue('Paid out', '−${SellerFormat.money(s.payouts)}'),
              SellerKeyValue('Closing balance', SellerFormat.money(s.closing)),
            ]),
          ),
        const SizedBox(height: DsSpace.s3),
        Text(
          'Tax lines use the rates the marketplace had set at the time of each sale. They are for your records, not tax advice. '
          'A spreadsheet version is on the web dashboard.',
          style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
        ),
      ]),
    );
  }
}

/// Owns its field, so it is disposed with the dialog and not while it animates out.
class _RequestDialog extends StatefulWidget {
  final SellerMoney money;

  const _RequestDialog({required this.money});

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Request a payout'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Payable now ${SellerFormat.money(widget.money.withdrawable)}. Smallest request ${SellerFormat.money(widget.money.minimumPayout)}.'),
          const SizedBox(height: DsSpace.s3),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (leave empty for everything payable)', prefixText: '₹'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _amount.text.trim().isEmpty ? -1.0 : double.tryParse(_amount.text.trim())),
            child: const Text('Request'),
          ),
        ],
      );
}

class _BankDialog extends StatefulWidget {
  const _BankDialog();

  @override
  State<_BankDialog> createState() => _BankDialogState();
}

class _BankDialogState extends State<_BankDialog> {
  final _holder = TextEditingController();
  final _number = TextEditingController();
  final _ifsc = TextEditingController();
  final _bank = TextEditingController();

  @override
  void dispose() {
    _holder.dispose();
    _number.dispose();
    _ifsc.dispose();
    _bank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Change bank account'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _holder, decoration: const InputDecoration(labelText: 'Account holder')),
            TextField(controller: _number, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Account number')),
            TextField(controller: _ifsc, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'IFSC')),
            TextField(controller: _bank, decoration: const InputDecoration(labelText: 'Bank name (optional)')),
            const SizedBox(height: DsSpace.s2),
            const Text('The team confirms new bank details before any money moves to them.', style: TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_holder.text.trim(), _number.text.trim(), _ifsc.text.trim(), _bank.text.trim())),
            child: const Text('Send'),
          ),
        ],
      );
}
