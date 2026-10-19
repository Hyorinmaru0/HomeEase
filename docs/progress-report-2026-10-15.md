# HomeEase — October 15, 2026 demonstration plan

## Scope and status

The existing Flutter UI, dashboard, navigation, settings, energy/history, alerts, priorities and routines remain. The physical demonstration uses two LEDs, the LCD Mini TV, HC-SR501 PIR and HC-SR04. The user reports that these passed individual tests; combined operation has **not** been verified by this coding session.

The relay and DC fan are disconnected and excluded. The `fan` appliance remains in the API and app with `online: false`, `isOn: false`, zero active watts and a not-connected explanation. Existing card and detail switches disable themselves using `online`. Demo fan operation remains available. Fan routines are retained, but firmware skips them while disabled. Direct fan power requests return HTTP 503 without touching GPIO32.

## Files changed for this configuration

- `firmware/HomeEase/HomeEaseConfig.h`: `HOMEEASE_ENABLE_FAN_RELAY` defaults to `0`; existing polarity setting is retained.
- `firmware/HomeEase/HomeEase.ino`: guards startup GPIO configuration, manual control, routine execution and live telemetry; adds Serial diagnostics.
- `lib/widgets/device_card.dart`: unavailable status on existing cards/details and a not-connected power description. Existing `online` guards are reused.
- `lib/screens/rooms_screen.dart`: unavailable appliance status in existing room lists.
- `test/home_controller_test.dart`, `test/widget_test.dart`: live fan rejection, enabled connected appliances, unchanged demo fan behavior and disabled UI switches.

No application modules were removed or recreated. REST paths remain `GET /api/state`, `PUT /api/devices/{id}/power`, `PUT /api/devices/{id}/priority` and `PUT /api/schedules`. Priorities and saved fan routines remain editable metadata; they cannot bypass disabled fan power.

## Hardware configuration

| Component | GPIO | Presentation status |
| --- | --- | --- |
| Red Living Room LED | 25 | Connected; individual resistor |
| Green Bedroom LED | 26 | Connected; individual resistor |
| HC-SR501 PIR | 27 | Connected; 60 s warm-up, 7 s no-motion hold |
| HC-SR04 TRIG / ECHO | 5 / 18 | Connected; ECHO through 1 kΩ / 2 kΩ divider |
| LCD SDA / SCL | 21 / 22 | Connected, address 0x27; electrical compatibility still to verify |
| Relay / physical fan | 32 reserved | Disconnected and firmware-disabled |
| Reed sensor, INA219, buzzer | Future | Not enabled; no fabricated readings |

LCD ON displays `HomeEase TV` and `TV ON`; OFF blanks the display and disables its backlight. LCD supply power is not disconnected. Sensor values come from the board; energy remains explicitly estimated because INA219 is not enabled. Network failure never silently changes to demo mode.

The loop uses elapsed-time checks for sensors, PIR hold, Wi-Fi reconnect and diagnostics. HC-SR04 echo measurement can block for at most 25 ms per sample, with a 250 ms sampling interval; this is bounded polling, not fully asynchronous capture. Serial status prints every five seconds at 115200 baud, with IP on connection and power command logs. PIR's 7-second hold runs on the board; the app's five-second polling can delay its visible transition.

## Upload and connect an Android phone

1. With power off, verify each LED resistor, common grounds, and ECHO divider orientation: ECHO → 1 kΩ → GPIO18 junction → 2 kΩ → GND. Keep relay and fan disconnected.
2. Verify the actual LCD backpack supply, chip and I2C pull-up voltages. A 5 V backpack may require a bidirectional level shifter with a 3.3 V ESP32 side. Do not assume existing wiring is safe merely because characters appeared. See the [electrical checklist](hardware-integration.md#electrical-checks-still-required).
3. Open `firmware/HomeEase/HomeEase.ino` in Arduino IDE. Use ESP32 core 3.3.12, ArduinoJson 7.4.2 and LiquidCrystal I2C 1.1.2, matching the software build environment.
4. Copy `secrets.example.h` to `secrets.h` in that folder. Enter your 2.4 GHz Wi-Fi SSID/password locally. Leave `HOMEEASE_ENABLE_FAN_RELAY` at **0** in `HomeEaseConfig.h`.
5. Select **ESP32 Dev Module**, connect your ESP32-WROOM-32 by USB and select its port (previously **COM3**; verify the current port). Click Verify, then Upload. If the board cannot enter upload mode, use its BOOT button as required by your board.
6. Open Serial Monitor at **115200 baud**, reset if needed, and confirm the fan-disabled message and `HomeEase address: http://...`. Allow the PIR warm-up to finish. Check LCD acknowledgement and ultrasonic status in the periodic diagnostics.
7. Install the updated `build/app/outputs/flutter-apk/app-debug.apk` on the Android phone, allowing installation from your chosen file-transfer source if Android prompts. It is a debug build for this demonstration.
8. Join the phone to the same LAN. Use a network that permits communication between clients; avoid guest/client isolation. A phone on the same router's other Wi-Fi band is acceptable if both bands share the LAN.
9. Open HomeEase → Settings. Enter the printed base URL including `http://` and without `/api/state`. Disable Demo Mode and save. Grant local-network access if prompted. Confirm **ESP32 connected**.
10. Confirm Fan shows **Unavailable**, both its card/detail switches are disabled, and the other three switches are available. Open Rooms for PIR motion and ultrasonic distance. If connection fails, verify the board's current IP, Wi-Fi and Android network permission; use Reconnect.

## Physical checks before presenting

- [ ] Verify LCD voltage compatibility/level shifting, LED resistors, divider and common grounds before powering the combined assembly.
- [ ] Cold boot with all presentation components attached; observe stable power, outputs initially OFF and fan-disabled log. GPIO32 must not be used for this demo.
- [ ] Confirm phone-to-board Wi-Fi state retrieval; device states are not demo data.
- [ ] Toggle Living Room LED repeatedly; Bedroom LED and LCD stay unchanged.
- [ ] Toggle Bedroom LED repeatedly; Living Room LED and LCD stay unchanged.
- [ ] Toggle Mini TV repeatedly; exact two lines appear ON and screen is blank OFF.
- [ ] Move in front of PIR after warm-up. Confirm raw motion, occupied hold, and vacancy seven seconds after OUT stops being HIGH (plus app polling delay).
- [ ] Move a target near/far from HC-SR04; compare displayed distance with a ruler. Calibrate the configured occupancy threshold. No echo must show unavailable rather than a fabricated distance.
- [ ] While both sensors change, repeatedly control LEDs/LCD and check responsiveness and absence of resets.
- [ ] Confirm fan controls are disabled in dashboard, Devices and details. If validating via REST, a fan power PUT must return 503 and leave GPIO32 untouched; saved fan routines must also do nothing physically.
- [ ] Disconnect/reconnect Wi-Fi; the app must show stale/offline information and recover without substituting demo readings.
- [ ] Switch to Demo Mode, verify simulated fan toggling, then return to Live Mode and confirm fan remains unavailable.
- [ ] If showing routines/history, confirm NTP is synchronized and test persistence/reboot beforehand. Review previously saved LED/LCD routines so they do not unexpectedly run during the report.

Keep the motor, relay, INA219, reed sensor and buzzer outside the physical demonstration. Relay clicks from the earlier individual test do not establish fan motor operation. To re-enable the future relay assembly, verify wiring/polarity first, change `HOMEEASE_ENABLE_FAN_RELAY` to `1`, recompile and upload, then perform separate motor tests.

Software verification results are recorded in [verification notes](verification.md). Successful compilation and automated app tests do not establish physical integration.
