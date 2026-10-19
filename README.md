# HomeEase

The existing HomeEase Flutter smart-home app for Team Rocket, with its charcoal surfaces, sage accents, navigation and modules preserved. ESP32 Wi-Fi integration adds Mini TV (LCD 16×2) through the existing appliance controls.

Starts in **demo mode**. No ESP32 or account is needed.

For the **October 15 progress report**, use the [presentation setup and physical test plan](docs/progress-report-2026-10-15.md). The relay/DC fan is disconnected and firmware-disabled by default; Fan remains available in Demo Mode and shows **Unavailable** in Live Mode.

[Android debug APK](build/app/outputs/flutter-apk/app-debug.apk) · [Dashboard preview](docs/homeease-dashboard.png) · [Devices preview](docs/homeease-devices.png) · [Energy preview](docs/homeease-energy.png)

See [verification notes](docs/verification.md) for automated checks and [hardware integration](docs/hardware-integration.md) for wiring, upload steps and remaining physical tests. Preview images show the earlier app design.

## Run

```sh
flutter pub get
flutter run
```

Choose an Android emulator or connected phone. For a browser preview:

```sh
flutter run -d edge
```

Build an Android package with `flutter build apk --debug`. iOS sources are included; iOS builds require macOS and Xcode.

## Included modules

| Module | Where to find it |
| --- | --- |
| Dashboard | Home: status, active devices, watts, rooms, energy, recent alert |
| Device control | Devices: Living Room Light, Bedroom Light, Fan, Mini TV (LCD 16×2); existing power switches and detail sheets |
| Room occupancy | Home → Rooms → View all; HC-SR04 distance, PIR motion/occupancy, separate demo switches |
| Energy monitoring | Energy: labeled rated-power estimates, date-range totals, 7-day chart; INA219 pending |
| Cost estimator | Energy: kWh × configurable PHP/kWh rate |
| Appliance history | Energy → Usage history; ON/OFF times, runtime, energy, recorded rate and cost |
| Alerts | Bell icon: Smart Exit, high load, unusual runtime, connectivity |
| Scheduling | Routines: add, edit, enable/disable and delete recurring ON/OFF actions |
| Load priority | Device details: High, Medium or Low |
| Settings | Electricity rate, thresholds, in-app alerts, demo/live mode and ESP32 address |
| ESP32 communication | Separate REST service and replaceable gateway interface |
| Local data | Persisted settings, routines, alert read state and bounded usage history |

## Structure

```text
lib/
  main.dart
  controllers/home_controller.dart
  models/
    appliance.dart
    room.dart
    usage_record.dart
    homeease_alert.dart
    schedule.dart
    app_settings.dart
  screens/
    home_shell.dart
    dashboard_screen.dart
    devices_screen.dart
    rooms_screen.dart
    energy_screen.dart
    history_screen.dart
    alerts_screen.dart
    schedules_screen.dart
    settings_screen.dart
  services/
    esp32_service.dart
    demo_data.dart
    storage_service.dart
  theme/app_theme.dart
  widgets/
    common.dart
    device_card.dart
    room_status_card.dart
    energy_card.dart
```

Widgets use a shared controller; they never make HTTP requests. `Esp32Gateway` is the hardware integration boundary. `HomeStorage` is the replaceable persistence interface. No Firebase, cloud service, login, API key or paid service is required.

## Hardware integration

The [included firmware](firmware/HomeEase/HomeEase.ino) implements [the REST API](docs/esp32-api.md) using your ESP32-WROOM-32 pins. Follow [setup and electrical checks](docs/hardware-integration.md), enter its address in Settings, turn demo mode off and save. Demo and live snapshots stay separate. Failed commands retain the last confirmed state. Mini TV shows `HomeEase TV` / `TV ON` when enabled and blanks when disabled. Physical combined-system verification, actual fan motor operation, INA219, reed sensor and buzzer remain pending.

## Demo behavior and limits

- Device toggles update watts and track estimated energy using rated watts × elapsed time.
- Closing a session records ON/OFF times, runtime, kWh and cost. Overnight sessions distribute energy proportionally across dates.
- Energy cost estimates use the current tariff. Completed history preserves the tariff recorded at switch-off.
- Demo schedules run in their matching minute while the app is open. Live schedules run in the included firmware after NTP time sync, including when the app is closed. Missed times are not replayed.
- In-app alerts check occupancy, runtime and total load. Push/background notifications are not included.
- Priorities guide device management; setting a priority does not automatically switch a relay.
- Local storage retains up to 2,000 sessions and 200 alerts per mode. The history screen shows the latest 100 sessions per appliance filter. Use a database implementation of `HomeStorage` for larger or critical records. This starter uses [SharedPreferencesAsync](https://pub.dev/packages/shared_preferences), which is intended for simple, non-critical local data.
- The 30-day selector totals available records; fresh demo data covers seven days. Charts always display the last seven days.
- Android and iOS project configuration is included. Release signing and physical ESP32 testing remain deployment steps.

## Verify

```sh
flutter analyze
flutter test
```

See [the walkthrough](docs/verification.md) for manual checks and [the API contract](docs/esp32-api.md) for endpoint details.

