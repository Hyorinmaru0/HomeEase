import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/controllers/home_controller.dart';
import 'package:homeease/models/app_settings.dart';
import 'package:homeease/models/homeease_alert.dart';
import 'package:homeease/models/schedule.dart';
import 'package:homeease/models/usage_record.dart';

import 'fakes.dart';

void main() {
  late DateTime time;
  late MemoryStorage storage;
  late FakeGateway gateway;
  late HomeController c;
  setUp(() async {
    time = DateTime(2026, 9, 28, 12);
    storage = MemoryStorage();
    gateway = FakeGateway();
    c = HomeController(storage: storage, gateway: gateway, clock: () => time);
    await c.initialize(startTimer: false);
  });
  tearDown(() => c.dispose());

  test(
    'presentation fan is unavailable live but retains demo control',
    () async {
      final demoFanOn = c.device('fan')!.isOn;
      gateway.state = {
        'devices': c.appliances
            .map(
              (d) => {
                ...d.toJson(),
                if (d.id == 'fan') ...{
                  'online': false,
                  'isOn': false,
                  'watts': 0,
                  'onSince': null,
                  'hardwareNote':
                      'Not connected; relay and fan disabled for presentation',
                },
              },
            )
            .toList(),
        'rooms': c.rooms.map((r) => r.toJson()).toList(),
        'history': [],
        'schedules': [],
      };
      await c.updateSettings(AppSettings(demoMode: false));
      expect(c.appliances.length, 4);
      expect(c.device('fan')!.online, isFalse);
      expect(await c.setPower('fan', true), isFalse);
      expect(await c.setPower('fan', false), isFalse);
      expect(gateway.powerCalls, 0);
      for (final id in ['living-light', 'bedroom-light', 'mini-tv']) {
        expect(await c.setPower(id, true), isTrue);
      }
      expect(gateway.powerCalls, 3);
      await c.updateSettings(AppSettings());
      expect(c.device('fan')!.online, isTrue);
      expect(c.device('fan')!.isOn, demoFanOn);
      expect(await c.setPower('fan', !demoFanOn), isTrue);
      expect(gateway.powerCalls, 3);
    },
  );

  test(
    'Mini TV is added once to old demo saves without resetting data',
    () async {
      await c.setPower('bedroom-light', true);
      final saved = (await storage.read('demo'))!;
      (saved['devices'] as List).removeWhere((d) => d['id'] == 'mini-tv');
      await storage.write('demo', saved);
      final restored = HomeController(storage: storage, gateway: FakeGateway());
      await restored.initialize(startTimer: false);
      expect(restored.appliances.length, 4);
      expect(restored.device('bedroom-light')!.isOn, isTrue);
      expect(restored.history.length, c.history.length);
      expect(restored.schedules.length, c.schedules.length);
      await restored.persist();
      restored.dispose();
      final again = HomeController(storage: storage, gateway: FakeGateway());
      await again.initialize(startTimer: false);
      expect(again.appliances.where((d) => d.id == 'mini-tv').length, 1);
      again.dispose();
    },
  );

  test('Mini TV uses existing demo sessions, totals and schedules', () async {
    final before = c.currentWatts;
    expect(await c.setPower('mini-tv', true), isTrue);
    expect(c.currentWatts, before + 1);
    time = time.add(const Duration(hours: 1));
    await c.setPower('mini-tv', false);
    expect(c.history.first.applianceId, 'mini-tv');
    expect(c.history.first.energyKwh, closeTo(.001, .0000001));
    await c.saveSchedule(
      DeviceSchedule(
        id: 'tv-routine',
        applianceId: 'mini-tv',
        name: 'TV',
        minuteOfDay: time.hour * 60,
        turnOn: true,
        days: [time.weekday],
      ),
    );
    await c.tick();
    expect(c.device('mini-tv')!.isOn, isTrue);
    expect(gateway.powerCalls, 0);
  });

  test(
    'sensor telemetry is live, cached, and never mutated by demo switches',
    () async {
      gateway.state = {
        'energySource': 'estimated',
        'devices': c.appliances.map((d) => d.toJson()).toList(),
        'rooms': [
          {
            'id': 'living',
            'name': 'Living room',
            'occupied': true,
            'sensor': 'HC-SR04',
            'sensorOnline': true,
            'distanceCm': 42.5,
          },
          {
            'id': 'bedroom',
            'name': 'Bedroom',
            'occupied': true,
            'sensor': 'PIR',
            'sensorOnline': true,
            'motion': false,
          },
        ],
        'history': [],
        'schedules': [],
      };
      await c.updateSettings(AppSettings(demoMode: false));
      expect(c.sensorReading(c.rooms.first), contains('42.5 cm'));
      expect(c.sensorReading(c.rooms.last), contains('No motion'));
      expect(
        c.rooms.last.occupied,
        isTrue,
      ); // Firmware's 7-second hold is authoritative.
      expect(c.energyLabel, 'Estimated energy (rated power)');
      await c.setOccupancy('living', false);
      expect(c.rooms.first.occupied, isTrue);
      final cached = (await storage.read('live'))!;
      expect((cached['rooms'] as List).first['distanceCm'], 42.5);
      gateway.fail = true;
      await c.refresh();
      expect(c.roomStatus(c.rooms.first), 'Last known');
      expect(c.sensorReading(c.rooms.first), startsWith('Last known ESP32'));
      expect(c.canControl, isFalse);
      await c.updateSettings(AppSettings());
      expect(c.rooms.first.sensor, isNull);
      expect(c.sensorReading(c.rooms.first), contains('Simulated'));
    },
  );

  test('unavailable sensors never raise a false vacant-room alert', () async {
    gateway.state = {
      'devices': c.appliances.map((d) => d.toJson()).toList(),
      'rooms': c.rooms
          .map((r) => {...r.toJson(), 'occupied': false, 'sensorOnline': false})
          .toList(),
      'history': [],
      'schedules': [],
    };
    await c.updateSettings(AppSettings(demoMode: false));
    expect(c.alerts.where((a) => a.kind == AlertKind.smartExit), isEmpty);
    expect(c.roomStatus(c.rooms.first), 'Sensor unavailable');
    gateway.state['rooms'][0]['distanceCm'] = -1;
    await c.refresh();
    expect(c.connected, isFalse);
    expect(c.rooms.first.distanceCm, isNull);
  });

  test(
    'live Mini TV changes only after remote confirmation and recovers',
    () async {
      gateway.state = {
        'devices': c.appliances.map((d) => d.toJson()).toList(),
        'rooms': c.rooms.map((r) => r.toJson()).toList(),
        'history': [],
        'schedules': [],
      };
      await c.updateSettings(AppSettings(demoMode: false));
      expect(await c.setPower('mini-tv', true), isTrue);
      expect(gateway.powerCalls, 1);
      gateway.fail = true;
      expect(await c.setPower('mini-tv', false), isFalse);
      expect(c.device('mini-tv')!.isOn, isTrue);
      gateway.fail = false;
      await c.refresh();
      expect(await c.setPower('mini-tv', false), isTrue);
      expect(c.device('mini-tv')!.isOn, isFalse);
      gateway.state['devices'][3]['online'] = false;
      await c.refresh();
      final calls = gateway.powerCalls;
      expect(await c.setPower('mini-tv', true), isFalse);
      expect(gateway.powerCalls, calls);
    },
  );

  test('demo device session records runtime, kWh and cost', () async {
    expect(await c.setPower('bedroom-light', true), isTrue);
    time = time.add(const Duration(hours: 2));
    await c.tick();
    expect(await c.setPower('bedroom-light', false), isTrue);
    final record = c.history.first;
    expect(record.runtime, const Duration(hours: 2));
    expect(record.energyKwh, closeTo(.018, .000001));
    expect(record.cost, closeTo(.207, .000001));
    expect(gateway.powerCalls, 0);
  });
  test('occupancy alerts are deduplicated until condition clears', () async {
    await c.setOccupancy('living', false);
    final count = c.alerts.length;
    await c.tick();
    await c.tick();
    expect(c.alerts.length, count);
    await c.setOccupancy('living', true);
    await c.setOccupancy('living', false);
    expect(c.alerts.length, count + 1);
  });
  test(
    'high-load and long-runtime thresholds produce distinct alerts',
    () async {
      await c.updateSettings(
        AppSettings(highLoadWatts: 20, longRuntimeHours: .25),
      );
      expect(c.alerts.any((a) => a.kind == AlertKind.highLoad), isTrue);
      expect(c.alerts.any((a) => a.kind == AlertKind.abnormalUsage), isTrue);
    },
  );
  test(
    'schedule executes once per matching minute and persists execution',
    () async {
      final rule = DeviceSchedule(
        id: 'test',
        applianceId: 'bedroom-light',
        name: 'Test',
        minuteOfDay: 12 * 60,
        turnOn: true,
        days: [time.weekday],
      );
      await c.saveSchedule(rule);
      await c.tick();
      expect(c.device('bedroom-light')!.isOn, isTrue);
      await c.setPower('bedroom-light', false);
      await c.tick();
      expect(c.device('bedroom-light')!.isOn, isFalse);
      final restored = HomeController(
        storage: storage,
        gateway: FakeGateway(),
        clock: () => time,
      );
      await restored.initialize(startTimer: false);
      await restored.tick();
      expect(restored.device('bedroom-light')!.isOn, isFalse);
      restored.dispose();
    },
  );
  test('demo and live data stay separate across mode changes', () async {
    final demoCount = c.history.length;
    await c.setPower('bedroom-light', true);
    await c.updateSettings(AppSettings(demoMode: false));
    expect(c.history, isEmpty);
    expect(c.appliances, isEmpty);
    expect(c.connected, isTrue);
    await c.updateSettings(AppSettings());
    expect(c.history.length, demoCount);
    expect(c.device('bedroom-light')!.isOn, isTrue);
  });
  test('failed hardware command keeps last confirmed state', () async {
    gateway.state = {
      'devices': c.appliances.map((d) => d.toJson()).toList(),
      'rooms': c.rooms.map((r) => r.toJson()).toList(),
      'history': [],
      'schedules': [],
    };
    await c.updateSettings(AppSettings(demoMode: false));
    gateway.fail = true;
    expect(await c.setPower('living-light', false), isFalse);
    expect(c.device('living-light')!.isOn, isTrue);
    expect(c.connected, isFalse);
    expect(c.error, isNotNull);
  });
  test(
    'malformed telemetry leaves the whole previous snapshot intact',
    () async {
      gateway.state = {
        'devices': c.appliances.map((d) => d.toJson()).toList(),
        'rooms': c.rooms.map((r) => r.toJson()).toList(),
        'history': [],
        'schedules': [],
      };
      await c.updateSettings(AppSettings(demoMode: false));
      gateway.state['rooms'] = [
        {'id': 'bad'},
      ];
      await c.refresh();
      expect(c.rooms.length, 2);
      expect(c.appliances.length, 4);
      expect(c.connected, isFalse);
    },
  );
  test(
    'storage failure is visible without losing in-memory controls',
    () async {
      storage.failWrites = true;
      expect(await c.setPower('bedroom-light', true), isTrue);
      expect(c.device('bedroom-light')!.isOn, isTrue);
      expect(c.storageError, isNotNull);
    },
  );
  test('overnight energy is apportioned between calendar days', () {
    final r = UsageRecord(
      id: '1',
      applianceId: 'fan',
      applianceName: 'Fan',
      onTime: DateTime(2026, 9, 27, 23),
      offTime: DateTime(2026, 9, 28, 1),
      energyKwh: .09,
      rate: 10,
    );
    expect(r.energyOn(DateTime(2026, 9, 27)), closeTo(.045, .000001));
    expect(r.energyOn(DateTime(2026, 9, 28)), closeTo(.045, .000001));
    expect(r.energyOn(DateTime(2026, 9, 29)), 0);
  });
}
