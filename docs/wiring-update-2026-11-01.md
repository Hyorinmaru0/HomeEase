# HomeEase GPIO update ? 1 November 2026

The configured firmware is `homeease-2.2`. The user selected GPIO14 for the Mini Fridge LED to free GPIO17 for INA219 SCL.

| Component | Connection |
| --- | --- |
| INA219 SDA | GPIO16 |
| INA219 SCL | GPIO17 |
| Mini Fridge LED | GPIO14 through its existing series resistor |
| Living Room AC LED | GPIO33 through its existing series resistor |
| LCD SDA / SCL | GPIO21 / GPIO22, unchanged |
| Living Room Light / Bedroom Light | GPIO25 / GPIO26, unchanged |
| Smart Wall Lamp / Bedroom AC | GPIO23 / GPIO19, unchanged |
| PIR | GPIO27, unchanged |
| Ultrasonic TRIG / ECHO | GPIO5 / GPIO18 with existing divider, unchanged |
| Former fan relay | GPIO32 remains excluded |

The LCD uses `Wire` (I?C controller 0). INA219 has its own `Wire1` (controller 1), initialized at 100 kHz on GPIO16/17. All 13 assigned pins are included in the existing compile-time duplicate-pin/retired-GPIO check. GPIO16/17 are no longer LED output pins.

This change configures the INA219 communication pins and initializes its bus only. It does not read, calibrate or verify the INA219 sensor. Successful bus initialization does not prove the sensor is connected. Energy remains explicitly estimated from configured appliance ratings and observed ON time; no measured voltage, current, power or kWh is claimed.

## Output polarity correction

The user confirmed that the Living Room AC and bedroom Smart Wall Lamp physically turn ON when the app requests OFF. These two outputs are configured as active-low in firmware 2.2:

| Output | GPIO | App ON | App OFF / firmware startup |
| --- | --- | --- | --- |
| Living Room AC | 33 | LOW | HIGH |
| Smart Wall Lamp | 23 | LOW | HIGH |
| Other LED outputs | Existing pins | HIGH | LOW |

`LIVING_AC_ACTIVE_LOW` and `WALL_LAMP_ACTIVE_LOW` are both `true` in `HomeEaseConfig.h`. Startup preloads each output's correct OFF level before enabling the output, and all power commands use the same polarity helper. The API's `isOn` remains the logical app state. The phone switches do not need inversion or an APK update.

Keep the model's existing active-low wiring for these two outputs. When recreating a bare-LED active-low circuit, a 3.3V series-resistor/LED circuit can have its LED cathode connected to the GPIO so LOW sinks current and turns it ON. This differs from an active-high LED with its cathode connected to GND; select the matching configuration if wiring changes.

## Apply to the board

Disconnect power before moving the Mini Fridge LED from GPIO17 to GPIO14 and the Living Room AC LED from GPIO16 to GPIO33. Keep each LED's existing series resistor. Keep INA219 SDA on GPIO16 and SCL on GPIO17; the LCD stays on its separate GPIO21/22 wiring.

Open `firmware/HomeEase/HomeEase.ino` in Arduino IDE, select ESP32 Dev Module for the existing WROOM-32 and the board's current port, then Verify and Upload when the wiring is ready. Keep the existing Wi-Fi secrets unchanged. This coding session does not flash the board.

At 115200 baud, expect firmware version `homeease-2.2` and an INA219 I?C-bus initialization message. A failed bus initialization is reported separately. After Wi-Fi connects, `/api/state` should report `firmware: homeease-2.1` and `energySource: estimated`. Test the fridge and Living Room AC individually and verify that neither LED uses GPIO16/17 now.

The phone app still addresses appliances by their stable IDs (`mini-fridge`, `living-ac`). GPIO selection happens entirely inside the ESP32 firmware, so the current local-account APK can be used without rebuilding it.

## Initial pin-update verification (firmware 2.1)

- `arduino-cli compile --fqbn esp32:esp32:esp32 --libraries C:\Users\Ahron\Documents\Arduino\libraries --build-path build/firmware-pins-20261101 firmware/HomeEase`: passed.
- Program storage: 1,008,765 bytes (76%); static RAM: 50,828 bytes (15%).
- Compile-time duplicate-pin assertion and independent 13-pin audit: passed; GPIO32 excluded.
- Compiled header matches the current source configuration after excluding Arduino's generated line directive.
- Output: `build/firmware-pins-20261101/HomeEase.ino.bin`.
- Existing LiquidCrystal I2C AVR-architecture metadata warning remains; compilation succeeded for the ESP32 target.
- No mobile code changed, so no APK rebuild was needed. No board upload was performed. Physical wiring, bus signals and INA219 readings are not claimed tested.

## Polarity-fix verification (firmware 2.2)

- ESP32 Dev Module compilation: passed. Program storage: 1,008,785 bytes (76%); static RAM: 50,828 bytes (15%).
- Compile-time ON/OFF truth-table checks pass for both polarities; the startup and command paths use that same helper.
- Duplicate-pin/retired-pin assertion: passed.
- The compiled header matches the source, and the binary contains firmware version `homeease-2.2`.
- Output: `build/firmware-pins-20261101/HomeEase.ino.bin`. The existing LCD library architecture metadata warning remains.
- No board upload was performed and no APK rebuild is needed.

After upload, test each app switch against its physical LED, then power-cycle the board to check that both outputs start OFF after firmware initialization. Physical verification is still required.
