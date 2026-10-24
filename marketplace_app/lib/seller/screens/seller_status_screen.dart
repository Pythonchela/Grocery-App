import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_format.dart';
import '../seller_host.dart';
import '../seller_models.dart';

/// Shown while the application is out of the seller's hands: under review,
/// approved but not yet switched on, or the account suspended.
class SellerStatusScreen extends StatelessWidget {
  final Onboarding onboarding;
  final SellerHost host;
  final Future<void> Function() onRefresh;

  const SellerStatusScreen({super.key, required this.onboarding, required this.host, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final suspended = onboarding.account.standing == SellerStanding.suspended;
    final approved = onboarding.kyc.status == KycStatus.approved;

    final (icon, title, body, tone) = suspended
        ? (
            Icons.block,
            'Your seller account is suspended',
            'You cannot sell while the suspension is in place.'
                '${host.supportEmail != null ? ' Contact ${host.supportEmail} for help.' : ' Contact support for help.'}',
            BxTone.danger,
          )
        : approved
            ? (
                Icons.verified_outlined,
                'You are verified',
                'Your details have been approved. Your shop will be switched on shortly — pull down to check again.',
                BxTone.success,
              )
            : (
                Icons.hourglass_top,
                'Your application is under review',
                'We are checking your details and documents. We usually respond within two business days, '
                    'and you will be notified when there is news.',
                BxTone.info,
              );

    return Scaffold(
      appBar: AppBar(title: const Text('Seller application')),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        color: c.accent,
        child: ListView(
          // Always scrollable, or pull-to-refresh does nothing on a short page.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DsSpace.s4),
          children: [
            const SizedBox(height: DsSpace.s8),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: c.surfaceSunken, shape: BoxShape.circle),
                child: Icon(icon, size: 34, color: c.ink),
              ),
            ),
            const SizedBox(height: DsSpace.s5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: DsText.xl, fontWeight: DsWeight.black, color: c.ink),
            ),
            const SizedBox(height: DsSpace.s2),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
            const SizedBox(height: DsSpace.s6),
            BxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          onboarding.account.displayName,
                          style: TextStyle(fontSize: DsText.md, fontWeight: DsWeight.black, color: c.ink),
                        ),
                      ),
                      BxBadge(_label(suspended, approved), tone: tone),
                    ],
                  ),
                  const SizedBox(height: DsSpace.s2),
                  if (onboarding.kyc.submittedAt != null)
                    Text(
                      'Submitted on ${SellerFormat.date(onboarding.kyc.submittedAt)}',
                      style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: DsSpace.s4),
            Text(
              'Pull down to check for updates.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
            ),
          ],
        ),
      ),
    );
  }

  String _label(bool suspended, bool approved) => suspended
      ? 'Suspended'
      : approved
          ? 'Verified'
          : 'In review';
}
