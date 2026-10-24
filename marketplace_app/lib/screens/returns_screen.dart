import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// The shopper's return and exchange requests with refund progress.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

const _steps = ['REQUESTED', 'APPROVED', 'PICKUP_SCHEDULED', 'PICKED_UP', 'REFUNDED'];

const _stepLabels = {
  'REQUESTED': 'Requested',
  'APPROVED': 'Approved',
  'PICKUP_SCHEDULED': 'Pickup scheduled',
  'PICKED_UP': 'Picked up',
  'REFUNDED': 'Refunded',
  'REJECTED': 'Rejected',
};

class _ReturnsScreenState extends State<ReturnsScreen> {
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  String? _error;

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
      final data = await ApiClient.request('/returns/mine',
          token: AppState.instance.token);
      final list = data is Map ? (data['data'] ?? []) : data;
      if (!mounted) return;
      setState(() {
        _returns = (list as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
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
      appBar: AppBar(title: const Text('Returns & refunds')),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: BxSkeleton(height: 140, radius: DsRadius.cardAll),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load returns',
                  description: _error,
                  action: BxButton(label: 'Try again', onPressed: _load),
                )
              : _returns.isEmpty
                  ? const BxEmptyState(
                      icon: Icons.assignment_return_outlined,
                      title: 'No returns yet',
                      description:
                          'You can raise a return from any delivered order within 7 days.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: c.accent,
                      child: ListView(
                        padding: const EdgeInsets.all(DsSpace.s4),
                        children: _returns
                            .map((r) => Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: DsSpace.s3),
                                  child: _ReturnCard(data: r),
                                ))
                            .toList(),
                      ),
                    ),
    );
  }
}

class _ReturnCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReturnCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final status = data['status']?.toString() ?? 'REQUESTED';
    final rejected = status == 'REJECTED';
    final current = _steps.indexOf(status);
    final product = (data['order_item'] ?? data['orderItem'])?['product'];
    final title = product is Map ? product['title']?.toString() : null;
    final refund = data['refund_amount'];

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data['rma_number']?.toString() ?? 'Return',
                  style: TextStyle(
                      fontFamily: DsFont.mono,
                      fontSize: DsText.xs,
                      fontWeight: DsWeight.bold,
                      color: c.inkMuted),
                ),
              ),
              BxBadge(_stepLabels[status] ?? status,
                  tone: rejected
                      ? BxTone.danger
                      : status == 'REFUNDED'
                          ? BxTone.success
                          : BxTone.warning),
            ],
          ),
          if (title != null) ...[
            const SizedBox(height: DsSpace.s2),
            Text(title,
                style: TextStyle(
                    fontSize: DsText.base,
                    fontWeight: DsWeight.bold,
                    color: c.ink)),
          ],
          const SizedBox(height: DsSpace.s1),
          Text(
            '${data['kind'] == 'EXCHANGE' ? 'Exchange' : 'Return'} · ${data['reason'] ?? ''} · '
            'Raised ${formatDate(data['created_at']?.toString())}',
            style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
          ),
          const SizedBox(height: DsSpace.s3),
          if (rejected)
            BxAlert(
              (data['admin_note'] ?? 'This request was not approved.').toString(),
              title: 'Return rejected',
              tone: BxTone.danger,
            )
          else ...[
            Row(
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  Icon(
                    i <= current
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: i <= current ? c.success : c.lineStrong,
                  ),
                  if (i < _steps.length - 1)
                    Expanded(
                      child: Container(
                          height: 2,
                          color: i < current ? c.success : c.line),
                    ),
                ],
              ],
            ),
            const SizedBox(height: DsSpace.s2),
            Text(
              _stepLabels[_steps[current < 0 ? 0 : current]]!,
              style: TextStyle(fontSize: DsText.xs, color: c.inkMuted),
            ),
            if (data['pickup_tracking_no'] != null) ...[
              const SizedBox(height: DsSpace.s2),
              Text('Pickup tracking: ${data['pickup_tracking_no']}',
                  style: TextStyle(
                      fontFamily: DsFont.mono,
                      fontSize: DsText.xs,
                      color: c.inkMuted)),
            ],
            if (status == 'REFUNDED' && refund != null) ...[
              const SizedBox(height: DsSpace.s3),
              BxAlert(
                '${formatMoney(double.tryParse('$refund') ?? 0)} refunded '
                '${data['refund_mode'] == 'WALLET' ? 'to your wallet.' : 'to your original payment method — expect it within 5–7 business days.'}',
                tone: BxTone.success,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
