import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/controllers/home_controller.dart';
import 'package:homeease/controllers/safety_controller.dart';
import 'package:homeease/models/app_settings.dart';
import 'package:homeease/models/account_data.dart';
import 'package:homeease/models/schedule.dart';
import 'package:homeease/models/usage_record.dart';
import 'package:homeease/services/budget_service.dart';
import 'package:homeease/services/supported_devices.dart';
import 'package:homeease/services/voice_service.dart';

import 'fakes.dart';
import 'smart_features_test.dart' show FakeAlarm;

class UnconfirmedGateway extends FakeGateway {
  @override
  Future<void> setPower(String baseUrl, String id, bool on) async {
    powerCalls++;
  }
}

class DelayedGateway extends FakeGateway {
  final sent = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> setPower(String baseUrl, String id, bool on) async {
    sent.complete();
    await release.future;
    await super.setPower(baseUrl, id, on);
  }
}

void main() {
  late HomeController home;
  late FakeGateway gateway;
  late MemoryStorage storage;
  late DateTime time;
  setUp(() async {
    time = DateTime(2026, 10, 31, 12);
    storage = MemoryStorage();
    gateway = FakeGateway();
    home = HomeController(
      storage: storage,
      gateway: gateway,
      clock: () => time,
    );
    await home.initialize(startTimer: false);
  });
  tearDown(() => home.dispose());
  Future<void> live() async {
    gateway.state = {
      'devices': home.appliances.map((d) => d.toJson()).toList(),
      'rooms': home.rooms.map((r) => r.toJson()).toList(),
      'history': [],
      'schedules': [],
    };
    await home.updateSettings(AppSettings(demoMode: false));
  }

  test(
    'exact seven-device inventory has four living and three bedroom devices',
    () {
      expect(home.appliances.map((d) => d.id).toSet(), {
        'living-light',
        'bedroom-light',
        'mini-tv',
        'mini-fridge',
        'living-ac',
        'bedroom-wall-lamp',
        'bedroom-ac',
      });
      expect(home.appliances.where((d) => d.roomId == 'living'), hasLength(4));
      expect(home.appliances.where((d) => d.roomId == 'bedroom'), hasLength(3));
      expect(home.device('bedroom-wall-lamp')!.name, 'Smart Wall Lamp');
      expect(
        SupportedDevices.modelNote('mini-fridge'),
        contains('no door sensing'),
      );
    },
  );

  for (final id in SupportedDevices.names.keys) {
    test(
      '$id confirms ON/OFF through the existing live command path',
      () async {
        await live();
        expect(await home.setPower(id, true), isTrue);
        expect(home.device(id)!.isOn, isTrue);
        expect(await home.setPower(id, false), isTrue);
        expect(home.device(id)!.isOn, isFalse);
        expect(gateway.powerCalls, 2);
        gateway.fail = true;
        expect(await home.setPower(id, true), isFalse);
        expect(home.device(id)!.isOn, isFalse);
        expect(home.connected, isFalse);
      },
    );
  }

  test('two ACs are independent and survive a demo restart', () async {
    await home.setPower('living-ac', true);
    expect(home.device('bedroom-ac')!.isOn, isFalse);
    await home.setPower('bedroom-ac', true);
    await home.setPower('living-ac', false);
    final restored = HomeController(
      storage: storage,
      gateway: FakeGateway(),
      clock: () => time,
    );
    await restored.initialize(startTimer: false);
    expect(restored.device('living-ac')!.isOn, isFalse);
    expect(restored.device('bedroom-ac')!.isOn, isTrue);
    restored.dispose();
  });

  test('safety shutdown leaves fridge ON and stops the alarm', () async {
    for (final id in SupportedDevices.names.keys) {
      await home.setPower(id, true);
    }
    final alarm = FakeAlarm();
    final safety = SafetyController(home, alarm);
    await safety.check();
    expect(safety.activeNames, hasLength(6));
    expect(safety.activeNames, isNot(contains('Mini Fridge')));
    expect(alarm.starts, 1);
    await safety.check(turnOff: true);
    expect(home.activeCount, 1);
    expect(home.device('mini-fridge')!.isOn, isTrue);
    expect(safety.message, contains('Fridge remains ON'));
    expect(safety.sounding, isFalse);
    expect(await home.setPower('mini-fridge', false), isTrue);
    safety.dispose();
  });

  test(
    'all lights includes wall lamp and excludes TV, fridge and ACs',
    () async {
      for (final id in SupportedDevices.names.keys) {
        await home.setPower(id, true);
      }
      final result = await executeVoice(
        VoiceCommand.parse('Turn off all lights')!,
        home,
        () async {},
      );
      expect(result, contains('verified'));
      for (final d in home.appliances) {
        expect(d.isOn, !SupportedDevices.lightIds.contains(d.id), reason: d.id);
      }
    },
  );

  test(
    'old firmware reports missing new devices as unavailable, never secure',
    () async {
      await live();
      (gateway.state['devices'] as List).removeWhere(
        (d) => !['living-light', 'bedroom-light', 'mini-tv'].contains(d['id']),
      );
      (gateway.state['devices'] as List).add({'id': 'fan'});
      await home.refresh();
      expect(home.connected, isTrue);
      expect(home.appliances, hasLength(7));
      expect(home.device('mini-fridge')!.online, isFalse);
      expect(home.device('fan'), isNull);
      final safety = SafetyController(home, FakeAlarm());
      await safety.check();
      expect(safety.message, contains('unknown'));
      expect(await home.setPower('living-light', false), isTrue);
      expect(await home.setPower('mini-fridge', true), isFalse);
      safety.dispose();
    },
  );

  test(
    'old three-device demo upgrades once without invented new history',
    () async {
      await home.persist();
      final saved = (await storage.read('demo'))!;
      (saved['devices'] as List).removeWhere(
        (d) => !['living-light', 'bedroom-light', 'mini-tv'].contains(d['id']),
      );
      (saved['history'] as List).removeWhere(
        (r) => ![
          'living-light',
          'bedroom-light',
          'mini-tv',
        ].contains(r['applianceId']),
      );
      await storage.write('demo', saved);
      final restored = HomeController(storage: storage, gateway: FakeGateway());
      await restored.initialize(startTimer: false);
      expect(restored.appliances, hasLength(7));
      expect(
        restored.history.every(
          (r) => [
            'living-light',
            'bedroom-light',
            'mini-tv',
          ].contains(r.applianceId),
        ),
        isTrue,
      );
      expect(restored.device('mini-fridge')!.isOn, isFalse);
      restored.dispose();
    },
  );

  test(
    'HTTP success without matching reported state returns a visible error',
    () async {
      final unconfirmed = UnconfirmedGateway();
      home.dispose();
      home = HomeController(storage: storage, gateway: unconfirmed);
      await home.initialize(startTimer: false);
      unconfirmed.state = {
        'devices': home.appliances.map((d) => d.toJson()).toList(),
        'rooms': home.rooms.map((r) => r.toJson()).toList(),
        'history': [],
        'schedules': [],
      };
      await home.updateSettings(AppSettings(demoMode: false));
      expect(await home.setPower('mini-fridge', true), isFalse);
      expect(home.error, contains('did not confirm'));
      expect(home.device('mini-fridge')!.isOn, isFalse);
    },
  );

  test(
    'pending command identifies its device and blocks duplicate taps',
    () async {
      final delayed = DelayedGateway();
      home.dispose();
      home = HomeController(storage: storage, gateway: delayed);
      await home.initialize(startTimer: false);
      delayed.state = {
        'devices': home.appliances.map((d) => d.toJson()).toList(),
        'rooms': home.rooms.map((r) => r.toJson()).toList(),
        'history': [],
        'schedules': [],
      };
      await home.updateSettings(AppSettings(demoMode: false));
      final result = home.setPower('bedroom-wall-lamp', true);
      await delayed.sent.future;
      expect(home.pendingDeviceId, 'bedroom-wall-lamp');
      expect(await home.setPower('bedroom-wall-lamp', true), isFalse);
      delayed.release.complete();
      expect(await result, isTrue);
      expect(home.pendingDeviceId, isNull);
      expect(delayed.powerCalls, 1);
    },
  );

  test('new appliance schedules use ESP32 persistence endpoints', () async {
    await live();
    for (final id in [
      'mini-fridge',
      'living-ac',
      'bedroom-wall-lamp',
      'bedroom-ac',
    ]) {
      expect(
        await home.saveSchedule(
          DeviceSchedule(
            id: 'schedule-$id',
            applianceId: id,
            name: id,
            minuteOfDay: 10,
            turnOn: true,
            days: [1],
          ),
        ),
        isTrue,
      );
    }
    expect(home.schedules, hasLength(4));
    expect(gateway.state['schedules'], hasLength(4));
    expect(
      home.activeCount,
      1,
    ); // Saving schedules never executes them in Flutter live mode.
  });

  test(
    'legacy IDs and obsolete wattages migrate to the seven-device schema',
    () {
      final settings = AppSettings(
        applianceWatts: {'living-fridge': 88, 'bedroom-lamp': 7, 'fan': 45},
      );
      expect(settings.applianceWatts['mini-fridge'], 88);
      expect(settings.applianceWatts['bedroom-wall-lamp'], 7);
      expect(settings.applianceWatts.keys, hasLength(7));
      final preference = DevicePreference.fromJson({
        'device_id': 'bedroom-lamp',
        'display_name': 'Table Lamp',
        'room': 'Bedroom',
      });
      expect(preference.deviceId, 'bedroom-wall-lamp');
      expect(preference.displayName, 'Smart Wall Lamp');
    },
  );

  test('daily weekly and monthly limits persist locally', () async {
    await home.updateSettings(
      AppSettings(
        budget: 20,
        budgetPeriod: 'daily',
        budgetLimits: {'weekly': 120, 'monthly': 400},
      ),
    );
    final restored = AppSettings.fromJson((await storage.read('settings'))!);
    expect(restored.budgetLimits, {'daily': 20, 'weekly': 120, 'monthly': 400});
  });

  test(
    'usage aggregation counts retries and overlapping observations only once',
    () {
      UsageRecord record(String id, int a, int b) => UsageRecord(
        id: id,
        applianceId: 'mini-fridge',
        applianceName: 'Mini Fridge',
        onTime: time.add(Duration(hours: a)),
        offTime: time.add(Duration(hours: b)),
        energyKwh: (b - a) * .1,
        rate: 10,
      );
      final a = record('a', 0, 2), b = record('b', 1, 3);
      final summary = BudgetService.calculate(
        [a, a, b],
        time.add(const Duration(hours: 4)),
        'daily',
        100,
        10,
      );
      expect(summary.kwh, closeTo(.3, 1e-10));
      expect(summary.cost, closeTo(3, 1e-10));
    },
  );

  for (final phrase in {
    'TURN ON MINI FRIDGE': 'mini-fridge',
    'turn off the mini fridge please': 'mini-fridge',
    'switch the living room air conditioner on': 'living-ac',
    'turn off living room AC': 'living-ac',
    'turn on bedroom AC': 'bedroom-ac',
    'turn off bedroom air conditioner': 'bedroom-ac',
    'turn on wall lamp': 'bedroom-wall-lamp',
    'switch off the smart wall lamp': 'bedroom-wall-lamp',
  }.entries) {
    test('voice resolves ${phrase.key}', () {
      expect(VoiceCommand.parse(phrase.key)?.deviceId, phrase.value);
    });
  }
}
