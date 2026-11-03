# HomeEase

The existing HomeEase Flutter smart-home app for Team Rocket, with consistent charcoal/sage dashboard and authentication colors, navigation and modules preserved. Seven ESP32 appliances use the existing controls, voice, safety checks, schedules and energy tracker.

Starts at **Login**, with Create Account, Forgot password and an isolated local Demo Mode. Accounts now work entirely on the phone: no Supabase, SMTP, API keys or email verification are required. Create an account, save the recovery code shown once, then continue to the dashboard. See the [local account guide](docs/simple-auth-setup.md).

Accounts, personal preferences, settings and history stay on this phone and remain saved after logout. Old cloud accounts are not imported: create a new local account in this version. Clearing app data or uninstalling can remove local accounts and records. A recovery code resets a password for an existing local account; it cannot restore deleted data or sign in on a different phone.

Current scope: Living Room Light, Mini TV, Mini Fridge and Living Room AC; Bedroom Light, Smart Wall Lamp and Bedroom AC. PIR/HC-SR04 pins remain unchanged. Read the [seven-appliance hardware guide](docs/system-update-2026-10-31.md) for wiring and manual upload instructions.

[Android APK 1.0.2 - ESP32 connection fix](build/app/outputs/flutter-apk/HomeEase-1.0.2-connection-fix.apk) · [Dashboard preview](docs/homeease-dashboard.png) · [Devices preview](docs/homeease-devices.png) · [Energy preview](docs/homeease-energy.png)

See [verification notes](docs/verification.md) for automated checks and [hardware integration](docs/hardware-integration.md) for wiring, upload steps and remaining physical tests. Preview images show the earlier app design.

Latest app update: command acknowledgments accept text or empty bodies, while fresh ESP32 state is still required for confirmation. See [connection troubleshooting](docs/esp32-confirmation-troubleshooting.md) if the model changes but an error appears.

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
| Authentication | Local signup/login; saved recovery code for password reset |
| Profile & account | Settings ? Profile & logout; local preferences, activity, profile/password edits |
| Dashboard | Home: status, active devices, watts, rooms, energy, recent alert |
| Device control | Devices: all seven appliances grouped by Living Room and Bedroom; existing power switches and detail sheets |
| Room occupancy | Home → Rooms → View all; HC-SR04 distance, PIR motion/occupancy, separate demo switches |
| Energy monitoring | Energy: configured-wattage estimates, cost budgets, device breakdown and period summaries |
| Cost estimator | Energy: kWh × configurable PHP/kWh rate |
| Appliance history | Energy → Usage history; ON/OFF times, runtime, energy, recorded rate and cost |
| Alerts | Bell icon: budget thresholds, high load, unusual runtime, connectivity |
| Scheduling | Routines: add, edit, enable/disable and delete recurring ON/OFF actions |
| Load priority | Device details: High, Medium or Low |
| Settings | Electricity rate, thresholds, in-app alerts, demo/live mode and ESP32 address |
| ESP32 communication | Separate REST service and replaceable gateway interface |
| Voice commands | Home → Smart controls; push-to-talk with recognized text and verified device commands |
| Smart Safety Check | Home → Smart controls; manual state check, phone alarm, dismiss, shutoff excluding fridge and recheck |
| Energy budget | Energy and Settings; daily/weekly/monthly cost budgets and configured appliance wattages |
| Local data | Persisted settings, routines, alert read state and bounded usage history |

## Structure

```text
lib/
  main.dart
  controllers/
    home_controller.dart
    auth_controller.dart
    account_data_controller.dart
  models/
    appliance.dart
    room.dart
    usage_record.dart
    homeease_alert.dart
    schedule.dart
    app_settings.dart
    account_data.dart
  screens/
    home_shell.dart
    auth_screen.dart
    account_screen.dart
    dashboard_screen.dart
    devices_screen.dart
    rooms_screen.dart
    energy_screen.dart
    history_screen.dart
    alerts_screen.dart
    schedules_screen.dart
    settings_screen.dart
  services/
    auth_service.dart
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

Widgets use shared controllers and repositories; they never make HTTP requests. `Esp32Gateway` remains the replaceable hardware boundary. `LocalAuthRepository` keeps identity separate from the UI and ESP32 service. Credentials use OS-backed secure storage with independently salted PBKDF2-HMAC-SHA256 hashes (600,000 iterations), computed off the UI isolate. `AccountDataController` stores personal labels and observed command activity; `HomeStorage` provides separate per-account and guest workspaces. Local login does not authenticate or secure the ESP32 REST endpoint itself.

## Hardware integration

Current [GPIO update](docs/wiring-update-2026-11-01.md): Mini Fridge **14**, Living Room AC **33**, INA219 **SDA16/SCL17**, LCD **SDA21/SCL22**. Upload the updated firmware to apply this wiring; the mobile APK does not need rebuilding for pin changes.

The [included firmware](firmware/HomeEase/HomeEase.ino) implements [the REST API](docs/esp32-api.md) using your ESP32-WROOM-32 pins. Follow [setup and electrical checks](docs/hardware-integration.md), enter its address in Settings, turn demo mode off and save. Demo and live snapshots stay separate. Failed commands retain the last confirmed state. Mini TV shows `HomeEase TV` / `TV ON` when enabled and blanks when disabled. Physical verification of the supported LEDs, LCD, ultrasonic/PIR sensors, phone speech and mobile audio remains required. Removed hardware is outside the current mobile-app scope.

## Demo behavior and limits

- Device toggles update watts and track estimated energy using rated watts × elapsed time.
- Closing a session records ON/OFF times, runtime, kWh and cost. Overnight sessions distribute energy proportionally across dates.
- Energy cost estimates use the current tariff. Completed history preserves the tariff recorded at switch-off.
- Demo schedules run in their matching minute while the app is open. Live schedules run in the included firmware after NTP time sync, including when the app is closed. Missed times are not replayed.
- In-app alerts check budget thresholds, runtime and hypothetical total load. Sensor indications never prove departure. Push/background notifications are not included.
- Priorities guide device management; setting a priority does not automatically switch devices.
- Local storage retains up to 2,000 sessions and 200 alerts per mode. The history screen shows the latest 100 sessions per appliance filter. Use a database implementation of `HomeStorage` for larger or critical records. This starter uses [SharedPreferencesAsync](https://pub.dev/packages/shared_preferences), which is intended for simple, non-critical local data.
- The 30-day selector totals available records; fresh demo data covers seven days. Charts always display the last seven days.
- Android and iOS project configuration is included. Release signing and physical ESP32 testing remain deployment steps.

## Verify

```sh
flutter analyze
flutter test
```

See [the walkthrough](docs/verification.md) for manual checks and [the API contract](docs/esp32-api.md) for endpoint details.

