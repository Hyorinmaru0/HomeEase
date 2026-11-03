> Updated GPIO map: Mini Fridge 14, Living Room AC 33, INA219 SDA 16 / SCL 17.
> Hardware integration report. Current account behavior and build verification are documented in [local account setup](simple-auth-setup.md) and [verification](verification.md); older counts/screenshots below describe the earlier build.

# HomeEase seven-appliance integration — 31 October 2026

**Current account flow:** local signup/login with a recovery code saved after signup. No email verification or backend configuration is required. See [local account setup](simple-auth-setup.md).

This updates the existing app and `firmware/HomeEase/` sketch. It preserves the dashboard/navigation, sensor monitoring, LCD content, REST gateway, foreground voice/alarm behavior, schedules and local accounts. Authentication retains its centered form layout and now shares the charcoal/sage colors and component shapes of the other modules. The latest palette-only change is in `lib/theme/auth_theme.dart` and `lib/screens/auth_screen.dart`; controller/service structure is retained. Earlier three-device/presentation reports are historical.

## Inspection and implementation

| Module | Before inspection | Update |
| --- | --- | --- |
| Appliance controls | Three supported app appliances, disabled legacy firmware fan | Seven independent devices; old fan responses ignored; GPIO32 excluded |
| Devices screen | Existing grid and room filters | Same cards/filters, now grouped by actual Living Room and Bedroom |
| Firmware | Four positional device entries/checkpoints | Seven IDs; safe OFF startup; compile-time pin collision check; ID-based checkpoint v2 with old TV/index migration |
| Sensors / TV / Wi-Fi | Working integrations already present | Pin assignments, TV text/backlight behavior, sensor sampling and reconnect logic preserved |
| Voice | Push-to-talk, duplicate prevention and three targets | New fridge, both ACs and wall-lamp aliases; lights-only includes wall lamp |
| Safety / alarm | Fresh-state checks and bundled phone sound | Seven-device availability check; default shutdown and warnings exclude fridge; individual fridge control remains available |
| Energy | Observed intervals, configurable tariff/watts, one selected budget | Seven hypothetical ratings; independent saved daily/weekly/monthly limits; duplicate/overlap exclusion in aggregates |
| Local accounts | Signup/login, saved recovery code and secure credential storage | No backend setup; account data stays on this phone |

## Complete appliance and GPIO table

| Room | Appliance | API ID | GPIO / connection | Physical behavior |
| --- | --- | --- | --- | --- |
| Living Room | Main Living Room Light | `living-light` | 25 | Existing red LED |
| Living Room | Mini TV (LCD 16×2) | `mini-tv` | SDA 21 / SCL 22 | ON: `HomeEase TV` / `TV ON`; OFF: blank and backlight off |
| Living Room | Mini Fridge | `mini-fridge` | 14 | Green power-indicator LED; manual hinged door only; no refrigeration |
| Living Room | Living Room AC | `living-ac` | 33 | Blue/white LED model; no cooling |
| Bedroom | Main Bedroom Light | `bedroom-light` | 26 | Existing green LED |
| Bedroom | Smart Wall Lamp | `bedroom-wall-lamp` | 23 | Warm-white/yellow wall-mounted LED |
| Bedroom | Bedroom AC | `bedroom-ac` | 19 | Independent blue/white LED model; no cooling |
| Bedroom | PIR OUT | — | 27 | Existing motion indication, 60-second warm-up |
| Living Room | HC-SR04 | — | TRIG 5 / ECHO 18 | Existing voltage divider retained; proximity threshold 9 cm |
| Sensor bus | INA219 SDA / SCL | ? | 16 / 17 (Wire1) | Bus configured; sensor measurements pending |
| Retired output | Former fan relay | Rejected | 32 | No startup configuration or writes; no UI device |

