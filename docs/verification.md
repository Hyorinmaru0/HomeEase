# Verification guide

## Firmware version consistency repair

A later inspection found the local sketch reporting `homeease-1.0` and missing its fan-disable guards even though the configuration still set `HOMEEASE_ENABLE_FAN_RELAY=0`. Restored the guards for startup, commands, routines and telemetry while preserving the Wi-Fi retry correction. The source now reports `homeease-1.1`, adds `fanRelayEnabled: false` to `/api/state` in presentation mode, and prints its version/fan configuration at startup. A read-only request to `http://10.17.244.67/api/state` timed out from the development computer; the installed board version remains unverified.

## Wi-Fi retry correction

The reported `wifi:sta is connecting, return error` appeared approximately every 15 seconds, matching the firmware's manual retry interval. Removed that timer-driven `WiFi.reconnect()` call so it does not overlap the ESP32 core's automatic reconnect attempts. Added event logs for association, IP acquisition/loss and numeric disconnect reasons without printing credentials. This corrects the overlapping retry; the underlying hotspot connection failure still requires fresh device logs and physical verification.

Corrected sketch compiled successfully for ESP32 Dev Module: 1,006,625 bytes flash and 50,596 bytes static RAM. The existing LCD library architecture warning remains. No upload or physical connection test was performed for this correction.

## October 15 presentation configuration

- Existing app design/modules retained. Relay and motor are disconnected; `HOMEEASE_ENABLE_FAN_RELAY=0` is the firmware default.
- GPIO32 is excluded from startup pin configuration, manual power requests, scheduled execution and active energy estimates. The REST device remains present and unavailable; direct power writes return 503. This is software verification, not a physical pin measurement.
- `flutter analyze`: no issues. `flutter test`: **29 tests passed**, including unavailable fan switches on dashboard, Devices and details, controller rejection of fan writes, working connected controls, and preserved demo fan behavior.
- `flutter build apk --debug --no-pub`: passed; the presentation APK is `build/app/outputs/flutter-apk/app-debug.apk`.
- ESP32 Dev Module firmware compile passed with ESP32 core 3.3.12, ArduinoJson 7.4.2 and LiquidCrystal I2C 1.1.2. Flash: **1,006,245 bytes (76%)**; static RAM: **50,604 bytes (15%)**.
- The existing LCD library still emits an AVR-architecture metadata warning; ESP32 compilation succeeds. LCD runtime/electrical checks remain pending.
- No upload, GPIO32 measurement, physical Wi-Fi test or combined component test was performed. See the [presentation plan](progress-report-2026-10-15.md) for Android setup and acceptance checks.

The records below describe earlier builds, before the presentation fan-disable update.

## ESP32 integration update — 13 October 2026

The existing application design/navigation/modules are preserved. Mini TV uses the existing appliance controls and is included in the dashboard. Live room monitoring adds ultrasonic distance, PIR motion and availability labels; demo data remains isolated. Rated-power estimates are explicitly labeled. See [hardware integration](hardware-integration.md) for the exact user-tested GPIO mapping, electrical checks, upload instructions and physical acceptance checklist.

- ESP32 firmware compiled successfully for `esp32:esp32:esp32` using core 3.3.12, ArduinoJson 7.4.2 and LiquidCrystal I2C 1.1.2.
- Final firmware footprint: 1,005,741 bytes flash (76%), 50,596 bytes static RAM (15%). The final build includes bounded NVS blob checkpoints. LCD library metadata emits an AVR compatibility warning; this did not prevent the ESP32 build.
- Added tests cover old demo-save migration, Mini TV controls/routines/history, all four REST power paths, sensor cache/source separation, unavailable sensor alerts, failed command recovery, and live UI on a 320-pixel screen at 1.3× text scale.
- Final `flutter analyze`: no issues. Final `flutter test`: all **27 tests passed**. The narrow-screen live test caught a long sensor-status overflow, resolved by wrapping the existing status badge.
- `flutter build apk --debug --no-pub`: passed. Updated APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- No firmware upload, COM3 operation, physical Wi-Fi request, motor operation or electrical measurement was performed. User-reported individual tests are separate from these software checks. INA219, door sensor and buzzer remain pending.

The following design-preview record is historical; the integration update above supersedes its earlier firmware-deferred status.

## Design refresh verified on 12 October 2026

- Flutter 3.47.5 / Dart 3.13.4.
- `flutter analyze`: no issues.
- `flutter test`: all 19 tests passed, including 320/390/1000-pixel layouts and 1.3× system text.
- Universal Android debug APK built with ARMv7, ARM64 and x86_64 support: `build/app/outputs/flutter-apk/app-debug.apk`.
- Installed and launched successfully on the Pixel 7 emulator (Android 17).
- Native dashboard, devices, energy, routines and settings layouts visually inspected on the Pixel 7 emulator. The final filter-contrast and row-alignment fixes were checked with hot reload; the debug APK was rebuilt afterward. Preview images are saved alongside this guide.
- Physical ESP32 communication and iOS builds have not been tested; firmware is intentionally deferred.

The first Android build required installing NDK 28.2.13676358 and Android SDK Platform 36. With the new Android CLI, the NDK package identifier is `ndk/28.2.13676358`; the legacy `sdkmanager.bat` wrapper failed to pass this package correctly on this machine.

[Dashboard preview](homeease-dashboard.png) · [Devices preview](homeease-devices.png) · [Energy preview](homeease-energy.png) · [Routines preview](homeease-routines.png) · [Settings preview](homeease-settings.png)

The refresh uses neutral charcoal surfaces and soft sage accents, compact device rows, consistent headings and spacing, and a power-first dashboard. Existing demo behavior and the separate ESP32 communication layer are unchanged.

Run from the project root:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

## Demo walkthrough

1. Open Home. The Demo badge identifies simulated data; the overview shows current watts and active-device counts.
2. Open Devices and toggle Bedroom Light on. Current watts and device counts update across the app.
3. Open a device's arrow button to view runtime, session energy and set a load priority.
4. Open Home → Rooms → View all. Mark a powered room vacant. A Smart Exit alert appears; opening Alerts allows marking it read.
5. Turn a device off. Usage history records its ON/OFF times, duration, energy and estimated cost.
6. Open Routines. Create a schedule for a minute shortly in the future; keep the app open through that minute. Confirm the device changes once. Edit, disable or delete the schedule.
7. Open Settings. Set the high-load threshold below current total watts and save; a high-load alert appears. Restore it afterward.
8. Change the rate and alert preferences, save, and restart. Settings, history and routines should remain.
9. Disable demo mode with an unreachable address. Confirm the offline banner appears and no demo readings are presented as live readings. Turn demo mode back on to restore the demo home.

## Automated coverage

Tests cover energy and cost calculations, overnight sessions, occupancy alert deduplication, load/runtime thresholds, scheduled execution, saved demo/live separation, storage failures, failed hardware commands, malformed telemetry, request encoding, HTTP errors, primary screens at phone and tablet widths, and 1.3× system text scaling.

Actual ESP32 communication requires uploading the included firmware and performing the physical checks in the hardware guide. iOS packaging requires a Mac with Xcode. Release distribution requires your own app signing configuration.
