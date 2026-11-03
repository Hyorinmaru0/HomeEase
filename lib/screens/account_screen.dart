import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../controllers/account_data_controller.dart';
import '../models/account_data.dart';
import '../services/auth_service.dart';
import '../services/supported_devices.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'auth_screen.dart';

class AccountScreen extends StatefulWidget {
  final AuthController auth;
  final AccountDataController account;
  const AccountScreen({super.key, required this.auth, required this.account});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final TextEditingController _name;
  final _current = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  final _passwordForm = GlobalKey<FormState>();
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.account.profile.fullName);
  }

  @override
  void dispose() {
    for (final c in [_name, _current, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _action(Future<void> Function() callback, String message) async {
    setState(() => _busy = true);
    try {
      await callback();
      if (mounted) showMessage(context, message);
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          e is Exception ? friendlyAuthError(e) : 'Could not save. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPreference(String id) async {
    final p = widget.account.preferences
        .where((p) => p.deviceId == id)
        .firstOrNull;
    final name = TextEditingController(
      text: p?.displayName ?? SupportedDevices.names[id],
    );
    final room = TextEditingController(
      text:
          p?.room ??
          (SupportedDevices.rooms[id] == 'bedroom' ? 'Bedroom' : 'Living room'),
    );
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Appliance preferences'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter a name.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: room,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Preferred room label',
                  ),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Enter a room label.'
                      : null,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Personal labels only. This does not move a sensor or change physical appliance state.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              try {
                await widget.account.savePreference(
                  DevicePreference(
                    deviceId: id,
                    displayName: name.text.trim(),
                    room: room.text.trim(),
                    preferences: p?.preferences ?? {},
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                if (ctx.mounted) {
                  showMessage(
                    ctx,
                    'Could not save preferences. Please try again.',
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    room.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.account,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PageHeading(
                    eyebrow: 'YOUR ACCOUNT',
                    title: 'Profile & preferences',
                    subtitle: 'Your preferences and observed activity.',
                  ),
                  Text(
                    widget.auth.session?.email ?? '',
                    style: const TextStyle(color: AppColors.mint),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_name.text.trim().isEmpty) {
                              showMessage(context, 'Enter your full name.');
                              return;
                            }
                            _action(
                              () => widget.account.saveName(_name.text),
                              'Profile saved on this phone.',
                            );
                          },
                    child: const Text('Save profile'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Local account ? Saved on this phone',
                    style: TextStyle(color: AppColors.mint),
                  ),
                  if (widget.account.error != null)
                    Text(
                      widget.account.error!,
                      style: const TextStyle(color: AppColors.amber),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Accounts, settings and history stay on this phone. The ESP32 uses your configured local Wi-Fi connection.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SectionHeading('Appliance preferences'),
                  ...SupportedDevices.names.entries.map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        widget.account.preferences
                                .where((p) => p.deviceId == d.key)
                                .firstOrNull
                                ?.displayName ??
                            d.value,
                      ),
                      subtitle: Text(
                        widget.account.preferences
                                .where((p) => p.deviceId == d.key)
                                .firstOrNull
                                ?.room ??
                            d.key,
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editPreference(d.key),
                    ),
                  ),
                  const SectionHeading('Change password'),
                  Form(
                    key: _passwordForm,
                    child: Column(
                      children: [
                        PasswordField(
                          controller: _current,
                          label: 'Current password',
                          validator: (v) => (v?.isEmpty ?? true)
                              ? 'Enter your current password.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _password,
                          label: 'New password',
                          newPassword: true,
                          validator: validatePassword,
                        ),
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _confirm,
                          label: 'Confirm new password',
                          newPassword: true,
                          validator: (v) => v == _password.text
                              ? null
                              : 'Passwords do not match.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  if (!_passwordForm.currentState!.validate()) {
                                    return;
                                  }
                                  _action(() async {
                                    await widget.auth.repository!
                                        .changePassword(
                                          _current.text,
                                          _password.text,
                                        );
                                    _current.clear();
                                    _password.clear();
                                    _confirm.clear();
                                  }, 'Password changed.');
                                },
                          child: const Text('Change password'),
                        ),
                      ],
                    ),
                  ),
                  SectionHeading(
                    'Device activity',
                    action: 'Latest ${widget.account.activity.length}',
                  ),
                  if (widget.account.activity.isEmpty)
                    const Text(
                      'No live commands recorded for this account. Demo activity is kept separate.',
                    ),
                  ...widget.account.activity.map(
                    (a) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        a.success
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: a.success ? AppColors.mint : AppColors.amber,
                      ),
                      title: Text(
                        '${SupportedDevices.names[a.deviceId] ?? a.deviceId} · ${a.action == 'power_on' ? 'ON' : 'OFF'}',
                      ),
                      subtitle: Text(
                        '${dateLabel(a.eventTime)} · ${TimeOfDay.fromDateTime(a.eventTime).format(context)} · ${a.source}\n${a.success ? 'Observed and confirmed' : 'Failed or not confirmed'}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Log out?'),
                                content: const Text(
                                  'Your account, settings and history will stay saved on this phone. Voice and alarm sessions will stop.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Log out'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) await widget.auth.logout();
                          },
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
