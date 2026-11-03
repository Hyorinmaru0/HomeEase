import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/controllers/home_controller.dart';
import 'package:homeease/main.dart';
import 'package:homeease/models/app_settings.dart';
import 'package:homeease/widgets/room_status_card.dart';
import 'package:homeease/screens/schedules_screen.dart';
import 'package:homeease/widgets/device_card.dart';

import 'fakes.dart';

void main() {
  Future<HomeController> load(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final c = HomeController(
      storage: MemoryStorage(),
      gateway: FakeGateway(),
      clock: () => DateTime(2026, 9, 28, 18),
    );
    await c.initialize(startTimer: false);
    addTearDown(() {
      c.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(HomeEaseApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  for (final width in [320.0, 390.0, 1000.0]) {
    testWidgets('all primary screens render at width $width', (tester) async {
      await load(tester, Size(width, 844));
      expect(find.text('HomeEase'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in [
        'Devices',
        'Energy',
        'Routines',
        'Settings',
        'Home',
      ]) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
    });
  }

  testWidgets('all seven supported appliances appear', (tester) async {
    final c = await load(tester, const Size(390, 844));
    expect(c.appliances.length, 7);
    expect(find.text('Fan'), findsNothing);
    expect(find.text('Smart Safety Check'), findsOneWidget);
    expect(find.text('Smart Safety Check').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Devices').last);
    await tester.pumpAndSettle();
    expect(find.byType(DeviceCard), findsNWidgets(7));
  });

  testWidgets('primary screens support larger system text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await load(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    for (final label in ['Devices', 'Energy', 'Routines', 'Settings', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
  });

  testWidgets('device toggle updates the shared state and detail sheet', (
    tester,
  ) async {
    final c = await load(tester, const Size(390, 844));
    await tester.tap(find.text('Devices').last);
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate(
      (w) => w is DeviceCard && w.device.id == 'bedroom-light',
    );
    final powerSwitch = find.descendant(
      of: card,
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(powerSwitch);
    await tester.tap(powerSwitch);
    await tester.pumpAndSettle();
    expect(c.device('bedroom-light')!.isOn, isTrue);
    await tester.ensureVisible(find.byTooltip('Bedroom Light details'));
    await tester.tap(find.byTooltip('Bedroom Light details'));
    await tester.pumpAndSettle();
    expect(find.text('Load priority'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mini TV appears on dashboard and shares its existing device control',
    (tester) async {
      final c = await load(tester, const Size(390, 844));
      expect(find.text('Mini TV (LCD 16×2)'), findsOneWidget);
      await tester.tap(find.text('Devices').last);
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is DeviceCard && w.device.id == 'mini-tv',
      );
      final toggle = find.descendant(of: card, matching: find.byType(Switch));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.device('mini-tv')!.isOn, isTrue);
      await tester.ensureVisible(find.byTooltip('Mini TV (LCD 16×2) details'));
      await tester.tap(find.byTooltip('Mini TV (LCD 16×2) details'));
      await tester.pumpAndSettle();
      expect(find.text('HomeEase TV • TV ON'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('Display blank'), findsOneWidget);
      expect(c.device('mini-tv')!.isOn, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('create, disable and delete a routine through the UI', (
    tester,
  ) async {
    final c = await load(tester, const Size(390, 844));
    await tester.tap(find.text('Routines').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create schedule'));
    await tester.tap(find.text('Create schedule'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditor), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Schedule name'),
      'Evening lights',
    );
    await tester.ensureVisible(find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();
    expect(c.schedules.any((s) => s.name == 'Evening lights'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('Delete Evening lights'));
    await tester.tap(find.byTooltip('Delete Evening lights'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(c.schedules.any((s) => s.name == 'Evening lights'), isFalse);
  });

  testWidgets('settings reject invalid energy rates', (tester) async {
    await load(tester, const Size(390, 844));
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final rate = find.widgetWithText(TextFormField, 'Electricity rate');
    await tester.ensureVisible(rate);
    await tester.enterText(rate, '-2');
    await tester.ensureVisible(find.text('Save preferences'));
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid non-negative number.'), findsOneWidget);
  });

  testWidgets(
    'live sensors and pending hardware fit the existing narrow screens',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await load(tester, const Size(320, 844));
      final gateway = c.gateway as FakeGateway;
      gateway.state = {
        'devices': c.appliances
            .map(
              (d) => {
                ...d.toJson(),
                if (d.id == 'fan')
                  'hardwareNote':
                      'Relay control; fan motor verification pending',
              },
            )
            .toList(),
        'rooms': [
          {
            'id': 'living',
            'name': 'Living room',
            'occupied': false,
            'sensor': 'HC-SR04',
            'sensorOnline': false,
            'distanceCm': null,
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
        'energySource': 'estimated',
        'pendingHardware': 'DC fan motor, INA219, door sensor, buzzer, LCD electrical compatibility',
        'clockSynced': false,
        'storageHealthy': false,
      };
      await c.updateSettings(AppSettings(demoMode: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(RoomStatusCard).first);
      await tester.tap(find.byType(RoomStatusCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Sensor unavailable'), findsOneWidget);
      expect(find.textContaining('PIR: No motion'), findsOneWidget);
      expect(find.text('Simulate occupancy'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      for (final label in ['Devices', 'Energy', 'Routines', 'Settings']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      expect(find.textContaining('Pending hardware:'), findsNothing);
    },
  );
}
