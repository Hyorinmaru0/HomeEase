import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/account_data.dart';
import '../models/usage_record.dart';
import '../services/home_events.dart';
import '../services/storage_service.dart';
import '../services/supported_devices.dart';
import 'home_controller.dart';

class AccountDataController extends ChangeNotifier implements HomeEvents {
  final HomeStorage storage;
  UserProfile profile;
  List<DevicePreference> preferences = [];
  List<DeviceActivity> activity = [];
  HomeController? _home;
  bool _disposed = false;
  String? error;
  AccountDataController({
    required this.storage,
    required String userId,
    required String initialName,
  }) : profile = UserProfile(userId, initialName);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize(HomeController home) async {
    _home = home;
    final cached = await storage.read('account');
    if (_disposed) return;
    if (cached != null) {
      final savedProfile = UserProfile.fromJson(
        Map<String, dynamic>.from(cached['profile']),
      );
      if (savedProfile.userId != profile.userId) {
        throw const FormatException('Account storage mismatch');
      }
      profile = savedProfile;
      preferences = (cached['preferences'] as List)
          .map((j) => DevicePreference.fromJson(Map<String, dynamic>.from(j)))
          .where((p) => SupportedDevices.contains(p.deviceId))
          .toList();
      activity = (cached['activity'] as List)
          .map((j) => DeviceActivity.fromJson(Map<String, dynamic>.from(j)))
          .where((a) => SupportedDevices.contains(a.deviceId))
          .take(200)
          .toList();
    }
    home.applyUserPresentation(profile.fullName, preferences);
    _notify();
  }

  Future<void> _save() async {
    if (_disposed) return;
    try {
      await storage.write('account', {
        'profile': profile.toJson(),
        'preferences': preferences.map((p) => p.toJson()).toList(),
        'activity': activity.map((a) => a.toJson()).toList(),
      });
      error = null;
    } catch (_) {
      error = 'Changes could not be saved on this phone. Please try again.';
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<void> saveName(String name) async {
    if (_disposed) return;
    profile = UserProfile(profile.userId, name.trim());
    _home?.applyUserPresentation(profile.fullName, preferences);
    await _save();
  }

  Future<void> savePreference(DevicePreference value) async {
    if (_disposed || !SupportedDevices.contains(value.deviceId)) return;
    preferences = [
      ...preferences.where((p) => p.deviceId != value.deviceId),
      value,
    ];
    _home?.applyUserPresentation(profile.fullName, preferences);
    await _save();
  }

  @override
  void commandObserved(
    String deviceId,
    bool on,
    String source,
    bool success,
    DateTime at,
  ) {
    if (_disposed || !SupportedDevices.contains(deviceId)) return;
    activity = [
      DeviceActivity(
        id: const Uuid().v4(),
        deviceId: deviceId,
        action: on ? 'power_on' : 'power_off',
        source: source,
        eventTime: at,
        success: success,
      ),
      ...activity,
    ].take(200).toList();
    unawaited(_save().catchError((Object _) {}));
  }

  @override
  void settingsChanged(AppSettings settings) {}
  @override
  void observedEnergy(UsageRecord record) {}
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
