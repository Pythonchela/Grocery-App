import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';
import '../widgets/theme_picker.dart';

/// Profile details, password and notification preferences — the mobile twin of
/// the web `/account/profile` and the preferences block on `/account/notifications`.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

const _notificationTypes = <String, String>{
  'ORDER_UPDATE': 'Order updates',
  'REFUND': 'Refunds',
  'PRICE_DROP': 'Price drops',
  'BACK_IN_STOCK': 'Back in stock',
  'REVIEW_REQUEST': 'Review requests',
  'PROMO': 'Deals & promotions',
};

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();

  Map<String, bool> _prefs = {};
  bool _loading = true;
  bool _savingProfile = false;
  bool _savingPassword = false;
  String? _loadError;
  String? _profileMsg;
  String? _profileError;
  String? _passwordMsg;
  String? _passwordError;
  String? _prefsError;

  String? get _token => AppState.instance.token;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data =
          await ApiClient.request('/profile', token: _token) as Map<String, dynamic>;
      final raw = data['notification_preferences'];
      if (!mounted) return;
      setState(() {
        _name.text = data['name']?.toString() ?? '';
        _email.text = data['email']?.toString() ?? '';
        _phone.text = data['phone']?.toString() ?? '';
        _prefs = {
          for (final key in _notificationTypes.keys)
            key: raw is Map ? raw[key] != false : true,
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _savingProfile = true;
      _profileMsg = null;
      _profileError = null;
    });
    try {
      final data = await ApiClient.request(
        '/profile',
        method: 'PUT',
        token: _token,
        body: {
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        },
      ) as Map<String, dynamic>;
      AppState.instance.updateUser(AuthUser.fromJson(data));
      if (mounted) setState(() => _profileMsg = 'Profile updated.');
    } catch (e) {
      if (mounted) setState(() => _profileError = e.toString());
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePassword() async {
    if (_newPassword.text.length < 8) {
      setState(() {
        _passwordMsg = null;
        _passwordError = 'The new password must be at least 8 characters.';
      });
      return;
    }
    setState(() {
      _savingPassword = true;
      _passwordMsg = null;
      _passwordError = null;
    });
    try {
      await ApiClient.request(
        '/profile/password',
        method: 'PUT',
        token: _token,
        body: {
          'current_password': _currentPassword.text,
          'new_password': _newPassword.text,
        },
      );
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      setState(() => _passwordMsg = 'Password changed.');
    } catch (e) {
      if (mounted) setState(() => _passwordError = e.toString());
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _togglePref(String key, bool value) async {
    final previous = Map<String, bool>.of(_prefs);
    setState(() {
      _prefs[key] = value;
      _prefsError = null;
    });
    try {
      await ApiClient.request(
        '/profile/notifications',
        method: 'PUT',
        token: _token,
        body: {'preferences': _prefs},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _prefs = previous;
        _prefsError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    Widget title(String text) => Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s3),
          child: Text(text,
              style: TextStyle(
                  fontSize: DsText.md,
                  fontWeight: DsWeight.black,
                  color: c.ink)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(DsSpace.s4),
              child: BxSkeleton(height: 240, radius: DsRadius.cardAll),
            )
          : _loadError != null
              ? BxEmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load your profile',
                  description: _loadError,
                  action: BxButton(label: 'Try again', onPressed: _load),
                )
              : ListView(
                  padding: const EdgeInsets.all(DsSpace.s4),
                  children: [
                    BxCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title('Profile details'),
                          if (_profileMsg != null) ...[
                            BxAlert(_profileMsg!, tone: BxTone.success),
                            const SizedBox(height: DsSpace.s3),
                          ],
                          if (_profileError != null) ...[
                            BxAlert(_profileError!, tone: BxTone.danger),
                            const SizedBox(height: DsSpace.s3),
                          ],
                          BxField(label: 'Full name', controller: _name),
                          const SizedBox(height: DsSpace.s3),
                          BxField(
                            label: 'Email',
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: DsSpace.s3),
                          BxField(
                            label: 'Phone',
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: DsSpace.s4),
                          BxButton(
                            label: 'Save changes',
                            fullWidth: true,
                            loading: _savingProfile,
                            onPressed: _savingProfile ? null : _saveProfile,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DsSpace.s4),
                    BxCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title('Appearance'),
                          const ThemeModePicker(),
                          const SizedBox(height: DsSpace.s2),
                          Text(
                            "System follows your device's light or dark setting.",
                            style: TextStyle(
                                fontSize: DsText.xs, color: c.inkSubtle),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DsSpace.s4),
                    BxCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title('Change password'),
                          if (_passwordMsg != null) ...[
                            BxAlert(_passwordMsg!, tone: BxTone.success),
                            const SizedBox(height: DsSpace.s3),
                          ],
                          if (_passwordError != null) ...[
                            BxAlert(_passwordError!, tone: BxTone.danger),
                            const SizedBox(height: DsSpace.s3),
                          ],
                          BxField(
                            label: 'Current password',
                            controller: _currentPassword,
                            obscureText: true,
                          ),
                          const SizedBox(height: DsSpace.s3),
                          BxField(
                            label: 'New password',
                            helper: 'At least 8 characters.',
                            controller: _newPassword,
                            obscureText: true,
                          ),
                          const SizedBox(height: DsSpace.s4),
                          BxButton(
                            label: 'Update password',
                            fullWidth: true,
                            loading: _savingPassword,
                            onPressed: _savingPassword ? null : _savePassword,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DsSpace.s4),
                    BxCard(
                      padding: const EdgeInsets.symmetric(vertical: DsSpace.s3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: DsSpace.s5),
                            child: title('Notification preferences'),
                          ),
                          if (_prefsError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  DsSpace.s5, 0, DsSpace.s5, DsSpace.s3),
                              child: BxAlert(_prefsError!, tone: BxTone.danger),
                            ),
                          for (final entry in _notificationTypes.entries)
                            SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: DsSpace.s5),
                              title: Text(entry.value,
                                  style: TextStyle(
                                      fontSize: DsText.base,
                                      fontWeight: DsWeight.bold,
                                      color: c.ink)),
                              value: _prefs[entry.key] ?? true,
                              onChanged: (v) => _togglePref(entry.key, v),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
