import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../document_picker.dart';
import '../seller_api.dart';
import '../seller_models.dart';
import '../widgets/seller_widgets.dart';

/// The seller's shop page, as shoppers see it when they browse shops: a logo and
/// banner, a line about the shop, when it is open, the smallest basket it will
/// deliver, how long it takes to get an order ready, and the PIN codes it covers.
///
/// Pops with `true` once saved, so the dashboard behind it reloads.
class ShopProfileScreen extends StatefulWidget {
  final SellerApi api;
  final DocumentPicker picker;
  final ShopProfile shop;

  const ShopProfileScreen({super.key, required this.api, required this.picker, required this.shop});

  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  static const _dayNames = {
    'mon': 'Monday',
    'tue': 'Tuesday',
    'wed': 'Wednesday',
    'thu': 'Thursday',
    'fri': 'Friday',
    'sat': 'Saturday',
    'sun': 'Sunday',
  };

  late final _tagline = TextEditingController(text: widget.shop.tagline);
  late final _about = TextEditingController(text: widget.shop.about);
  late final _minOrder = TextEditingController(
      text: widget.shop.minOrderAmount <= 0 ? '' : _plain(widget.shop.minOrderAmount));
  late final _prep = TextEditingController(text: widget.shop.prepMinutes?.toString() ?? '');
  late final _pincodes = TextEditingController(text: widget.shop.servicePincodes.join('\n'));

  late String? _logo = widget.shop.logoUrl;
  late String? _banner = widget.shop.bannerUrl;
  late bool _accepting = widget.shop.acceptingOrders;
  late bool _always = widget.shop.openingHours == null;
  late final Map<String, HoursSlot?> _hours = {
    for (final day in ShopProfile.days)
      day: widget.shop.openingHours == null
          ? const HoursSlot('09:00', '21:00')
          : widget.shop.openingHours![day],
  };

