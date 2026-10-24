import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// Address book. Doubles as the picker during checkout — `selectMode` swaps the
/// tap action from "edit" to "choose and pop", so there is one screen rather
/// than two that drift.
class AddressScreen extends StatefulWidget {
  final bool selectMode;

  const AddressScreen({super.key, this.selectMode = false});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  List<Address> _addresses = [];
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
      final data = await ApiClient.request('/addresses', token: AppState.instance.token);
      if (!mounted) return;
      setState(() {
        _addresses = (data as List).map((a) => Address.fromJson(a)).toList();
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

  Future<void> _delete(Address address) async {
    final confirmed = await showBxSheet<bool>(
      context: context,
      title: 'Delete this address?',
      child: Text(
        address.oneLine,
        style: TextStyle(fontSize: DsText.base, color: context.ds.inkMuted),
      ),
      footer: Row(
        children: [
          Expanded(
            child: BxButton(
              label: 'Keep',
              variant: BxButtonVariant.secondary,
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: BxButton(
              label: 'Delete',
              variant: BxButtonVariant.danger,
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient.request(
        '/addresses/${address.id}',
        method: 'DELETE',
        token: AppState.instance.token,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _openForm({Address? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddressFormScreen(existing: existing)),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectMode ? 'Deliver to' : 'Saved addresses'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
        onPressed: () => _openForm(),
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: Column(
                children: [
                  BxSkeleton(height: 108, radius: DsRadius.cardAll),
                  SizedBox(height: DsSpace.s3),
                  BxSkeleton(height: 108, radius: DsRadius.cardAll),
                ],
              ),
            )
          : _error != null
              ? BxEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Could not load addresses',
                  description: _error,
                  action: BxButton(label: 'Retry', onPressed: _load),
                )
              : _addresses.isEmpty
                  ? BxEmptyState(
                      icon: Icons.location_on_outlined,
                      title: 'No saved addresses',
                      description: 'Add one so we know where to deliver.',
                      action: BxButton(label: 'Add address', onPressed: () => _openForm()),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s16),
                      itemCount: _addresses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: DsSpace.s3),
                      itemBuilder: (context, i) {
                        final a = _addresses[i];
                        return BxCard(
                          onTap: widget.selectMode ? () => Navigator.of(context).pop(a) : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (a.tag != null && a.tag!.isNotEmpty) ...[
                                    BxBadge(a.tag!, tone: BxTone.accent),
                                    const SizedBox(width: DsSpace.s2),
                                  ],
                                  if (a.isDefault) const BxBadge('Default', tone: BxTone.success),
                                  const Spacer(),
                                  if (!widget.selectMode) ...[
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      tooltip: 'Edit address',
                                      color: c.inkMuted,
                                      onPressed: () => _openForm(existing: a),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      tooltip: 'Delete address',
                                      color: c.danger,
                                      onPressed: () => _delete(a),
                                    ),
                                  ] else
                                    Icon(Icons.chevron_right, color: c.inkSubtle),
                                ],
                              ),
                              const SizedBox(height: DsSpace.s2),
                              Text(
                                a.name,
                                style: TextStyle(
                                  fontSize: DsText.base,
                                  fontWeight: DsWeight.black,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                a.oneLine,
                                style: TextStyle(
                                  fontSize: DsText.base,
                                  height: DsText.baseHeight,
                                  color: c.inkMuted,
                                ),
                              ),
                              const SizedBox(height: DsSpace.s1),
                              Text(
                                a.phone,
                                style: TextStyle(
                                  fontFamily: DsFont.mono,
                                  fontSize: DsText.xs,
                                  color: c.inkSubtle,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}

class AddressFormScreen extends StatefulWidget {
  final Address? existing;

  const AddressFormScreen({super.key, this.existing});

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  late final _tag = TextEditingController(text: widget.existing?.tag ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _line1 = TextEditingController(text: widget.existing?.line1 ?? '');
  late final _line2 = TextEditingController(text: widget.existing?.line2 ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _state = TextEditingController(text: widget.existing?.state ?? '');
  late final _pincode = TextEditingController(text: widget.existing?.pincode ?? '');

  late bool _isDefault = widget.existing?.isDefault ?? false;
  bool _saving = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  /// Pincode serviceability, checked as it is typed. Telling someone we do not
  /// deliver to their pincode *before* they finish the form is considerably
  /// kinder than failing at the payment step.
  String? _serviceabilityNote;
  bool _serviceable = true;

  @override
  void dispose() {
    for (final c in [_tag, _name, _phone, _line1, _line2, _city, _state, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkPincode(String value) async {
    if (value.length != 6) {
      setState(() => _serviceabilityNote = null);
      return;
    }

    try {
      final data = await ApiClient.request(
        '/serviceability',
        method: 'POST',
        body: {'pincode': value},
      ) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _serviceable = data['serviceable'] == true;
        _serviceabilityNote = data['message'] as String?;
      });
    } catch (_) {
      // A serviceability outage must not block someone saving an address.
    }
  }

  bool _validate() {
    _fieldErrors.clear();

    if (_name.text.trim().isEmpty) _fieldErrors['name'] = 'Required.';
    if (!RegExp(r'^[0-9]{10}$').hasMatch(_phone.text.trim())) {
      _fieldErrors['phone'] = 'Enter a 10-digit mobile number.';
    }
    if (_line1.text.trim().isEmpty) _fieldErrors['line1'] = 'Required.';
    if (_city.text.trim().isEmpty) _fieldErrors['city'] = 'Required.';
    if (_state.text.trim().isEmpty) _fieldErrors['state'] = 'Required.';
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(_pincode.text.trim())) {
      _fieldErrors['pincode'] = 'Enter a valid 6-digit pincode.';
    }

    setState(() {});
    return _fieldErrors.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = {
      'tag': _tag.text.trim().isEmpty ? null : _tag.text.trim(),
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'line1': _line1.text.trim(),
      'line2': _line2.text.trim().isEmpty ? null : _line2.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'pincode': _pincode.text.trim(),
      'is_default': _isDefault,
    };

    try {
      await ApiClient.request(
        widget.existing == null ? '/addresses' : '/addresses/${widget.existing!.id}',
        method: widget.existing == null ? 'POST' : 'PUT',
        token: AppState.instance.token,
        body: payload,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add address' : 'Edit address')),
      body: ListView(
        padding: const EdgeInsets.all(DsSpace.s4),
        children: [
          if (_error != null) ...[
            BxAlert(_error!, tone: BxTone.danger),
            const SizedBox(height: DsSpace.s4),
          ],
          BxField(
            label: 'Label',
            hint: 'Home, Work…',
            controller: _tag,
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Full name',
            controller: _name,
            error: _fieldErrors['name'],
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Mobile number',
            controller: _phone,
            keyboardType: TextInputType.phone,
            error: _fieldErrors['phone'],
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Address line 1',
            hint: 'Flat, house no., building',
            controller: _line1,
            error: _fieldErrors['line1'],
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Address line 2',
            hint: 'Area, landmark (optional)',
            controller: _line2,
          ),
          const SizedBox(height: DsSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BxField(
                  label: 'City',
                  controller: _city,
                  error: _fieldErrors['city'],
                ),
              ),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: BxField(
                  label: 'State',
                  controller: _state,
                  error: _fieldErrors['state'],
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s4),
          BxField(
            label: 'Pincode',
            controller: _pincode,
            keyboardType: TextInputType.number,
            error: _fieldErrors['pincode'],
            helper: _serviceabilityNote,
            onChanged: _checkPincode,
          ),
          if (_serviceabilityNote != null && !_serviceable) ...[
            const SizedBox(height: DsSpace.s3),
            BxAlert(_serviceabilityNote!, tone: BxTone.warning),
          ],
          const SizedBox(height: DsSpace.s4),
          Row(
            children: [
              Switch(
                value: _isDefault,
                activeThumbColor: c.accent,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
              const SizedBox(width: DsSpace.s2),
              Expanded(
                child: Text(
                  'Use as my default delivery address',
                  style: TextStyle(fontSize: DsText.base, color: c.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s6),
          BxButton(
            label: widget.existing == null ? 'Save address' : 'Update address',
            size: BxButtonSize.lg,
            fullWidth: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
