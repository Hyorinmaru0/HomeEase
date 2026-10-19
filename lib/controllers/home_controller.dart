import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/appliance.dart';
import '../models/app_settings.dart';
import '../models/homeease_alert.dart';
import '../models/room.dart';
import '../models/schedule.dart';
import '../models/usage_record.dart';
import '../services/demo_data.dart';
import '../services/esp32_service.dart';
import '../services/storage_service.dart';

class HomeController extends ChangeNotifier {
  final HomeStorage storage;
  final Esp32Gateway gateway;
  final DateTime Function() now;
  AppSettings settings = AppSettings();
  List<Appliance> appliances = [];
  List<Room> rooms = [];
  List<UsageRecord> history = [];
  List<HomeEaseAlert> alerts = [];
  List<DeviceSchedule> schedules = [];
  bool ready = false;
  bool connected = false;
  bool busy = false;
  String? error;
  String? storageError;
  DateTime? lastSync;
  String energySource = 'estimated';
  String? pendingHardware;
  bool? espClockSynced;
  bool? espStorageHealthy;
  Timer? _timer;
  DateTime? _lastTick;
  final Set<String> _conditions = {};
  final Map<String, String> _scheduleRuns = {};
  Future<void> _saveQueue = Future.value();
  bool _disposed = false;

  HomeController({
    required this.storage,
    required this.gateway,
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;
  int get activeCount => appliances.where((d) => d.isOn).length;
  int get unreadCount => alerts.where((a) => !a.read).length;
  double get currentWatts =>
      appliances.fold(0, (s, d) => s + (d.isOn ? d.watts : 0));
  bool get canControl => !busy && (settings.demoMode || connected);
  String get energyLabel => settings.demoMode
      ? 'Simulated energy'
      : energySource == 'measured'
      ? 'Measured energy'
      : 'Estimated energy (rated power)';
  String roomStatus(Room room) => !settings.demoMode && !connected
      ? 'Last known'
      : !room.sensorOnline
      ? 'Sensor unavailable'
      : room.occupied
      ? 'Occupied'
      : 'Vacant';
  String sensorReading(Room room) {
    if (settings.demoMode) return 'Demo • Simulated occupancy';
    final source = connected ? 'ESP32' : 'Last known ESP32';
    if (!room.sensorOnline) {
      return '$source • ${room.sensor ?? 'Sensor'} unavailable';
    }
    if (room.sensor == 'HC-SR04') {
      return '$source • HC-SR04: ${room.distanceCm?.toStringAsFixed(1) ?? '—'} cm';
    }
    if (room.sensor == 'PIR') {
      return '$source • PIR: ${room.motion == true ? 'Motion detected' : 'No motion'}';
    }
    return '$source • Occupancy';
  }

  String get connectionLabel => settings.demoMode
      ? 'Demo home'
      : connected
      ? 'ESP32 connected'
      : 'ESP32 offline';
  String roomName(String id) =>
      rooms.where((r) => r.id == id).firstOrNull?.name ?? id;
  Appliance? device(String id) =>
      appliances.where((d) => d.id == id).firstOrNull;

  Future<void> initialize({bool startTimer = true}) async {
    try {
      final saved = await storage.read('settings');
      if (saved != null) settings = AppSettings.fromJson(saved);
      await _loadData();
    } catch (_) {
      storageError =
          'Saved data could not be read. This session is using demo data.';
      settings = AppSettings();
      _seedDemo();
    }
    ready = true;
    _lastTick = now();
    evaluateAlerts();
    if (!settings.demoMode) await refresh();
    if (startTimer) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => tick());
    }
    _notify();
  }

  void _seedDemo() {
    energySource = 'estimated';
    appliances = DemoData.appliances(now());
    rooms = DemoData.rooms();
    history = DemoData.history(now());
    schedules = DemoData.schedules();
    alerts = [];
    connected = false;
  }

