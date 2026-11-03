# HomeEase feature update

The existing navigation, theme, device controls, priorities, schedules, room telemetry and demo/live modes are retained. The app supports only `living-light`, `bedroom-light` and `mini-tv`. Legacy devices, history, alerts and routines are excluded from the mobile interface. When saving live routines, existing legacy routines are carried through unchanged to avoid silently changing firmware behavior. Removing the fan from the app does not disable a fan routine already stored on the ESP32.

## Voice commands

On Home, scroll to Smart controls and tap **Voice command**. Grant microphone permission if asked, then say one command, for example “Turn on living room light”, “Switch off bedroom light”, “Turn on Mini TV”, “Turn off all lights”, “Turn off everything”, “Check home status”, or “Run safety check”. ON and OFF commands work for each supported appliance. Recognized text and execution feedback appear below the button. Cancel listening stops the microphone; repeated recognition results do not submit repeated commands.

Enable or disable this feature under Settings and save preferences. Speech uses the phone's speech-recognition service through `speech_to_text` 7.5.0. No HomeEase account or paid speech API is required. Recognition may use internet and the device provider's speech service; offline operation depends on language packs and service availability. Use an English recognition language for the supported English commands. No continuous microphone or background service is used.

## Smart Safety Check and mobile alarm

Tap the full-width **Smart Safety Check** button in Home, below the home overview. Live mode requests fresh state and requires all three appliances to be available before reporting “All monitored appliances are OFF.” Demo mode explicitly simulates the check. Warnings use the existing amber accent, with Turn Off All and Dismiss Alarm actions.

If appliances are ON, the card lists them and starts the bundled warning sound when enabled. **Dismiss Alarm** stops sound without changing appliances. **Turn Off All** sends existing power commands, then fetches state again. **View Active Devices** expands the list. **Recheck** refreshes the check. Acknowledged warnings do not repeatedly restart the audio; a verified all-off state resets the warning for the next check.

Settings includes Enable Warning Sound, optional vibration feedback and a three-second **Test Alarm Sound** button with Stop. Playback uses `audioplayers` 6.8.1, a local original WAV file, audio focus and silence-respecting platform configuration. Phone volume, silent mode, Do Not Disturb and audio routing may suppress or redirect playback. Test on the actual Android phone. This is a manual appliance-state check, not a security system or detection of door opening/departure. PIR and ultrasonic readings never trigger this alarm.

## Energy budget

In Settings, enter electricity rate in pesos/kWh, estimated wattage for each of the three appliances, a positive cost budget, and daily, weekly or monthly period. Save preferences. Energy shows estimated cost, remaining/over-budget amount, percentage, kWh, per-device breakdown and calendar daily/weekly/monthly summaries. Weeks start Monday. Costs in these summaries use the current configured electricity rate. Recorded history retains the rate used when recorded; wattage changes affect future observations rather than rewriting earlier energy.

The existing usage-record model is the single source for the reports and budget. Live tracking records only contiguous foreground observations no more than 20 seconds apart, when an appliance is online and ON in both observations with the same ON timestamp. It does not extrapolate across disconnects, restarts, suspension or unobserved transitions. Consequently it is an approximation and may undercount between observations. Previously saved supported-device history is retained. Live API cumulative energy is not added on top of the local intervals, preventing double counting. History is capped at 2,000 records; older missing coverage is not reconstructed. Incomplete coverage is explicitly shown. Demo histories are simulated.

Energy = watts × hours / 1,000; estimated cost = kWh × rate. In-app warnings fire once at 80% and once at 100% per calendar period and selected period type, with threshold acknowledgement persisted separately for demo/live. Changing the budget within the same period does not reissue an already issued threshold. No Android background notifications or continuous closed-app monitoring are implemented.

## Sensor adjustment requested separately

Following the user's subsequent 9 cm request, the only firmware source changes are `OCCUPIED_DISTANCE_CM = 9` in HomeEaseConfig.h and using `<=` in the Living Room occupancy comparison in HomeEase.ino. Valid HC-SR04 distances from 2 through 9 cm report occupied; valid distances greater than 9 cm report vacant. Missing/out-of-range echoes report sensor unavailable. No GPIO assignments or endpoints changed. Upload the updated sketch to apply this adjustment; editing the Flutter app alone cannot change the board's threshold. Test with a flat target around 8, 9 and 10 cm; boundary readings can fluctuate due to sensor noise.

## Changed files

- Controllers: `lib/controllers/home_controller.dart`, new `safety_controller.dart`.
- Models: `lib/models/app_settings.dart`, `appliance.dart`.
- Services: `lib/services/demo_data.dart`; new `supported_devices.dart`, `budget_service.dart`, `voice_service.dart`, `alarm_service.dart`.
- Screens: `dashboard_screen.dart`, `energy_screen.dart`, `history_screen.dart`, `settings_screen.dart`, `home_shell.dart`, `rooms_screen.dart`, `alerts_screen.dart`, `schedules_screen.dart` in `lib/screens/`.
- Widgets: `lib/widgets/common.dart`, `device_card.dart`; new `smart_controls.dart`, `budget_card.dart`.
- Platform/dependencies: `pubspec.yaml`, `pubspec.lock`, Android main manifest, iOS Runner Info.plist.
- Assets: `assets/audio/safety_alarm.wav`, `LICENSE.txt`.
- Tests: `test/home_controller_test.dart`, `widget_test.dart`, new `smart_features_test.dart`.
- Firmware: the two explicitly requested distance-threshold edits described above only.

Android adds RECORD_AUDIO (requested at runtime by speech recognition), VIBRATE (optional feedback) and RecognitionService package visibility. Existing internet/local-network access remains. Bluetooth speech support is disabled; no Bluetooth permission or account is added. iOS microphone and speech usage descriptions are included, but no iOS build or physical testing has been performed.

## Physical acceptance checks

1. Install the APK and test speech permission denial, permission grant, unsupported command, silence, cancel and each supported command. Confirm switches and actual LEDs/LCD agree.
2. In live mode, switch one or more appliances on and run a safety check. Test dismiss, recheck, Turn Off All, loss of Wi-Fi and a missing device. Unknown status must never say Home Secure.
3. Test alarm sound with normal/silent/DND settings, phone speaker/headphones, navigation away and putting the app in the background. Confirm no overlapping sound and no sound after dismissal or leaving the app.
4. Configure a small demo budget and test 80%/100% warnings, restart persistence and the distinction between simulated and live readings. In live mode, disconnect for several minutes and verify the gap is not counted as continuous ON time.
5. Upload the updated firmware and verify Living Room occupancy around 9 cm, plus Bedroom PIR, both lights and LCD behavior.

APK: `C:\Users\Ahron\appdev\build\app\outputs\flutter-apk\app-debug.apk`.

Plugin reference documentation: https://pub.dev/packages/speech_to_text and https://pub.dev/packages/audioplayers.

## Automated verification

- `flutter pub get`: passed.
- `flutter analyze`: no issues found.
- `flutter test`: all 60 tests passed, including 31 new feature tests and the adapted existing suite. Full final test output: `build/feature-tests.log`.
- `flutter build apk --debug`: passed after the final source changes. Build output: `build/feature-apk-build.log`.
- ESP32 compile: passed for `esp32:esp32:esp32`, using the installed Arduino libraries. Flash 1,006,929 bytes; static RAM 50,596 bytes. LiquidCrystal_I2C emits its library architecture warning; physical LCD compatibility still requires checking.
- Firmware hash comparison: only HomeEase.ino and HomeEaseConfig.h changed; these contain the separately requested 9 cm adjustment. No firmware upload or physical hardware test was performed.
