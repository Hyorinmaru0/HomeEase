import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/controllers/home_controller.dart';
import 'package:homeease/models/app_settings.dart';
import 'package:homeease/services/alarm_service.dart';
import 'package:homeease/theme/app_theme.dart';
import 'package:homeease/widgets/smart_controls.dart';

import 'fakes.dart';

class CountingGateway extends FakeGateway {
  int reads = 0;
  @override
  Future<Map<String, dynamic>> fetchState(String baseUrl) {
    reads++;
    return super.fetchState(baseUrl);
  }
}

class DashboardAlarm implements AlarmOutput {
  int starts = 0;
  bool playing = false;
  @override
  Future<void> start({bool vibrate = false}) async {
    starts++;
    playing = true;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> dispose() async {
    playing = false;
  }
}

void main() {
  testWidgets(
    'dashboard checks fresh live state, warns, dismisses and verifies shutoff',
    (tester) async {
      final gateway = CountingGateway();
      final home = HomeController(storage: MemoryStorage(), gateway: gateway);
      await home.initialize(startTimer: false);
      gateway.state = {
        'devices': home.appliances.map((d) => d.toJson()).toList(),
        'rooms': home.rooms.map((r) => r.toJson()).toList(),
        'history': [],
        'schedules': [],
      };
      await home.updateSettings(AppSettings(demoMode: false));
      final alarm = DashboardAlarm();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: home,
                builder: (context, _) =>
                    SmartControls(controller: home, alarm: alarm),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change the response after caching ON: the button must fetch the OFF state.
      for (final d in gateway.state['devices'] as List) {
        d['isOn'] = false;
      }
      final before = gateway.reads;
      await tester.tap(find.text('Smart Safety Check'));
      await tester.pumpAndSettle();
      expect(gateway.reads, before + 1);
      expect(find.text('All monitored appliances are OFF.'), findsOneWidget);
      expect(alarm.starts, 0);

      for (final d in gateway.state['devices'] as List) {
        d['isOn'] = d['id'] == 'bedroom-light' || d['id'] == 'mini-tv';
      }
      await tester.tap(find.text('Smart Safety Check'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Appliances still ON: Bedroom Light, Mini TV'),
        findsOneWidget,
      );
      expect(alarm.playing, isTrue);
      expect(find.text('Turn Off All (except fridge)'), findsOneWidget);
      await tester.tap(find.text('Dismiss Alarm'));
      await tester.pumpAndSettle();
      expect(alarm.playing, isFalse);
      await tester.tap(find.text('Recheck'));
      await tester.pumpAndSettle();
      expect(alarm.starts, 1);

      final beforeShutoff = gateway.reads;
      await tester.tap(find.text('Turn Off All (except fridge)'));
      await tester.pumpAndSettle();
      expect(gateway.powerCalls, 6);
      expect(gateway.reads, greaterThan(beforeShutoff));
      expect(home.activeCount, 0);
      expect(find.text('All monitored appliances are OFF.'), findsOneWidget);
      expect(alarm.playing, isFalse);

      gateway.fail = true;
      await tester.tap(find.text('Smart Safety Check'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Status unknown'), findsOneWidget);
      expect(find.text('All monitored appliances are OFF.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      home.dispose();
    },
  );
}
