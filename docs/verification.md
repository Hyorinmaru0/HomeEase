# HomeEase verification ? local accounts

The current build replaces the former Supabase integration with local accounts. Older screenshots in this folder show earlier builds and are not evidence for the new authentication flow.

## ESP32 command confirmation update - app 1.0.2

The user reported physical LEDs changing despite a generic confirmation/Wi-Fi error. The app now accepts valid 2xx write acknowledgments with text or empty bodies, validates the following state JSON, retries one transient GET failure, and never replays a PUT automatically. Board-side command HTTP errors trigger a read-only refresh so the displayed state reflects actual telemetry while the explicit command failure remains visible. Network, timeout, permission, malformed-data and HTTP errors have distinct messages.

- Focused ESP32/controller/seven-appliance tests: 55 passed.
- Full `flutter test`: 133 passed, including the production-strength local account test.
- `flutter analyze`: no issues.
- `flutter build apk --debug`: passed. APK: `build/app/outputs/flutter-apk/HomeEase-1.0.2-connection-fix.apk`, 162,217,882 bytes, version 1.0.2 / build 3. Formatting: 54 Dart files, no changes.
- Actual board response is unverified: the computer's read-only request to the supplied local address timed out. The phone's firmware/storage status is still needed to determine the exact board-side cause.
- Firmware 2.2 upload remains pending. The authorized upload wrote no firmware: COM3 was initially held by Serial Monitor; after releasing it, esptool reported wrong boot mode. Manual BOOT/EN assistance is required before retrying. No appliance writes were sent during the network diagnosis.

See [confirmation troubleshooting](esp32-confirmation-troubleshooting.md).

## Active-low output correction - 1 November 2026

User-observed reversed controls were corrected in firmware `homeease-2.2` for Living Room AC GPIO33 and Smart Wall Lamp GPIO23. Both now use LOW for logical ON and HIGH for logical OFF. Startup preloads the same correct OFF level before enabling each GPIO. Other LED output polarities are unchanged. Compile-time checks cover the polarity truth table and pin conflicts.

ESP32 Dev Module compilation passed: 1,008,785 bytes flash (76%) and 50,828 bytes static RAM (15%). The compiled header matches source and the binary version is 2.2. The existing LCD library architecture warning remains. No board upload or app rebuild was performed; physical ON/OFF and startup verification remain pending. See [wiring and upload instructions](wiring-update-2026-11-01.md).

## GPIO update ? 1 November 2026

Firmware `homeease-2.1` configures Mini Fridge GPIO14, Living Room AC GPIO33, INA219 SDA16/SCL17 on `Wire1`, and keeps LCD SDA21/SCL22 on `Wire`. The independent pin audit and compile-time assertion pass for all 13 unique assigned pins; GPIO32 is excluded. ESP32 Dev Module compilation passed: 1,008,765 bytes flash (76%), 50,828 bytes static RAM (15%). The existing LCD library architecture warning remains. The compiled header matches the updated source after excluding Arduino's generated line directive. See [current wiring and upload steps](wiring-update-2026-11-01.md).

This configures the INA219 bus only; readings/calibration are still pending and energy remains estimated. No board upload or mobile APK rebuild was performed.

## Automated scope

- Local signup, case-insensitive email login, duplicate-email rejection, incorrect passwords, saved-session restoration, account identity stability and logout persistence.
- Password/recovery-code hashes use separate random salts. PBKDF2-HMAC-SHA256 output is checked against an independent known vector; production uses 600,000 iterations off the UI isolate. Plaintext passwords and recovery codes are not saved.
- Recovery requires the saved code, never grants appliance access during reset, rotates the code after reset, and returns to login. Recovery authorization does not survive restart. Wrong attempts trigger a persisted 30-second cooldown.
- Local write failures cannot manufacture a signup session. Corrupt credential storage is not silently replaced. Generic errors do not expose private exception details.
- Widget routing covers signup ? save recovery code ? dashboard, logout removing protected routes, retained per-account data, guest isolation, narrow screens, larger text, mismatched passwords, and visible scrolled error feedback.
- Local profile/preferences/activity restoration, bounded activity, mismatched-account rejection, and logout draining pending writes without accepting stale writes.
- Existing ESP32 REST, seven-appliance controls, voice, safety, schedules, sensor displays, energy/budget calculations and responsive module tests remain in the suite.

## Local-account app 1.0.1 check results

- `flutter analyze`: passed, no issues.
- `flutter test`: 123 tests passed across the full suite before adding the production-work-factor smoke test.
- Focused production-settings test: passed (signup + logout + login, 9,589 ms on this host). The suite now contains 124 tests; the new test was run separately after the full suite.
- `dart format --output=none --set-exit-if-changed lib test`: passed with no changes.
- `flutter build apk --debug`: passed without any backend defines.
- APK: `build/app/outputs/flutter-apk/HomeEase-1.0.1-local.apk` (same bytes as `app-debug.apk`), 162,217,462 bytes. Version name 1.0.1, version code 2.
- Source/dependency audit: no Supabase imports, dependencies or cloud sync code remain in `lib`, `test`, `pubspec.yaml` or `pubspec.lock`. Obsolete local backend configuration, migrations and templates were removed; hosted resources were not modified.

This authentication version has not been installed or tested on the user's physical phone.

## Phone acceptance check

Install the latest APK over the old debug build. Create a new local account, save its recovery code, and continue to the dashboard. Log out through Settings ? Profile & logout and log back in; reopen the app to check saved-session restoration. Reset the password using the saved code, save the replacement, and sign in with the new password. Old cloud accounts are not imported. Use another local account to check separate preferences/history.

Automated tests use injected memory stores and hardware fakes. They do not establish Android secure storage on your physical phone, actual ESP32 output/sensor behavior, phone microphone/audio permissions, or iOS behavior. Firmware was not edited or flashed for this authentication change. The earlier firmware build remains documented in [the hardware guide](system-update-2026-10-31.md).
