import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../models/app_settings.dart';
import '../services/esp32_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  final HomeController controller;
  const SettingsScreen({super.key, required this.controller});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _rate, _load, _runtime, _url;
  late bool _demo, _alerts;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _rate = TextEditingController(text: s.electricityRate.toString());
    _load = TextEditingController(text: s.highLoadWatts.toString());
    _runtime = TextEditingController(text: s.longRuntimeHours.toString());
    _url = TextEditingController(text: s.esp32Url);
    _demo = s.demoMode;
    _alerts = s.alertsEnabled;
  }

  @override
  void dispose() {
    for (final c in [_rate, _load, _runtime, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _number(String? input, {bool allowZero = false}) {
    final value = double.tryParse(input ?? '');
    return value == null ||
            !value.isFinite ||
            (allowZero ? value < 0 : value <= 0)
        ? 'Enter a valid ${allowZero ? 'non-negative' : 'positive'} number.'
        : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.controller.updateSettings(
        AppSettings(
          name: widget.controller.settings.name,
          electricityRate: double.parse(_rate.text),
          highLoadWatts: double.parse(_load.text),
          longRuntimeHours: double.parse(_runtime.text),
          alertsEnabled: _alerts,
          demoMode: _demo,
          esp32Url: _url.text.trim(),
        ),
      );
      if (mounted) {
        showMessage(
          context,
          widget.controller.storageError ??
              widget.controller.error ??
              'Your preferences are saved.',
        );
      }
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Could not apply settings. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            eyebrow: 'Preferences',
            title: 'Settings',
            subtitle: 'Connection, energy rates, and alerts.',
          ),
          const SectionHeading('ESP32 connection'),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Demo mode',
                    style: TextStyle(fontSize: 15),
                  ),
                  subtitle: const Text(
                    'Explore with simulated devices',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  value: _demo,
                  onChanged: (v) => setState(() => _demo = v),
                ),
                const SizedBox(height: 12),
                Text(
                  _demo
                      ? 'Your demo home is ready to explore. Turn this off when your ESP32 firmware is ready.'
                      : 'Connect your phone and ESP32 to the same Wi-Fi network, then enter its local address.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'ESP32 address',
                    hintText: 'http://192.168.1.100',
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                  validator: (v) => Esp32Service.validAddress(v ?? '')
                      ? null
                      : 'Use a valid http:// or https:// address.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    StatusPill(
                      c.connectionLabel,
                      color: c.settings.demoMode || c.connected
                          ? AppColors.mint
                          : AppColors.amber,
                    ),
                    if (!c.settings.demoMode)
                      TextButton.icon(
                        onPressed: c.busy ? null : c.refresh,
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('Reconnect'),
                      ),
                  ],
                ),
                if (c.lastSync != null && !c.settings.demoMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Last update: ${clockLabel(c.lastSync!)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (!c.settings.demoMode && c.pendingHardware != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Pending hardware: ${c.pendingHardware}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
                if (!c.settings.demoMode && c.espClockSynced == false)
                  const Text(
                    'ESP32 clock pending: routines wait for time sync.',
                    style: TextStyle(fontSize: 12, color: AppColors.amber),
                  ),
                if (!c.settings.demoMode && c.espStorageHealthy == false)
                  const Text(
                    'ESP32 storage unavailable: changes may not survive a restart.',
                    style: TextStyle(fontSize: 12, color: AppColors.amber),
                  ),
              ],
            ),
          ),
          const SectionHeading('Energy & thresholds'),
          Surface(
            child: Column(
              children: [
                TextFormField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Electricity rate',
                    prefixText: '₱ ',
                    suffixText: '/ kWh',
                  ),
                  validator: (v) => _number(v, allowZero: true),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _load,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'High-load alert threshold',
                    suffixText: 'W',
                  ),
                  validator: _number,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _runtime,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Long-runtime alert after',
                    suffixText: 'hours',
                  ),
                  validator: _number,
                ),
              ],
            ),
          ),
          const SectionHeading('Alerts'),
          Surface(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'In-app alerts',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Smart Exit, high load, and unusual runtime. Alerts are checked while the app is open.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              value: _alerts,
              onChanged: (v) => setState(() => _alerts = v),
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving || c.busy ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving…' : 'Save preferences'),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'HOMEEASE  /  TEAM ROCKET\nVersion 1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                height: 1.8,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
