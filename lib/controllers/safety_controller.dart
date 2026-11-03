import 'package:flutter/foundation.dart';

import 'home_controller.dart';
import '../services/alarm_service.dart';
import '../services/supported_devices.dart';

class SafetyController extends ChangeNotifier {
  final HomeController home;
  final AlarmOutput alarm;
  bool checking = false, warning = false, dismissed = false, sounding = false;
  bool _disposed = false;
  int _generation = 0;
  List<String> activeNames = [];
  String message =
      'Run a manual check of all seven appliances. The fridge stays on during safety shutdown.';
  bool _checked = false;
  SafetyController(this.home, this.alarm) {
    home.addListener(_homeChanged);
  }
  String get _clearMessage => home.device('mini-fridge')?.isOn == true
      ? 'All safety-target appliances are OFF. Fridge remains ON.'
      : 'All monitored appliances are OFF.';
  void _homeChanged() {
    if (!_checked || checking || _disposed) return;
    if (!home.foreground) return;
    if (!home.settings.demoMode &&
        (!home.connected ||
            home.lastSync == null ||
            home.now().difference(home.lastSync!) >=
                const Duration(seconds: 15))) {
      message = 'Status unknown — reconnect and recheck.';
      activeNames = [];
      _stop();
    } else if (home.allDevicesAvailable) {
      activeNames = home.appliances
          .where((d) => d.isOn && SupportedDevices.safetyTarget(d.id))
          .map((d) => d.name)
          .toList();
      if (activeNames.isEmpty) {
        message = _clearMessage;
        warning = false;
        dismissed = false;
        _stop();
      } else {
        message =
            'Appliances still ON: ${activeNames.join(', ')}. Recheck to run a new safety check.';
      }
    } else {
      message = 'Status unknown — a monitored appliance is unavailable.';
      activeNames = [];
      _stop();
    }
    if (!home.settings.alarmEnabled) _stop();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check({bool turnOff = false}) async {
    if (checking || !home.foreground) return;
    final generation = _generation;
    checking = true;
    _checked = true;
    _notify();
    try {
      final ok = turnOff
          ? await home.turnOffSupported()
          : await home.freshSupportedState();
      if (_disposed || generation != _generation) return;
      if (!ok) {
        message = turnOff
            ? 'Could not verify Turn Off All. Reconnect and recheck.'
            : 'Status unknown — ESP32 offline, busy, or an appliance unavailable. Recheck.';
        activeNames = [];
        await _stop();
      } else {
        activeNames = home.appliances
            .where((d) => d.isOn && SupportedDevices.safetyTarget(d.id))
            .map((d) => d.name)
            .toList();
        if (activeNames.isEmpty) {
          message = _clearMessage;
          warning = false;
          dismissed = false;
          await _stop();
        } else {
          message = 'Appliances still ON: ${activeNames.join(', ')}';
          final firstWarning = !warning;
          warning = true;
          if (firstWarning && !dismissed && home.settings.alarmEnabled) {
            sounding = true;
            try {
              await alarm.start(vibrate: home.settings.vibrationEnabled);
            } catch (_) {
              sounding = false;
              message +=
                  '\nAlarm audio unavailable. Check phone audio settings.';
            }
          }
        }
      }
    } finally {
      checking = false;
      _notify();
    }
  }

  Future<void> _stop() async {
    sounding = false;
    try {
      await alarm.stop();
    } catch (_) {}
  }

  Future<void> dismiss() async {
    dismissed = true;
    await _stop();
    _notify();
  }

  Future<void> suspend() async {
    _generation++;
    message =
        'Check paused. Recheck current device states when the app is active.';
    activeNames = [];
    await dismiss();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    home.removeListener(_homeChanged);
    alarm.dispose();
    super.dispose();
  }
}