  Future<void> _loadData() async {
    energySource = 'estimated';
    pendingHardware = null;
    espClockSynced = null;
    espStorageHealthy = null;
    final data = await storage.read(settings.demoMode ? 'demo' : 'live');
    _conditions.clear();
    _scheduleRuns.clear();
    if (data == null) {
      if (settings.demoMode) {
        _seedDemo();
      } else {
        appliances = [];
        rooms = [];
        history = [];
        alerts = [];
        schedules = [];
      }
      return;
    }
    _applyState(data);
    // Upgrade existing demo homes without resetting any saved modules or data.
    if (settings.demoMode &&
        !appliances.any((d) => d.id == 'mini-tv') &&
        rooms.any((r) => r.id == 'living')) {
      appliances.add(DemoData.miniTv());
    }
    alerts = (data['alerts'] as List? ?? [])
        .map((e) => HomeEaseAlert.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _scheduleRuns.addAll(Map<String, String>.from(data['scheduleRuns'] ?? {}));
    _conditions.addAll(List<String>.from(data['conditions'] ?? []));
  }

  void _applyState(Map<String, dynamic> json) {
    // Parse the entire response before changing any visible state.
    final devices = (json['devices'] as List)
        .map((e) => Appliance.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final roomData = (json['rooms'] as List)
        .map((e) => Room.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final usage = (json['history'] as List)
        .map((e) => UsageRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final rules = (json['schedules'] as List)
        .map((e) => DeviceSchedule.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final source = json['energySource'] as String? ?? 'estimated';
    final pending = json['pendingHardware'] as String?;
    final clockSynced = json['clockSynced'] as bool?;
    final storageHealthy = json['storageHealthy'] as bool?;
    if (!['estimated', 'measured'].contains(source) ||
        roomData.any(
          (r) =>
              (r.distanceCm != null &&
                  (!r.distanceCm!.isFinite || r.distanceCm! < 0)) ||
              (r.sensorOnline &&
                  r.sensor == 'HC-SR04' &&
                  r.distanceCm == null) ||
              (r.sensorOnline && r.sensor == 'PIR' && r.motion == null),
        ) ||
        devices.map((d) => d.id).toSet().length != devices.length ||
        roomData.map((r) => r.id).toSet().length != roomData.length ||
        usage.map((r) => r.id).toSet().length != usage.length ||
        rules.map((r) => r.id).toSet().length != rules.length ||
        usage.any(
          (r) =>
              !r.energyKwh.isFinite ||
              r.energyKwh < 0 ||
              !r.rate.isFinite ||
              r.rate < 0 ||
              r.offTime.isBefore(r.onTime),
        ) ||
        rules.any((s) => !devices.any((d) => d.id == s.applianceId)) ||
        devices.any(
          (d) =>
              !d.watts.isFinite ||
              d.watts < 0 ||
              !d.totalKwh.isFinite ||
              d.totalKwh < 0 ||
              !d.ratedWatts.isFinite ||
              d.ratedWatts < 0 ||
              !d.sessionStartKwh.isFinite ||
              d.sessionStartKwh < 0 ||
              d.sessionStartKwh > d.totalKwh ||
              !roomData.any((r) => r.id == d.roomId),
        )) {
      throw const FormatException('Invalid ESP32 device data');
    }
    appliances = devices;
    energySource = source;
    pendingHardware = pending;
    espClockSynced = clockSynced;
    espStorageHealthy = storageHealthy;
    rooms = roomData;
    usage.sort((a, b) => b.offTime.compareTo(a.offTime));
    history = usage.take(2000).toList();
    schedules = rules;
  }

  Map<String, dynamic> _snapshot() => {
    'energySource': energySource,
    'pendingHardware': pendingHardware,
    'clockSynced': espClockSynced,
    'storageHealthy': espStorageHealthy,
    'devices': appliances.map((d) => d.toJson()).toList(),
    'rooms': rooms.map((r) => r.toJson()).toList(),
    'history': history.take(2000).map((r) => r.toJson()).toList(),
    'alerts': alerts.take(200).map((a) => a.toJson()).toList(),
    'schedules': schedules.map((s) => s.toJson()).toList(),
    'scheduleRuns': Map.of(_scheduleRuns),
    'conditions': _conditions.toList(),
  };

  Future<void> persist() {
    final key = settings.demoMode ? 'demo' : 'live';
    final data = _snapshot();
    final prefs = settings.toJson();
    _saveQueue = _saveQueue.then((_) async {
      try {
        await storage.write(key, data);
        await storage.write('settings', prefs);
        storageError = null;
      } catch (_) {
        storageError =
            'Changes are in memory, but could not be saved on this device.';
        _notify();
      }
    });
    return _saveQueue;
  }

  Future<void> refresh() async {
    if (busy || settings.demoMode) return;
    busy = true;
    _notify();
    try {
      await _fetch();
    } catch (e) {
      _connectionFailure(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _fetch() async {
    _applyState(await gateway.fetchState(settings.esp32Url));
    connected = true;
    error = null;
    lastSync = now();
    evaluateAlerts();
    await persist();
  }

  void _connectionFailure(Object e) {
    connected = false;
    error = e is LocalNetworkPermissionException
        ? 'Allow local-network access in Android app settings, then reconnect.'
        : 'Could not confirm ESP32 state. Check the address and Wi-Fi, then reconnect.';
    _addAlert(
      'connection',
      AlertKind.connection,
      'Connection interrupted',
      'Device status is from the last successful update.',
    );
  }

  Future<bool> _command(
    Future<void> Function() remote,
    void Function() demo,
  ) async {
    if (!canControl) return false;
    busy = true;
    error = null;
    _notify();
    try {
      if (settings.demoMode) {
        _integrateDemo();
        demo();
        evaluateAlerts();
        await persist();
      } else {
        await remote();
        await _fetch();
      }
      return true;
    } catch (e) {
      _connectionFailure(e);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> setPower(String id, bool on) async {
    final d = device(id);
    if (d == null || !d.online) return false;
    return _command(
      () => gateway.setPower(settings.esp32Url, id, on),
      () => _demoPower(d, on),
    );
  }

  void _demoPower(Appliance d, bool on) {
    if (d.isOn == on) return;
    if (on) {
      d.onSince = now();
      d.sessionStartKwh = d.totalKwh;
    } else if (d.onSince != null) {
      history.insert(
        0,
        UsageRecord(
          id: '${now().microsecondsSinceEpoch}-${d.id}',
          applianceId: d.id,
          applianceName: d.name,
          onTime: d.onSince!,
          offTime: now(),
          energyKwh: math.max(0, d.totalKwh - d.sessionStartKwh),
          rate: settings.electricityRate,
        ),
      );
      d.onSince = null;
      if (history.length > 2000) history.removeRange(2000, history.length);
    }
    d.isOn = on;
    d.watts = on ? d.ratedWatts : 0;
  }

  Future<bool> setPriority(String id, LoadPriority priority) => _command(
    () => gateway.setPriority(settings.esp32Url, id, priority.name),
    () {
      device(id)?.priority = priority;
    },
  );

  Future<bool> saveSchedule(DeviceSchedule schedule) {
    final next = [...schedules.where((s) => s.id != schedule.id), schedule];
    return _replaceSchedules(next);
  }

  Future<bool> deleteSchedule(String id) =>
      _replaceSchedules(schedules.where((s) => s.id != id).toList());
  Future<bool> _replaceSchedules(List<DeviceSchedule> next) =>
      _command(() => gateway.saveSchedules(settings.esp32Url, next), () {
        schedules = next;
        _scheduleRuns.removeWhere((id, _) => !next.any((s) => s.id == id));
      });

  Future<void> setOccupancy(String id, bool value) async {
    if (!settings.demoMode) return;
    rooms.firstWhere((r) => r.id == id).occupied = value;
    evaluateAlerts();
    _notify();
    await persist();
  }

  Future<void> updateSettings(AppSettings next) async {
    if (busy) return;
    busy = true;
    final modeChanged = next.demoMode != settings.demoMode;
    final addressChanged = next.esp32Url != settings.esp32Url;
    try {
      await persist();
      settings = next;
      if (modeChanged) {
        connected = false;
        error = null;
        lastSync = null;
        try {
          await _loadData();
        } catch (_) {
          if (settings.demoMode) {
            _seedDemo();
          } else {
            appliances = [];
            rooms = [];
            history = [];
            alerts = [];
            schedules = [];
          }
          storageError = 'Cached data could not be restored.';
        }
        _lastTick = now();
      }
      if (addressChanged) connected = false;
      evaluateAlerts();
      await persist();
    } finally {
      busy = false;
      _notify();
    }
    if (!settings.demoMode && (modeChanged || addressChanged || !connected)) {
      await refresh();
    }
  }

  Iterable<UsageRecord> get activeSessions sync* {
    for (final d in appliances.where((d) => d.isOn && d.onSince != null)) {
      yield UsageRecord(
        id: 'active-${d.id}',
        applianceId: d.id,
        applianceName: d.name,
        onTime: d.onSince!,
        offTime: now(),
        energyKwh: math.max(0, d.totalKwh - d.sessionStartKwh),
        rate: settings.electricityRate,
      );
    }
  }

  double energyOn(DateTime date) =>
      [...history, ...activeSessions].fold(0, (s, r) => s + r.energyOn(date));
  double get todayKwh => energyOn(now());
  double energyForDays(int days) => List.generate(
    days,
    (i) => energyOn(
      DateTime(now().year, now().month, now().day).subtract(Duration(days: i)),
    ),
  ).fold(0, (a, b) => a + b);

  void _integrateDemo() {
    final stamp = now();
    final seconds = math.max(
      0,
      stamp.difference(_lastTick ?? stamp).inMilliseconds / 1000,
    );
    for (final d in appliances.where((d) => d.isOn)) {
      d.totalKwh += d.watts * seconds / 3600000;
    }
    _lastTick = stamp;
  }

  Future<void> tick() async {
    if (busy || !ready) return;
    if (!settings.demoMode) {
      await refresh();
      return;
    }
    _integrateDemo();
    final stamp = now();
    for (final s in schedules.where((s) => s.enabled)) {
      final key = '${stamp.year}-${stamp.month}-${stamp.day}-${s.minuteOfDay}';
      if (s.days.contains(stamp.weekday) &&
          s.minuteOfDay == stamp.hour * 60 + stamp.minute &&
          _scheduleRuns[s.id] != key) {
        final d = device(s.applianceId);
        if (d != null && d.online) {
          _demoPower(d, s.turnOn);
          _scheduleRuns[s.id] = key;
        }
      }
    }
    evaluateAlerts();
    _notify();
    await persist();
  }

  void evaluateAlerts() {
    if (!settings.alertsEnabled || (!settings.demoMode && !connected)) return;
    final active = <String>{};
    void check(String key, AlertKind kind, String title, String message) {
      active.add(key);
      _addAlert(key, kind, title, message);
    }

    if (currentWatts > settings.highLoadWatts) {
      check(
        'load',
        AlertKind.highLoad,
        'Your home is using more power',
        '${currentWatts.toStringAsFixed(0)} W exceeds your ${settings.highLoadWatts.toStringAsFixed(0)} W limit. Review low-priority devices.',
      );
    }
    for (final r in rooms.where((r) => r.sensorOnline && !r.occupied)) {
      final devices = appliances.where((d) => d.roomId == r.id && d.isOn);
      if (devices.isNotEmpty) {
        check(
          'exit-${r.id}',
          AlertKind.smartExit,
          'A little energy you can save',
          '${r.name} is vacant with ${devices.length} device${devices.length == 1 ? '' : 's'} still on.',
        );
      }
    }
    for (final d in appliances.where((d) => d.isOn && d.onSince != null)) {
      if (now().difference(d.onSince!).inMinutes >=
          settings.longRuntimeHours * 60) {
        check(
          'runtime-${d.id}',
          AlertKind.abnormalUsage,
          '${d.name} has been on a while',
          'Runtime has passed your ${settings.longRuntimeHours.toStringAsFixed(1)} hour threshold.',
        );
      }
    }
    _conditions.removeWhere((key) => !active.contains(key));
  }

  void _addAlert(String key, AlertKind kind, String title, String message) {
    if (!settings.alertsEnabled || !_conditions.add(key)) return;
    alerts.insert(
      0,
      HomeEaseAlert(
        id: '$key-${now().microsecondsSinceEpoch}',
        title: title,
        message: message,
        kind: kind,
        createdAt: now(),
      ),
    );
    if (alerts.length > 200) alerts.removeLast();
  }

  Future<void> markAlertsRead() async {
    for (final a in alerts) {
      a.read = true;
    }
    _notify();
    await persist();
  }

  Future<void> markAlertRead(String id) async {
    alerts.firstWhere((a) => a.id == id).read = true;
    _notify();
    await persist();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    gateway.close();
    super.dispose();
  }
}