  bool _busy = false;
  String? _uploading; // 'logo' | 'banner'
  String? _error;
  final Map<String, String> _errors = {};

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    for (final c in [_tagline, _about, _minOrder, _prep, _pincodes]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Pictures ──────────────────────────────────────────────────────────────

  Future<void> _pick(String which) async {
    final PickedDocument? file;
    try {
      file = await widget.picker.pick(extensions: PhotoRules.allowedExtensions);
    } catch (_) {
      setState(() => _errors[which] = 'Could not open the photo picker.');
      return;
    }
    if (file == null || !mounted) return;

    final problem = PhotoRules.problemWith(file);
    if (problem != null) {
      setState(() => _errors[which] = problem);
      return;
    }

    setState(() {
      _uploading = which;
      _errors.remove(which);
    });
    try {
      final url = await widget.api.uploadImage(file);
      if (!mounted) return;
      setState(() {
        which == 'logo' ? _logo = url : _banner = url;
        _uploading = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _uploading = null;
          _errors[which] = e.fieldError('file') ?? e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploading = null;
          _errors[which] = 'Could not upload. Try again.';
        });
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  /// The PIN codes typed, one per line or separated by commas or spaces.
  List<String> get _pincodeList => _pincodes.text
      .split(RegExp(r'[\s,;]+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _save() async {
    final errors = <String, String>{};

    final minimum = _minOrder.text.trim().isEmpty ? 0.0 : double.tryParse(_minOrder.text.trim().replaceAll(',', ''));
    if (minimum == null || minimum < 0) errors['min'] = 'Enter an amount in rupees, or leave it empty for no minimum.';

    final prep = _prep.text.trim().isEmpty ? null : int.tryParse(_prep.text.trim());
    if (_prep.text.trim().isNotEmpty && (prep == null || prep < 0 || prep > 1440)) {
      errors['prep'] = 'Enter a number of minutes, up to 1440.';
    }

    final pins = _pincodeList;
    if (pins.any((p) => !RegExp(r'^[1-9][0-9]{5}$').hasMatch(p))) {
      errors['pins'] = 'PIN codes are six digits, one per line.';
    }

    if (!_always) {
      for (final e in _hours.entries) {
        final slot = e.value;
        if (slot != null && slot.open == slot.close) {
          errors['hours'] = '${_dayNames[e.key]} opens and closes at the same time. Mark it closed or change a time.';
        }
      }
    }

    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _error = errors.isEmpty ? null : 'Fix the highlighted fields and try again.';
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await widget.api.updateShop(ShopProfile(
        logoUrl: _logo,
        bannerUrl: _banner,
        tagline: _tagline.text,
        about: _about.text,
        openingHours: _always ? null : Map.of(_hours),
        acceptingOrders: _accepting,
        minOrderAmount: minimum ?? 0,
        servicePincodes: pins,
        prepMinutes: prep,
      ));
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.errors == null ? e.message : 'Fix the highlighted fields and try again.';
        for (final f in (e.errors ?? {}).entries) {
          final key = f.key.startsWith('service_pincodes')
              ? 'pins'
              : f.key.startsWith('opening_hours')
                  ? 'hours'
                  : f.key == 'min_order_amount'
                      ? 'min'
                      : f.key == 'prep_minutes'
                          ? 'prep'
                          : f.key;
          _errors[key] = f.value.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  // ── Opening hours ─────────────────────────────────────────────────────────

  /// Every half hour of the day, plus any odd time the shop already has.
  List<String> _timeChoices(Iterable<String> extra) {
    final all = <String>{
      for (var h = 0; h < 24; h++) ...['${h.toString().padLeft(2, '0')}:00', '${h.toString().padLeft(2, '0')}:30'],
      ...extra,
    }.toList()
      ..sort();
    return all;
  }

  static String _clock(String hhmm) {
    final h = int.parse(hhmm.substring(0, 2));
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${hhmm.substring(3, 5)} ${h < 12 ? 'AM' : 'PM'}';
  }

  Widget _timePicker(String label, String value, ValueChanged<String> onChanged) {
    final choices = _timeChoices([value]);

    return Expanded(
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final t in choices) DropdownMenuItem(value: t, child: Text(_clock(t))),
        ],
        onChanged: _busy ? null : (v) => v == null ? null : onChanged(v),
      ),
    );
  }

  Widget _hoursEditor(BuildContext context) {
    final c = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Always open'),
          subtitle: const Text('No set hours; shoppers can order any time.'),
          value: _always,
          onChanged: _busy ? null : (v) => setState(() => _always = v),
        ),
        if (!_always) ...[
          for (final day in ShopProfile.days)
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_dayNames[day]!,
                            style: TextStyle(
                                fontSize: DsText.base, fontWeight: DsWeight.semibold, color: c.ink)),
                      ),
                      Text(_hours[day] == null ? 'Closed' : 'Open',
                          style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
                      Switch(
                        value: _hours[day] != null,
                        onChanged: _busy
                            ? null
                            : (open) => setState(
                                () => _hours[day] = open ? const HoursSlot('09:00', '21:00') : null),
                      ),
                    ],
                  ),
                  if (_hours[day] != null)
                    Row(
                      children: [
                        _timePicker('Opens', _hours[day]!.open,
                            (v) => setState(() => _hours[day] = HoursSlot(v, _hours[day]!.close))),
                        const SizedBox(width: DsSpace.s3),
                        _timePicker('Closes', _hours[day]!.close,
                            (v) => setState(() => _hours[day] = HoursSlot(_hours[day]!.open, v))),
                      ],
                    ),
                ],
              ),
            ),
          Text(
            'A closing time earlier than the opening time means the shop stays open past midnight.',
            style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle),
          ),
          if (_errors['hours'] != null) ...[
            const SizedBox(height: DsSpace.s1),
            Text(_errors['hours']!, style: TextStyle(fontSize: DsText.xs, color: c.danger)),
          ],
        ],
      ],
    );
  }

  Widget _picture(BuildContext context, String which, String label, String? url, {required bool round}) {
    final c = context.ds;
    final busy = _uploading == which;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: DsText.xs, fontWeight: DsWeight.bold, color: c.inkMuted)),
        const SizedBox(height: DsSpace.s1 + 2),
        Row(
          children: [
            Container(
              width: round ? 64 : 120,
              height: 64,
              decoration: BoxDecoration(
                color: c.surfaceSunken,
                shape: round ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: round ? null : DsRadius.controlAll,
              ),
              clipBehavior: Clip.antiAlias,
              child: url == null
                  ? Icon(Icons.image_outlined, color: c.inkSubtle)
                  : Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported_outlined, color: c.inkSubtle)),
            ),
            const SizedBox(width: DsSpace.s3),
            Wrap(
              spacing: DsSpace.s2,
              children: [
                BxButton(
                  label: busy ? 'Uploading…' : (url == null ? 'Add' : 'Change'),
                  size: BxButtonSize.sm,
                  variant: BxButtonVariant.secondary,
                  onPressed: busy || _busy ? null : () => _pick(which),
                ),
                if (url != null)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => which == 'logo' ? _logo = null : _banner = null),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ],
        ),
        if (_errors[which] != null) ...[
          const SizedBox(height: DsSpace.s1),
          Text(_errors[which]!, style: TextStyle(fontSize: DsText.xs, color: c.danger)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(title: const Text('Shop page')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DsSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    BxAlert(_error!, title: 'Could not save', tone: BxTone.danger),
                    const SizedBox(height: DsSpace.s4),
                  ],
                  const SellerSectionTitle('Taking orders',
                      subtitle: 'Pause the shop when you are too busy. Shoppers can still look around.'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_accepting ? 'Taking orders' : 'Paused'),
                    value: _accepting,
                    onChanged: _busy ? null : (v) => setState(() => _accepting = v),
                  ),
                  const SizedBox(height: DsSpace.s4),
                  const SellerSectionTitle('How your shop looks'),
                  _picture(context, 'logo', 'Logo', _logo, round: true),
                  const SizedBox(height: DsSpace.s4),
                  _picture(context, 'banner', 'Banner', _banner, round: false),
                  const SizedBox(height: DsSpace.s4),
                  BxField(
                    label: 'Tagline (optional)',
                    hint: 'Fresh groceries since 1990',
                    controller: _tagline,
                    enabled: !_busy,
                  ),
                  const SizedBox(height: DsSpace.s4),
                  BxField(
                    label: 'About your shop (optional)',
                    controller: _about,
                    maxLines: 4,
                    enabled: !_busy,
                  ),
                  const SizedBox(height: DsSpace.s5),
                  const SellerSectionTitle('Orders',
                      subtitle: 'What your shop asks of an order.'),
                  BxField(
                    label: 'Minimum order (₹)',
                    hint: 'Leave empty for no minimum',
                    controller: _minOrder,
                    keyboardType: TextInputType.number,
                    error: _errors['min'],
                    enabled: !_busy,
                  ),
                  const SizedBox(height: DsSpace.s4),
                  BxField(
                    label: 'Usually ready in (minutes)',
                    controller: _prep,
                    keyboardType: TextInputType.number,
                    error: _errors['prep'],
                    enabled: !_busy,
                  ),
                  const SizedBox(height: DsSpace.s4),
                  BxField(
                    label: 'PIN codes you deliver to',
                    hint: 'One per line. Leave empty to deliver anywhere a courier can go.',
                    controller: _pincodes,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    error: _errors['pins'],
                    enabled: !_busy,
                  ),
                  const SizedBox(height: DsSpace.s5),
                  const SellerSectionTitle('Opening hours'),
                  _hoursEditor(context),
                  const SizedBox(height: DsSpace.s6),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(DsSpace.s4),
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
              child: BxButton(
                label: 'Save shop page',
                fullWidth: true,
                size: BxButtonSize.lg,
                loading: _busy,
                onPressed: _busy || _uploading != null ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
