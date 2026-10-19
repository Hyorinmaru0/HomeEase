# HomeEase ESP32 integration

The existing Flutter screens, navigation and modules are retained. Mini TV is the only new appliance. ID `mini-tv` uses the same switches, details, room filters, routines and history as the original three appliances. Old demo saves gain it once without resetting their data.

## Connect the existing app

**October 15 presentation:** relay and fan are disconnected. The default `HOMEEASE_ENABLE_FAN_RELAY=0` leaves GPIO32 untouched at startup and during manual/scheduled commands. Fan remains in the app as **Unavailable** in Live Mode; Demo Mode is unchanged. Follow the [presentation upload and test plan](progress-report-2026-10-15.md).

1. Open `firmware/HomeEase/HomeEase.ino` in Arduino IDE. Select **ESP32 Dev Module** for your ESP32-WROOM-32. Your reported port is **COM3**; confirm it before upload.
2. Install **ArduinoJson 7.4.2** and **LiquidCrystal I2C 1.1.2** (Frank de Brabander / Marco Schwartz). The latter is the library from your individual LCD test. The installed ESP32 core is **3.3.12**.
3. Copy `secrets.example.h` to `secrets.h` beside the sketch and enter Wi-Fi credentials. This local file is Git-ignored. No credentials are supplied.
4. Review `HomeEaseConfig.h` and the electrical checks below. Leave the fan flag disabled for the presentation. `FAN_RELAY_ACTIVE_LOW` applies only when the future relay is enabled.
5. After the physical checks, upload and open Serial Monitor at **115200 baud**. Firmware prints `HomeEase address: http://...` after joining Wi-Fi.
6. Put the phone on the same LAN. In the existing Settings screen, enter the printed base URL, turn Demo mode off and save. Allow local-network access if prompted.

The app polls every five seconds and immediately refreshes after accepted writes. Demo mode remains the default. Firmware has not been flashed or physically validated by this coding session. Android is the preferred initial hardware target; CORS is implemented, but browser HTTPS/mixed-content and local-network policies can still block an HTTP board.

After installing the libraries, the CLI build command is `arduino-cli compile --fqbn esp32:esp32:esp32 firmware/HomeEase`. The presentation firmware compiled against ESP32 core 3.3.12, ArduinoJson 7.4.2 and the existing LiquidCrystal I2C 1.1.2 library: 1,006,245 bytes flash (76%) and 50,604 bytes static RAM (15%). LiquidCrystal I2C's metadata declares AVR support and emits a compatibility warning; compilation succeeded for ESP32, while runtime operation remains a physical check.

## User-tested wiring

| Component | GPIO | Behavior |
| --- | --- | --- |
| Living Room LED, red | 25 | Existing `living-light`; HIGH = on |
| Bedroom LED, green | 26 | Existing `bedroom-light`; HIGH = on |
| Fan relay, channel 1 | 32 reserved | Not connected; disabled by default; no GPIO32 access |
| HC-SR04 TRIG / ECHO | 5 / 18 | Living room proximity occupancy |
| HC-SR501 PIR OUT | 27 | Bedroom motion/occupancy |
| LCD SDA / SCL | 21 / 22 | I2C address `0x27` |
| Planned magnetic door sensor | 33 | Reserved; not enabled |

Mini TV ON writes `HomeEase TV` on row 1 and `TV ON` on row 2, with display/backlight enabled. OFF clears the characters and disables display/backlight. The LCD remains electrically powered. A missing I2C acknowledgement reports Mini TV offline and rejects commands; acknowledgement cannot verify visible characters or voltage compatibility.

## Sensors and estimates

- HC-SR04 is sampled about every 250 ms with a 25 ms echo timeout. Valid range is 2–400 cm. `OCCUPIED_DISTANCE_CM` defaults to 100 cm and must be calibrated to placement. This is proximity detection, not a people counter. Timeout/out-of-range reports **Sensor unavailable**, not vacant.
- PIR has a configurable 60-second warm-up. Occupancy stays true while OUT is HIGH and for **7 seconds after the last observed HIGH**. The sensor's own hold-time setting adds to this delay. Raw motion and held occupancy are displayed separately. The signal alone cannot reliably diagnose an unplugged PIR or prove vacancy.
- Unavailable sensors do not trigger Smart Exit alerts. Network failure preserves a **Last known** snapshot and disables controls until reconnect succeeds.
- No INA219 data is fabricated. Firmware declares `energySource: estimated`; watts use configurable ratings multiplied by commanded ON duration. Existing 12 W / 9 W / 45 W demo ratings are retained as placeholders, with 1 W for LCD. These are not measured LED/motor/LCD loads; set appropriate ratings before using estimates.
- Match firmware `ELECTRICITY_RATE` to the app's tariff. The app's rate setting is local; completed board history keeps its recorded rate.
- **Relay/fan are disconnected; motor operation, INA219, magnetic door sensor, buzzer and LCD electrical verification remain pending.** Settings identifies these; the fan card shows unavailable with a not-connected explanation. No additional modules or unfinished appliances were added.

