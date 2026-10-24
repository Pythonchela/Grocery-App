import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../design/components.dart';
import '../design/tokens.g.dart';
import 'document_picker.dart';
import 'screens/become_seller_screen.dart';
import 'screens/onboarding_wizard.dart';
import 'screens/seller_dashboard.dart';
import 'screens/seller_status_screen.dart';
import 'seller_api.dart';
import 'seller_host.dart';
import 'seller_models.dart';
import 'widgets/seller_widgets.dart';

/// Where an account stands with selling, for a host's menu to label its entry
/// ("Seller dashboard", "Application in review"...) without opening the area.
enum SellerStage {
  /// Never applied.
  none,

  /// Applied, details unfinished or sent back.
  applying,

  /// Submitted and waiting for the marketplace.
  inReview,

  /// Approved and selling.
  active,
  suspended,

  /// Could not be worked out (offline, server trouble): show the neutral entry.
  unknown,
}

/// The single entry point to everything seller-related.
///
/// It asks the API where this account stands and shows the matching screen:
///
///   no merchant account          → apply
///   account, details unfinished  → the guided application
///   application under review     → status (pull to refresh)
///   approved and active           → the dashboard
///   suspended                     → status
///
/// The host app just pushes this widget. A standalone seller app would make it
/// its `home:`.
class SellerArea extends StatefulWidget {
  final SellerHost host;

  /// Injectable for tests and for a different transport; defaults to the API.
  final SellerApi? api;
  final DocumentPicker picker;

  const SellerArea({
    super.key,
    required this.host,
    this.api,
    this.picker = const FilePickerDocumentPicker(),
  });

  /// One quick question to the API: where does this account stand?
  /// Never throws; anything unexpected is [SellerStage.unknown].
  static Future<SellerStage> stage(SellerHost host, {SellerApi? api}) async {
    try {
      final ob = await (api ?? HttpSellerApi(host)).onboarding();
      if (ob == null) return SellerStage.none;

      return switch (ob.account.standing) {
        SellerStanding.active => SellerStage.active,
        SellerStanding.suspended => SellerStage.suspended,
        SellerStanding.pending => switch (ob.kyc.status) {
            KycStatus.draft || KycStatus.rejected => SellerStage.applying,
            KycStatus.submitted || KycStatus.approved => SellerStage.inReview,
          },
      };
    } catch (_) {
      return SellerStage.unknown;
    }
  }

  /// Convenience for the host: open the seller area as a full-screen route.
  static Future<void> open(BuildContext context, SellerHost host) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SellerArea(host: host)));

  /// Staff in single-business mode operate the house shop without applying as
  /// an outside seller. The server checks both their staff role and store mode.
  static Future<void> openHouse(BuildContext context, SellerHost host, String shopName) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => house(host, shopName)));

  /// The house shop's dashboard as a widget, for a seller app whose staff land on it.
  static Widget house(SellerHost host, String shopName, {SellerApi? api, DocumentPicker? picker}) => SellerDashboard(
        api: api ?? HttpSellerApi(host), host: host, shopName: shopName,
        picker: picker ?? const FilePickerDocumentPicker(),
      );

  @override
  State<SellerArea> createState() => _SellerAreaState();
}

class _SellerAreaState extends State<SellerArea> {
  late final SellerApi _api = widget.api ?? HttpSellerApi(widget.host);

  Onboarding? _onboarding;
  bool _loading = true;
  bool _notASeller = false;
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
      final ob = await _api.onboarding();
      if (!mounted) return;
      setState(() {
        _onboarding = ob;
        _notASeller = ob == null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  void _update(Onboarding ob) => setState(() {
        _onboarding = ob;
        _notASeller = false;
      });

  @override
  Widget build(BuildContext context) {
    if (_loading && _onboarding == null && !_notASeller) {
      return Scaffold(
        appBar: AppBar(title: Text('Sell on ${widget.host.marketplaceName}')),
        body: const Padding(
          padding: EdgeInsets.all(DsSpace.s4),
          child: Column(children: [
            BxSkeleton(height: 120, radius: DsRadius.cardAll),
            SizedBox(height: DsSpace.s3),
            BxSkeleton(height: 120, radius: DsRadius.cardAll),
          ]),
        ),
      );
    }

    if (_error != null && _onboarding == null && !_notASeller) {
      return Scaffold(
        appBar: AppBar(title: Text('Sell on ${widget.host.marketplaceName}')),
        body: SellerLoadError(message: _error!, onRetry: _load),
      );
    }

    if (_notASeller) {
      return BecomeSellerScreen(api: _api, host: widget.host, onApplied: _update);
    }

    final ob = _onboarding!;
    final standing = ob.account.standing;

    if (standing == SellerStanding.active) {
      return SellerDashboard(api: _api, host: widget.host, shopName: ob.account.displayName, picker: widget.picker);
    }

    if (standing == SellerStanding.suspended) {
      return SellerStatusScreen(onboarding: ob, host: widget.host, onRefresh: _load);
    }

    // PENDING: the application is either still the seller's to complete, or out
    // of their hands.
    return switch (ob.kyc.status) {
      KycStatus.draft || KycStatus.rejected => OnboardingWizard(
          api: _api,
          picker: widget.picker,
          onboarding: ob,
          onChanged: _update,
        ),
      KycStatus.submitted || KycStatus.approved => SellerStatusScreen(
          onboarding: ob,
          host: widget.host,
          onRefresh: _load,
        ),
    };
  }
}