All 13 assigned GPIOs are distinct, including the INA219 bus pins. See [the 1 November pin update](wiring-update-2026-11-01.md). The static assertion rejects duplicate assignments and retired GPIO32 use. Pins 16/17 are suitable for the specified **ESP32-WROOM-32**; this mapping is not a claim of compatibility with modules that reserve pins for PSRAM. Check the board label against the [Espressif WROOM-32 pin definitions](https://documentation.espressif.com/esp32-wroom-32_datasheet_en.html).

## Wire the four new LED appliances

1. Disconnect USB and any other board power before changing the circuit. Keep the existing GPIO25/26 lights, sensor wiring and LCD wiring.
2. Connect ESP32 GND to the breadboard ground rail. Use the GPIO numbers printed on the board; do not count header positions.
3. Fridge: connect **GPIO14 → one 330 Ω resistor → green LED anode (+)**. Connect its cathode (−, normally the shorter leg/flat side) to GND.
4. Living Room AC: keep the user-confirmed active-low LED circuit on **GPIO33**. For a 3.3V sink circuit: 3.3V -> its own 330 ohm resistor -> LED anode; LED cathode -> GPIO33. Firmware 2.2 uses LOW = ON and HIGH = OFF for this output.
5. Smart Wall Lamp: keep the user-confirmed active-low LED circuit on **GPIO23**. For a 3.3V sink circuit: 3.3V -> its own 330 ohm resistor -> LED anode; LED cathode -> GPIO23. Firmware 2.2 uses LOW = ON and HIGH = OFF for this output.
6. Bedroom AC: connect **GPIO19 → its own 330 Ω resistor → blue/white LED anode**; cathode to GND.
7. Each LED needs its own series resistor. These instructions are for bare low-current indicator LEDs driven from 3.3 V GPIO. Check the actual LED specifications; blue/white LEDs may be dim at 3.3 V. Do not substitute LED strips, motors, cooling hardware or mains loads.
8. Leave the fridge hinge entirely manual. No servo, reed switch, door-open state or OPEN/CLOSE control is part of this system. Leave the former GPIO32 relay circuit disconnected.
9. Inspect the wiring for shorts, then reconnect USB. Firmware sets the six LED outputs and Mini TV OFF at startup. GPIOs can float before firmware starts; use external pull-ups for active-low outputs or pull-downs for active-high outputs if the model needs a defined OFF state throughout reset, and verify on the physical board.
10. Test one new appliance at a time from the Devices screen. Confirm only its intended LED changes. Test both ACs ON together, then turn one OFF and confirm the other remains ON.

Keep ECHO → existing 1 kΩ resistor → GPIO18 junction → existing 2 kΩ resistor → GND. Retain common ground and verify actual ECHO voltage. GPIO5 is an existing strapping-pin assignment: verify cold boot with the sensor connected. Keep the LCD's electrical compatibility checks: ESP32 SDA/SCL must not be pulled up to 5 V; use suitable bidirectional level shifting for a 5 V backpack. These are existing electrical requirements, not changes to sensor pins. See [ESP32 electrical/boot specifications](https://documentation.espressif.com/esp32_datasheet_en.html) and [PCF8574 specifications](https://www.nxp.com/docs/en/data-sheet/PCF8574_PCF8574A.pdf).

Living Room AC and Smart Wall Lamp use active-low polarity in firmware 2.2. Other LED outputs retain active-high polarity. See the [current polarity configuration](wiring-update-2026-11-01.md).

## Manual Arduino upload

1. Open `C:\Users\Ahron\appdev\firmware\HomeEase\HomeEase.ino` in Arduino IDE.
2. Select **ESP32 Dev Module** for the existing WROOM-32. Use installed ESP32 core 3.3.12, ArduinoJson 7.4.2 and LiquidCrystal I2C 1.1.2. Libraries are installed under `C:\Users\Ahron\Documents\Arduino\libraries`.
3. Keep the existing local `secrets.h` / `secret.h` files private and unchanged. The sketch uses the credentials already included through `HomeEaseConfig.h`; do not overwrite them with the example.
4. Click **Verify**. Select the board's actual current port under Tools → Port; COM3 was historically reported but must be confirmed now.
5. Upload only when you are ready. **This update did not flash the board.**
6. Open Serial Monitor at 115200 baud. Expect `Firmware: homeease-2.2; seven appliances; GPIO32 untouched` and the local IP after Wi-Fi connects.
7. Verify `GET http://<board-IP>/api/state` returns seven devices, both rooms and `firmware: homeease-2.2`. LED states are firmware-commanded outputs, not independent electrical feedback.
8. Install the new APK, sign into a local account, then Settings → ESP32 connection. Enter the printed base URL, turn Demo mode OFF and Save. Allow Android local-network permission when prompted.

Firmware preserves Wi-Fi credentials/reconnect events and NTP timezone UTC+08:00. Stored old fan routines/history are removed on migration. Existing light/TV totals and priorities are restored by the correct old index; new devices start with zero totals. Version 2 checkpoints identify devices by ID. Outputs still start OFF after reboot, closing prior sessions only through the last durable checkpoint.

Firmware stores up to 16 routines / 3,500 serialized bytes and up to 32 sessions within the 6,000-byte checkpoint cap. Oldest sessions can be trimmed. NTP must synchronize before schedules run; missed times are not replayed. Live routines run on the ESP32 with the app closed; demo routines require the app open. Physical reboot, NVS durability and closed-app schedule execution remain manual checks.

## REST API and compatibility

Existing routes remain `GET /api/state`, `PUT /api/devices/{id}/power`, `PUT /api/devices/{id}/priority`, and `PUT /api/schedules`. Power body: `{"isOn":true}` or `false`. The table above lists every supported device ID.

Unknown IDs/routes return 404; retired `/api/devices/fan/power` returns 503 and never touches GPIO32. Invalid JSON/values return 400; oversized requests return 413. LCD/persistence failure returns 503. App power state is reconciled by fetching ESP32 state after a command; HTTP success with a mismatched state is reported as unconfirmed. Cards show pending command state and retain last-known labels when disconnected.

Old ESP32 snapshots with `fan` remain readable. Missing new appliances appear unavailable and require a firmware upload; no successful state is invented. Available original devices can still be controlled individually. Safety checks cannot claim a clear result if any expected appliance is missing/unavailable. Obsolete routines are not sent back to legacy firmware.

## Safety, voice and energy behavior

The safety action fetches fresh state, lists relevant ON appliances, sounds bundled `assets/audio/safety_alarm.wav`, and supports dismiss/recheck/shutdown. Mini Fridge is excluded from the default warning/shutdown set because it normally remains running. The UI states this explicitly; its own switch or explicit voice command can turn it OFF. A fridge-only ON result says the fridge remains ON rather than claiming every appliance is OFF. There is no automatic exit detection, physical buzzer, door sensor or background-monitoring promise.

Push-to-talk, permission/error feedback, recognized text and duplicate-final-result suppression remain in the existing speech integration. Commands cover all seven devices, both air-conditioner names, wall lamp, all lights, home status and safety check. Generic “turn off everything” also preserves the fridge; “turn off mini fridge” is explicit. No continuous microphone listener was added.

Energy is **hypothetical configured wattage × observed hours / 1,000**, then × the user's ₱/kWh tariff. Default ratings: 12 W / 9 W / 1 W for existing light/light/TV, 100 W fridge, 750 W Living Room AC, 5 W wall lamp, 500 W Bedroom AC. These are editable scenario values, not power consumed by the miniature LEDs. No refrigeration or cooling is claimed.

Daily, weekly and monthly budget limits save independently; the selected budget period drives the 80% / 100% in-app warnings. Weeks start Monday. New wattages affect future observations. Live gaps over 20 seconds, disconnection, suspension and restarts never invent ON duration. Aggregates remove duplicate IDs and count only uncovered portions of overlapping same-appliance intervals, using the earlier-starting record (ID order breaks equal-start ties). This avoids summing simultaneous observations as independent household loads; it is still not a utility meter. Firmware estimates remain separate and are not blindly uploaded as user observations.

## Local accounts

The current app uses local signup/login and a saved recovery code. No Supabase, email, SQL migration or build configuration is required. See [local account setup](simple-auth-setup.md). Account records and history stay on this phone; ESP32 REST communication remains separate.

## Files changed

Flutter application:

- `lib/services/supported_devices.dart`, `demo_data.dart`, `voice_service.dart`, `budget_service.dart`
- `lib/models/app_settings.dart`, `account_data.dart`
- `lib/controllers/home_controller.dart`, `safety_controller.dart`, `account_data_controller.dart`
- `lib/widgets/common.dart`, `device_card.dart`, `smart_controls.dart`, `budget_card.dart`
- `lib/screens/devices_screen.dart`, `energy_screen.dart`, `settings_screen.dart`, `account_screen.dart`

Firmware: `firmware/HomeEase/HomeEase.ino`, `firmware/HomeEase/HomeEaseConfig.h`. Secret files were not edited. No board upload was performed.

Local account data replaces the former backend integration.

Tests: new `test/seven_appliances_test.dart`; updated `test/home_controller_test.dart`, `widget_test.dart`, `safety_dashboard_test.dart`, `esp32_service_test.dart`, `account_data_test.dart`.

Documentation: this guide, `README.md`, `docs/esp32-api.md`, `hardware-integration.md`, and `verification.md`.

## Dependencies and verification

No additional package is required. Existing dependencies remain Flutter, `http`, `shared_preferences`, `speech_to_text`, `audioplayers`, `flutter_secure_storage`, `uuid` and `cupertino_icons`; exact resolved versions are in `pubspec.lock`.

- `flutter pub get`: passed.
- `flutter analyze`: no issues.
- `flutter test`: 129 tests passed, including seven ON/OFF paths, AC independence, fridge exclusion, old-cache/firmware compatibility, pending/failed/unconfirmed commands, new schedules, voice aliases, local account persistence, overlap accounting, budget limits, sensor regressions and existing auth/storage checks.
- Earlier seven-appliance firmware (`homeease-2.0`) compiled for `esp32:esp32:esp32`, core 3.3.12, ArduinoJson 7.4.2, LiquidCrystal I2C 1.1.2: **1,008,545 bytes flash (76%) / 50,828 bytes static RAM (15%)**. The existing LCD library AVR-architecture metadata warning remains; compile success does not establish electrical compatibility.
- Earlier pin audit: 11 distinct assignments. The current 1 November map has 13, including INA219 SDA/SCL; GPIO32 remains excluded. No automatic flash.
- APK build/visual results are recorded in [verification.md](verification.md). Output: `C:\Users\Ahron\appdev\build\app\outputs\flutter-apk\app-debug.apk`.
- Final configured APK build passed (193,363,090 bytes). Installed/launched on Pixel 7; visually checked login, [dashboard](homeease-seven-dashboard.png), [Living Room](homeease-seven-devices-living.png) and [Bedroom](homeease-seven-devices-bedroom.png) in isolated demo mode. Formatting: 54 Dart files, 0 changes.

Build/run without backend configuration:

```powershell
cd C:\Users\Ahron\appdev
flutter run
flutter build apk --debug
```

## Still requires live verification

Physical ON/OFF of each LED, Mini TV text/backlight, independent AC operation, sensor calibration/timing, GPIO32 exclusion/reset behavior, shared supply stability, Wi-Fi reconnect, NVS restoration, routines with the app closed, Android speech/permissions/audio/vibration, local authentication on your physical phone remain unverified by these mocks/compilation checks. iOS/release signing/background monitoring were not implemented or verified as part of this Android integration.