## Electrical checks still required

Individual LED/sensor/LCD tests and relay clicks were reported by the user. The combined circuit still requires these physical checks:

1. **LCD backpack:** inspect the IC marking and trace/measure SDA/SCL pull-ups. Do not apply 5 V pull-ups to ESP32 GPIO. For a 5 V backpack, use an appropriate bidirectional I2C level shifter with 3.3 V pull-ups on the ESP32 side. Moving pull-ups to 3.3 V alone may not meet a 5 V PCF8574's HIGH threshold of 0.7 × VDD. Check the actual LCD's supply, contrast and backlight requirements. Address `0x27` cannot establish electrical compatibility. [NXP PCF8574 datasheet](https://www.nxp.com/docs/en/data-sheet/PCF8574_PCF8574A.pdf), [ESP32 electrical characteristics](https://documentation.espressif.com/esp32_datasheet_en.html).
2. **Ultrasonic:** retain ECHO → 1 kΩ → GPIO18 junction → 2 kΩ → GND. Nominal 5 V becomes about 3.33 V; confirm actual voltage and common ground. GPIO5 is a strapping pin, so verify cold boot with the sensor connected. [ESP32 boot configuration](https://documentation.espressif.com/esp32_datasheet_en.html).
3. **LEDs/relay/motor:** retain LED current-limiting resistors. Verify 3.3 V relay input compatibility, polarity and OFF behavior during reset before attaching the motor. Check contact ratings, motor supply, suppression and grounding for the actual module. Relay clicks do not establish motor operation.
4. **Combined assembly:** test supply stability during Wi-Fi transmission and relay/motor switching. Firmware initializes outputs OFF; external biasing must establish OFF during reset before firmware executes.

## Existing schedules, priorities and history

Priorities are metadata and never automatically shed loads. Firmware stores up to 16 routines (3,500 serialized bytes) and up to 32 completed sessions, priorities and cumulative estimates in NVS. A checkpoint is capped at 6,000 bytes; the oldest history entries are trimmed if necessary, so long routine lists reduce retained history. The app retains its existing larger local limits. Schedule validation is atomic before replacement.

Checkpoints use binary blobs because NVS strings have a 4,000-byte limit. The checkpoint cap leaves room for replacement on the standard ESP32 Dev Module NVS partition; storage exhaustion still returns an error and is shown in Settings. [Espressif NVS storage limits](https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32/api-reference/storage/nvs_flash.html).

Routines run on the ESP32 with the app closed once NTP synchronizes its clock. Timezone defaults to Asia/Manila, UTC+08:00. Missed routines are not replayed. Without time sync, manual controls/sensors work, but routines and timestamped history wait; Settings indicates that condition.

Outputs start OFF after reboot. State checkpoints occur every minute and on changes. An interrupted session closes at the last durable checkpoint, rather than an invented shutdown time; sudden power loss can lose roughly one minute of estimates. Energy before initial NTP sync has no fabricated timestamped history. Firmware storage failure is shown in Settings.

Demo and live snapshots remain separate. Demo switches never contact hardware. Live commands wait for acknowledgement and refresh. GPIO state is commanded state, not independent feedback proving that the connected load physically operated.

## Physical acceptance checklist

| Test | Expected result | Status |
| --- | --- | --- |
| Both lights individually | Only corresponding LED changes | Combined test pending |
| Fan exclusion | Unavailable live; GPIO32 untouched by startup, commands or routines | Software configured; physical exclusion check pending |
| Mini TV repeated ON/OFF | Exact two lines / blank screen | Combined/electrical tests pending |
| HC-SR04 near/far/no echo | Correct cm, occupancy threshold, unavailable on timeout | Calibration pending |
| PIR motion then clear | Occupied; vacant ≥7 s after OUT returns LOW | Combined timing test pending |
| Wi-Fi loss/reconnect | Stale labels, disabled controls, real-state recovery | Physical LAN test pending |
| Routine with app closed | One action at configured time after NTP sync | Board runtime test pending |
| Restart | Outputs OFF; history/routines/priorities restored | Board NVS test pending |
| INA219 / reed sensor / buzzer | Stay pending | Not enabled or claimed tested |

After upload, `http://<ESP32-IP>/api/state` is a read-only diagnostic. Power writes use `PUT /api/devices/<id>/power` with `{"isOn": true}` or `false`; see [API contract](esp32-api.md). This unauthenticated API is for the trusted development LAN; do not expose it through router port forwarding.
