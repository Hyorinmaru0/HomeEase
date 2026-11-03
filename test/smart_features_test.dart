import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/controllers/home_controller.dart';
import 'package:homeease/controllers/safety_controller.dart';
import 'package:homeease/models/app_settings.dart';
import 'package:homeease/models/usage_record.dart';
import 'package:homeease/services/alarm_service.dart';
import 'package:homeease/services/budget_service.dart';
import 'package:homeease/services/voice_service.dart';

import 'fakes.dart';

class FakeAlarm implements AlarmOutput {
  int starts = 0, stops = 0;
  @override
  Future<void> start({bool vibrate = false}) async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

class FakeSpeech implements SpeechInput {
  bool available = true;
  String? failure;
  void Function(String, bool)? result;
  @override
  Future<bool> initialize(
    void Function(String) error,
    void Function(String) status,
  ) async {
    if (failure != null) {
      error(failure!);
      return false;
    }
    return available;
  }

  @override
  Future<void> listen(void Function(String, bool) result) async {
    this.result = result;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  late HomeController home;
  late MemoryStorage storage;
  late FakeGateway gateway;
  late DateTime time;
  setUp(() async {
    time = DateTime(2026, 10, 22, 12);
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

  for (final phrase in [
    'Turn on living room light',
    'switch OFF bedroom light',
    'turn on mini tv',
    'turn off all lights',
    'turn off everything',
    'check home status',
    'run safety check',
  ]) {
    test('parses $phrase', () {
      expect(VoiceCommand.parse(phrase), isNotNull);
    });
  }
  test('unsupported and ambiguous commands never map to appliances', () {
    for (final text in [
      'turn on fan',
      'turn on mini tv and bedroom light',
      'do not turn off mini tv',
      'hello',
    ]) {
      expect(VoiceCommand.parse(text), isNull);
    }
  });
  test('voice ON OFF and everything reuse controls', () async {
    for (final text in [
      'Turn on bedroom light',
      'Turn off bedroom light',
      'Turn off everything',
    ]) {
      expect(
        await executeVoice(VoiceCommand.parse(text)!, home, () async {}),
        contains('verified'),
      );
    }
    expect(home.activeCount, 0);
  });
  test('voice offline cannot report success', () async {
    await live();
    gateway.fail = true;
    expect(
      await executeVoice(
        VoiceCommand.parse('turn on mini tv')!,
        home,
        () async {},
      ),
      contains('Failed'),
    );
  });
  test('voice setting blocks commands', () async {
    home.settings.voiceEnabled = false;
    expect(
      await executeVoice(
        VoiceCommand.parse('turn off everything')!,
        home,
        () async {},
      ),
      contains('disabled'),
    );
    expect(home.activeCount, 1);
  });
  for (final failure in ['error_permission', 'unavailable']) {
    test('speech $failure handled', () async {
      final input = FakeSpeech()..available = false;
      if (failure != 'unavailable') input.failure = failure;
      final voice = VoiceSession(input, (_) async => 'executed');
      await voice.start();
      expect(voice.listening, isFalse);
      expect(voice.message, contains('unavailable'));
      voice.dispose();
    });
  }
  test('partial and repeated final results execute exactly once', () async {
    final input = FakeSpeech();
    var calls = 0;
    final voice = VoiceSession(input, (_) async {
      calls++;
      return 'done';
    });
    await voice.start();
    input.result!('turn on mini tv', false);
    expect(calls, 0);
    input.result!('turn on mini tv', true);
    input.result!('turn on mini tv', true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    voice.dispose();
  });
  test('cancel ignores late recognition', () async {
    final input = FakeSpeech();
    var calls = 0;
    final voice = VoiceSession(input, (_) async {
      calls++;
      return 'done';
    });
    await voice.start();
    await voice.cancel();
    input.result!('turn on mini tv', true);
    expect(calls, 0);
    voice.dispose();
  });
  test('silence and unsupported speech are visible', () async {
    final input = FakeSpeech();
    final voice = VoiceSession(input, (_) async => 'bad');
    await voice.start();
    input.result!('', true);
    expect(voice.message, contains('No speech'));
    await voice.start();
    input.result!('turn on fan', true);
    expect(voice.message, contains('Unsupported'));
    voice.dispose();
  });

  test('safety all off is verified, with no alarm', () async {
    await home.turnOffSupported();
    final alarm = FakeAlarm();
    final safety = SafetyController(home, alarm);
    await safety.check();
    expect(safety.message, equals('All monitored appliances are OFF.'));
    expect(alarm.starts, 0);
    safety.dispose();
  });
  test(
    'one and multiple active devices, dismiss and repeated warning',
    () async {
      final alarm = FakeAlarm();
      final safety = SafetyController(home, alarm);
      await safety.check();
      expect(safety.activeNames.length, 1);
      expect(alarm.starts, 1);
      await home.setPower('mini-tv', true);
      await safety.check();
      expect(safety.activeNames.length, 2);
      expect(alarm.starts, 1);
      await safety.dismiss();
      expect(safety.sounding, isFalse);
      await safety.check();
      expect(alarm.starts, 1);
      await safety.check(turnOff: true);
      expect(home.activeCount, 0);
      expect(safety.message, equals('All monitored appliances are OFF.'));
      await home.setPower('mini-tv', true);
      await safety.check();
      expect(alarm.starts, 2);
      safety.dispose();
    },
  );
  test('sound disabled retains visual warning', () async {
    home.settings.alarmEnabled = false;
    final alarm = FakeAlarm();
    final safety = SafetyController(home, alarm);
    await safety.check();
    expect(safety.warning, isTrue);
    expect(alarm.starts, 0);
    safety.dispose();
  });
  test('offline and control failure never report secure', () async {
    await live();
    final safety = SafetyController(home, FakeAlarm());
    await safety.check();
    gateway.fail = true;
    await safety.check(turnOff: true);
    expect(safety.message, contains('Could not verify'));
    await safety.check();
    expect(safety.message, contains('unknown'));
    safety.dispose();
  });
  test('missing device never reports secure', () async {
    await live();
    (gateway.state['devices'] as List).removeLast();
    final safety = SafetyController(home, FakeAlarm());
    await safety.check();
    expect(safety.message, contains('unknown'));
    safety.dispose();
  });
  test('secure state becomes unknown after connection loss', () async {
    await live();
    await home.turnOffSupported();
    final safety = SafetyController(home, FakeAlarm());
    await safety.check();
    expect(safety.message, equals('All monitored appliances are OFF.'));
    gateway.fail = true;
    await home.refresh();
    expect(safety.message, contains('unknown'));
    safety.dispose();
  });

  for (final amount in [79.0, 80.0, 100.0, 120.0]) {
    test('budget threshold at $amount percent', () {
      final r = UsageRecord(
        id: 'x',
        applianceId: 'mini-tv',
        applianceName: 'Mini TV',
        onTime: time.subtract(const Duration(hours: 1)),
        offTime: time,
        energyKwh: amount / 10,
        rate: 10,
      );
      final b = BudgetService.calculate([r], time, 'daily', 100, 10);
      expect(b.cost, amount);
      expect(
        b.threshold,
        amount >= 100
            ? 100
            : amount >= 80
            ? 80
            : 0,
      );
      expect(b.remaining, 100 - amount);
    });
  }
  test('cost responds to rate without changing kWh', () {
    final r = UsageRecord(
      id: 'x',
      applianceId: 'mini-tv',
      applianceName: 'TV',
      onTime: time.subtract(const Duration(hours: 1)),
      offTime: time,
      energyKwh: .5,
      rate: 10,
    );
    final a = BudgetService.calculate([r], time, 'monthly', 100, 10),
        b = BudgetService.calculate([r], time, 'monthly', 100, 20);
    expect(a.kwh, b.kwh);
    expect(b.cost, a.cost * 2);
  });
  test(
    'live energy observes contiguous intervals, not offline gaps or restarts',
    () async {
      await live();
      expect(home.todayKwh, 0);
      time = time.add(const Duration(seconds: 10));
      await home.refresh();
      expect(home.todayKwh, closeTo(12 * 10 / 3600000, 1e-10));
      final before = home.todayKwh;
      gateway.fail = true;
      time = time.add(const Duration(hours: 1));
      await home.refresh();
      gateway.fail = false;
      await home.refresh();
      expect(home.todayKwh, before);
      await home.persist();
      final restored = HomeController(
        storage: storage,
        gateway: gateway,
        clock: () => time.add(const Duration(hours: 2)),
      );
      await restored.initialize(startTimer: false);
      expect(restored.energyForDays(1), before);
      expect(restored.usageIncomplete, isTrue);
      restored.dispose();
    },
  );
  test(
    'wattage changes apply forward and persist with budget settings',
    () async {
      await home.turnOffSupported();
      final settings = AppSettings(
        budget: 50,
        budgetPeriod: 'weekly',
        voiceEnabled: false,
        alarmEnabled: false,
        applianceWatts: {
          'living-light': 12,
          'bedroom-light': 9,
          'mini-tv': 100,
        },
      );
      await home.updateSettings(settings);
      await home.setPower('mini-tv', true);
      time = time.add(const Duration(hours: 1));
      await home.setPower('mini-tv', false);
      expect(home.history.first.energyKwh, closeTo(.1, 1e-9));
      final restored = HomeController(
        storage: storage,
        gateway: FakeGateway(),
        clock: () => time,
      );
      await restored.initialize(startTimer: false);
      expect(restored.settings.budget, 50);
      expect(restored.settings.budgetPeriod, 'weekly');
      expect(restored.settings.voiceEnabled, isFalse);
      expect(restored.device('mini-tv')!.ratedWatts, 100);
      restored.dispose();
    },
  );
  test(
    'budget warning thresholds survive restart without repetition',
    () async {
      home.history = [
        UsageRecord(
          id: 'budget',
          applianceId: 'mini-tv',
          applianceName: 'TV',
          onTime: time.subtract(const Duration(hours: 1)),
          offTime: time,
          energyKwh: 10,
          rate: 10,
        ),
      ];
      await home.updateSettings(
        AppSettings(budget: 100, electricityRate: 10, budgetPeriod: 'daily'),
      );
      final count = home.alerts.where((a) => a.id.startsWith('budget-')).length;
      expect(count, 2);
      await home.tick();
      expect(
        home.alerts.where((a) => a.id.startsWith('budget-')).length,
        count,
      );
      final restored = HomeController(
        storage: storage,
        gateway: FakeGateway(),
        clock: () => time,
      );
      await restored.initialize(startTimer: false);
      expect(
        restored.alerts.where((a) => a.id.startsWith('budget-')).length,
        count,
      );
      restored.dispose();
    },
  );
  test(
    'empty history is zero with explicitly incomplete live coverage',
    () async {
      await live();
      expect(home.budgetSummary.kwh, 0);
      expect(home.usageIncomplete, isTrue);
    },
  );
}
