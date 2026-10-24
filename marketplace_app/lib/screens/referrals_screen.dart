import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/brand.g.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// Refer & earn: the shopper's code, a share action and the invite tally.
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  Map<String, dynamic>? _data;
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
      final data = await ApiClient.request('/referrals',
          token: AppState.instance.token) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = data;
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

  String get _message {
    final d = _data!;
    return 'Join me on ${DsBrand.name}! Sign up with my referral code '
        '${d['code']} and get ${formatMoney(_num(d['referee_reward']))} off '
        'your first order.';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: '${_data!['code']}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Referral code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(title: const Text('Refer & earn')),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: BxSkeleton(height: 180, radius: DsRadius.cardAll),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load referrals',
                  description: _error,
                  action: BxButton(label: 'Try again', onPressed: _load),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: c.accent,
                  child: ListView(
                    padding: const EdgeInsets.all(DsSpace.s4),
                    children: [
                      BxCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.card_giftcard, color: c.accent),
                            const SizedBox(height: DsSpace.s2),
                            Text('Your referral code',
                                style: TextStyle(
                                    fontSize: DsText.sm, color: c.inkMuted)),
                            Text('${_data!['code']}',
                                style: TextStyle(
                                    fontFamily: DsFont.mono,
                                    fontSize: DsText.x2xl,
                                    fontWeight: DsWeight.black,
                                    color: c.ink)),
                            const SizedBox(height: DsSpace.s2),
                            Text(
                              'You earn ${formatMoney(_num(_data!['referrer_reward']))} and they get '
                              '${formatMoney(_num(_data!['referee_reward']))} off, once their first order is delivered.',
                              style: TextStyle(
                                  fontSize: DsText.base, color: c.inkMuted),
                            ),
                            const SizedBox(height: DsSpace.s4),
                            Row(
                              children: [
                                Expanded(
                                  child: BxButton(
                                    label: 'Share',
                                    leadingIcon: Icons.ios_share,
                                    fullWidth: true,
                                    onPressed: () => SharePlus.instance
                                        .share(ShareParams(text: _message)),
                                  ),
                                ),
                                const SizedBox(width: DsSpace.s2),
                                Expanded(
                                  child: BxButton(
                                    label: 'Copy code',
                                    leadingIcon: Icons.copy,
                                    variant: BxButtonVariant.secondary,
                                    fullWidth: true,
                                    onPressed: _copy,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: DsSpace.s3),
                      Row(
                        children: [
                          Expanded(
                            child: _Stat(
                              icon: Icons.currency_rupee,
                              value: formatMoney(_num(_data!['total_earned'])),
                              label: 'Total earned',
                            ),
                          ),
                          const SizedBox(width: DsSpace.s3),
                          Expanded(
                            child: _Stat(
                              icon: Icons.hourglass_empty,
                              value: '${_data!['pending_count'] ?? 0}',
                              label: 'Awaiting first order',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DsSpace.s5),
                      Text("People you've invited",
                          style: TextStyle(
                              fontSize: DsText.lg,
                              fontWeight: DsWeight.black,
                              color: c.ink)),
                      const SizedBox(height: DsSpace.s3),
                      ..._invites(c),
                    ],
                  ),
                ),
    );
  }

  List<Widget> _invites(DsColors c) {
    final invites = (_data!['invites'] as List? ?? []).cast<Map<String, dynamic>>();
    if (invites.isEmpty) {
      return const [
        BxEmptyState(
          icon: Icons.group_add_outlined,
          title: 'Nobody yet',
          description: 'Share your code to start earning.',
        )
      ];
    }
    return invites.map((inv) {
      final rewarded = inv['status'] == 'REWARDED';
      return Padding(
        padding: const EdgeInsets.only(bottom: DsSpace.s3),
        child: BxCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${inv['name']}',
                        style: TextStyle(
                            fontWeight: DsWeight.bold, color: c.ink)),
                    Text('Joined ${formatDate(inv['joined_at']?.toString())}',
                        style:
                            TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BxBadge(rewarded ? 'Rewarded' : 'Pending first order',
                      tone: rewarded ? BxTone.success : BxTone.warning),
                  if (rewarded)
                    Text('+${formatMoney(_num(inv['reward']))}',
                        style: TextStyle(
                            fontSize: DsText.xs,
                            fontWeight: DsWeight.bold,
                            color: c.success)),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Stat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(height: DsSpace.s2),
          Text(value,
              style: TextStyle(
                  fontSize: DsText.lg,
                  fontWeight: DsWeight.black,
                  color: c.ink)),
          Text(label,
              style: TextStyle(fontSize: DsText.x2xs, color: c.inkSubtle)),
        ],
      ),
    );
  }
}
