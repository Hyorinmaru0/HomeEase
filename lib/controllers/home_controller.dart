import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/account_data.dart';
import '../services/home_events.dart';

import '../models/appliance.dart';
import '../models/app_settings.dart';
import '../models/homeease_alert.dart';
import '../models/room.dart';
import '../models/schedule.dart';
import '../models/usage_record.dart';
import '../services/demo_data.dart';
import '../services/supported_devices.dart';
import '../services/budget_service.dart';
import '../services/esp32_service.dart';
import '../services/storage_service.dart';

class HomeController extends ChangeNotifier {
  final HomeStorage storage;
  final Esp32Gateway gateway;
  final DateTime Function() now;
  final HomeEvents? events;
  final bool localDemoOnly;
  List<DevicePreference> _userPreferences = [];
  AppSettings settings = AppSettings();
  List<Appliance> appliances = [];
  List<Room> rooms = [];
  List<UsageRecord> history = [];
  List<HomeEaseAlert> alerts = [];
  List<DeviceSchedule> schedules = [];
  bool ready = false;
  bool connected = false;
  bool busy = false;
  String? pendingDeviceId;
  String? error;
  String? storageError;
  DateTime? lastSync;
  String energySource = 'estimated';
  String? pendingHardware;
  bool? espClockSynced;
  bool? espStorageHealthy;
  bool foreground = true;
  bool usageIncomplete = true;
  DateTime? _observation;
  final Set<String> _budgetWarnings = {};
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
    this.events,
    this.localDemoOnly = false,
  }) : now = clock ?? DateTime.now;
  int get activeCount => appliances.where((d) => d.isOn).length;
  int get unreadCount => alerts.where((a) => !a.read).length;
  double get currentWatts =>
      appliances.fold(0, (s, d) => s + (d.isOn ? d.watts : 0));
  bool get canControl =>
      !_disposed && foreground && !busy && (settings.demoMode || connected);
  String get energyLabel => settings.demoMode
      ? 'Simulated estimated energy'
      : 'Estimated energy (configured wattage)';
  String get energyExplanation =>
      'User-defined hypothetical appliance estimates, not electricity measured from the LED models. Fridge and AC models do not refrigerate or cool.';
  bool get allDevicesAvailable =>
      SupportedDevices.names.keys.every((id) => device(id)?.online == true);
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
      if (localDemoOnly) settings.demoMode = true;
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
    _applyWattages();
    alerts = [];
    connected = false;
  }

  Future<void> _loadData() async {
    energySource = 'estimated';
    pendingHardware = null;
    espClockSynced = null;
    espStorageHealthy = null;
    final data = await storage.read(settings.demoMode ? 'demo' : 'live');
    _observation = null;
    _budgetWarnings.clear();
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
    _budgetWarnings.addAll(List<String>.from(data['budgetWarnings'] ?? []));
    usageIncomplete = data['usageIncomplete'] as bool? ?? true;
    if (settings.demoMode) {
      for (final d in DemoData.appliances(now())) {
        if (device(d.id) == null && rooms.any((r) => r.id == d.roomId)) {
          d.isOn = false;
          d.watts = 0;
          d.onSince = null;
          d.totalKwh = 0;
          d.sessionStartKwh = 0;
          appliances.add(d);
        }
      }
    }
    _applyWattages();
    alerts = (data['alerts'] as List? ?? [])
        .where(
          (e) =>
              e['kind'] != 'smartExit' &&
              !RegExp(
                r'fan|relay|door|buzzer',
                caseSensitive: false,
              ).hasMatch('${e['title']} ${e['message']}'),
        )
        .map((e) => HomeEaseAlert.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _scheduleRuns.addAll(Map<String, String>.from(data['scheduleRuns'] ?? {}));
    _conditions.addAll(List<String>.from(data['conditions'] ?? []));
  }

  void _applyState(Map<String, dynamic> json) {
    Map<String, dynamic> migrate(dynamic value, String field) {
      final data = Map<String, dynamic>.from(value);
      data[field] = SupportedDevices.canonical(data[field] as String);
      return data;
    }

    final devices = (json['devices'] as List)
        .map((e) => migrate(e, 'id'))
        .where((e) => SupportedDevices.contains(e['id']))
        .map((e) => Appliance.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final roomData = (json['rooms'] as List)
        .where((e) => ['living', 'bedroom'].contains(e['id']))
        .map((e) => Room.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final usage = (json['history'] as List)
        .map((e) => migrate(e, 'applianceId'))
        .where((e) => SupportedDevices.contains(e['applianceId']))
        .map((e) => UsageRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final rules = (json['schedules'] as List)
        .map((e) => migrate(e, 'applianceId'))
        .where((e) => SupportedDevices.contains(e['applianceId']))
        .map((e) => DeviceSchedule.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final source = json['energySource'] as String? ?? 'estimated';
    const String? pending = null;
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
    if (!settings.demoMode && devices.isNotEmpty) {
      for (final id in SupportedDevices.names.keys) {
        if (!devices.any((d) => d.id == id) &&
            roomData.any((r) => r.id == SupportedDevices.rooms[id])) {
          devices.add(
            Appliance(
              id: id,
              name: SupportedDevices.names[id]!,
              roomId: SupportedDevices.rooms[id]!,
              kind: SupportedDevices.kinds[id]!,
              ratedWatts: SupportedDevices.defaultWatts[id]!,
              online: false,
              hardwareNote:
                  'Not reported by ESP32. Upload the seven-appliance firmware.',
            ),
          );
        }
      }
    }
    energySource = 'estimated';
    pendingHardware = pending;
    espClockSynced = clockSynced;
    espStorageHealthy = storageHealthy;
    rooms = roomData;
    usage.sort((a, b) => b.offTime.compareTo(a.offTime));
    history = usage.take(2000).toList();
    schedules = rules;
    _applyWattages();
  }

  Map<String, dynamic> _snapshot() => {
    'budgetWarnings': _budgetWarnings.toList(),
    'usageIncomplete': usageIncomplete,
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
    if (_disposed) return Future.value();
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
    if (_disposed || busy || settings.demoMode) return;
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
    final response = await gateway.fetchState(settings.esp32Url);
    if (_disposed) return;
    final prior = appliances;
    final localHistory = history;
    _applyState({
      ...response,
      'history': localHistory.map((r) => r.toJson()).toList(),
    });
    _recordObservation(prior);
    _applyPresentation();
    for (final d in appliances) {
      d.totalKwh = history
          .where((r) => r.applianceId == d.id)
          .fold(0, (s, r) => s + r.energyKwh);
      d.sessionStartKwh = d.totalKwh;
    }
    connected = true;
    error = null;
    lastSync = now();
    evaluateAlerts();
    await persist();
  }

  void _connectionFailure(Object e, {bool commandSent = false}) {
    _observation = null;
    usageIncomplete = true;
    connected = false;
    error = esp32FailureMessage(e);
    if (commandSent) {
      error = 'Command sent, but its state could not be confirmed. $error';
    }
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
    var commandSent = false;
    try {
      if (settings.demoMode) {
        _integrateDemo();
        demo();
        evaluateAlerts();
        await persist();
      } else {
        await remote();
        commandSent = true;
        await _fetch();
      }
      return true;
    } catch (e) {
      if (!settings.demoMode && e is Esp32HttpException && e.method == 'PUT') {
        final rejection = esp32FailureMessage(e);
        try {
          await _fetch();
          error = rejection;
        } catch (readError) {
          _connectionFailure(readError);
          error = '$rejection $error';
        }
      } else {
        _connectionFailure(e, commandSent: commandSent);
      }
      return false;
    } finally {
      busy = false;
      pendingDeviceId = null;
      _notify();
    }
  }

  Future<bool> setPower(String id, bool on, {String source = 'manual'}) async {
    if (_disposed) return false;
    final live = !settings.demoMode;
    final d = device(id);
    if (d == null || !d.online || !canControl) {
      if (live && SupportedDevices.contains(id)) {
        events?.commandObserved(id, on, source, false, now());
      }
      return false;
    }
    pendingDeviceId = id;
    final success = await _command(
      () => gateway.setPower(settings.esp32Url, id, on),
      () => _demoPower(d, on),
    );
    final confirmed =
        !_disposed &&
        success &&
        device(id)?.isOn == on &&
        device(id)?.online == true;
    if (success && !confirmed && !_disposed) {
      error =
          'ESP32 did not confirm the requested power state. Refresh and retry.';
      _notify();
    }
    if (live && !_disposed) {
      events?.commandObserved(id, on, source, confirmed, now());
    }
    return confirmed;
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

  Future<bool> setPriority(String id, LoadPriority priority) async {
    if (!SupportedDevices.contains(id) || device(id)?.online != true) {
      return false;
    }
    return _command(
      () => gateway.setPriority(settings.esp32Url, id, priority.name),
      () {
        device(id)?.priority = priority;
      },
    );
  }

  Future<bool> saveSchedule(DeviceSchedule schedule) {
    if (!SupportedDevices.contains(schedule.applianceId) ||
        device(schedule.applianceId)?.online != true) {
      return Future.value(false);
    }
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
    if (_disposed || busy) return;
    if (localDemoOnly) next.demoMode = true;
    busy = true;
    final modeChanged = next.demoMode != settings.demoMode;
    final addressChanged = next.esp32Url != settings.esp32Url;
    try {
      if (settings.demoMode) _integrateDemo();
      await persist();
      _observation = null;
      settings = next;
      _applyWattages();
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
      _applyPresentation();
      evaluateAlerts();
      await persist();
    } finally {
      busy = false;
      _notify();
    }
    if (!settings.demoMode && (modeChanged || addressChanged || !connected)) {
      await refresh();
    }
    if (!_disposed) events?.settingsChanged(settings);
  }

  Iterable<UsageRecord> get activeSessions sync* {
    if (!settings.demoMode) return;
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

  double energyOn(DateTime date) => BudgetService.energyBetween(
    [...history, ...activeSessions],
    DateTime(date.year, date.month, date.day),
    DateTime(date.year, date.month, date.day + 1),
  ).values.fold(0, (a, b) => a + b);
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
    if (_disposed || busy || !ready || !foreground) return;
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
    final summary = budgetSummary;
    final budgetKey =
        '${settings.budgetPeriod}-${summary.start.toIso8601String()}';
    for (final threshold in [80, 100]) {
      if (summary.threshold >= threshold &&
          _budgetWarnings.add('$budgetKey-$threshold')) {
        alerts.insert(
          0,
          HomeEaseAlert(
            id: 'budget-$budgetKey-$threshold',
            title: threshold == 100
                ? 'Estimated budget reached'
                : 'Estimated budget nearing limit',
            message:
                '${settings.demoMode ? "Demo: " : ""}Estimated spending has reached $threshold% of your ${settings.budgetPeriod} budget.',
            kind: AlertKind.highLoad,
            createdAt: now(),
          ),
        );
      }
    }
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

  BudgetSummary get budgetSummary => BudgetService.calculate(
    [...history, ...activeSessions],
    now(),
    settings.budgetPeriod,
    settings.budget,
    settings.electricityRate,
  );

  void _applyWattages() {
    for (final d in appliances) {
      d.ratedWatts = settings.applianceWatts[d.id] ?? d.ratedWatts;
      d.watts = d.isOn ? d.ratedWatts : 0;
    }
  }

  void setForeground(bool active) {
    foreground = active;
    _observation = null;
    _lastTick = now();
    if (!active) {
      usageIncomplete = true;
      connected = false;
    }
  }

  void _recordObservation(List<Appliance> prior) {
    final stamp = now();
    final start = _observation;
    _observation = foreground ? stamp : null;
    if (!foreground || start == null) return;
    final elapsed = stamp.difference(start);
    if (elapsed <= Duration.zero || elapsed > const Duration(seconds: 20)) {
      usageIncomplete = true;
      return;
    }
    for (final d in appliances) {
      final old = prior.where((p) => p.id == d.id).firstOrNull;
      if (old == null ||
          !old.online ||
          !d.online ||
          !old.isOn ||
          !d.isOn ||
          old.onSince != d.onSince) {
        continue;
      }
      final kwh = old.ratedWatts * elapsed.inMilliseconds / 3600000000;
      final index = history.indexWhere(
        (r) =>
            r.applianceId == d.id &&
            r.offTime == start &&
            r.rate == settings.electricityRate &&
            (r.energyKwh / r.runtime.inMilliseconds -
                        old.ratedWatts / 3600000000)
                    .abs() <
                1e-15,
      );
      final previous = index < 0 ? null : history.removeAt(index);
      history.insert(
        0,
        UsageRecord(
          id: previous?.id ?? 'observed-${const Uuid().v4()}',
          applianceId: d.id,
          applianceName: d.name,
          onTime: previous?.onTime ?? start,
          offTime: stamp,
          energyKwh: (previous?.energyKwh ?? 0) + kwh,
          rate: settings.electricityRate,
        ),
      );
      events?.observedEnergy(history.first);
    }
    if (history.length > 2000) {
      history = history.take(2000).toList();
      usageIncomplete = true;
    }
  }

  Future<bool> freshSupportedState() async {
    if (busy || !foreground) return false;
    if (!settings.demoMode) await refresh();
    return (settings.demoMode ||
            (connected &&
                lastSync != null &&
                now().difference(lastSync!) < const Duration(seconds: 15))) &&
        allDevicesAvailable;
  }

  Future<bool> turnOffSupported({
    bool lightsOnly = false,
    bool includeFridge = false,
    String source = 'manual',
  }) async {
    if (!await freshSupportedState()) return false;
    var success = true;
    for (final id in SupportedDevices.names.keys) {
      if (lightsOnly && !SupportedDevices.lightIds.contains(id)) continue;
      if (!includeFridge && id == 'mini-fridge') continue;
      if (!await setPower(id, false, source: source)) success = false;
    }
    final verified = await freshSupportedState();
    return success &&
        verified &&
        appliances
            .where(
              (d) =>
                  (!lightsOnly || SupportedDevices.lightIds.contains(d.id)) &&
                  (includeFridge || d.id != 'mini-fridge'),
            )
            .every((d) => !d.isOn);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void applyUserPresentation(String name, List<DevicePreference> preferences) {
    if (_disposed) return;
    settings.name = name;
    _userPreferences = List.of(preferences);
    _applyPresentation();
    _notify();
  }

  void _applyPresentation() {
    for (final d in appliances) {
      final pref = _userPreferences
          .where((p) => p.deviceId == d.id)
          .firstOrNull;
      if (pref != null) d.name = pref.displayName;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    foreground = false;
    _timer?.cancel();
    gateway.close();
    super.dispose();
  }
}
