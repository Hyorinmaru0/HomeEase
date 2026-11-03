# Appliance changes but HomeEase shows a confirmation error

The user reported that LEDs physically change while the app shows a generic Wi-Fi/state-confirmation error. That proves a command can reach the board, but does not show whether the command response or the following state read failed.

## App update 1.0.2

- Accepts successful command acknowledgments such as `OK`, JSON, or an empty body. It previously attempted to decode every response as JSON, including unused write-response bodies.
- Keeps strict JSON parsing and device-state validation for `/api/state`. A successful acknowledgment alone never proves a device changed.
- Retries one transient state-read failure without replaying the physical command.
- Separates HTTP errors, invalid device data, timeouts, connection errors and Android local-network permission failures.
- After a board-side HTTP command failure, refreshes actual output state without retrying the command. For example, an ESP32 may change a GPIO and then report HTTP 503 because saving to NVS failed. The app then shows the actual refreshed state along with the explicit save/device error.

## On-phone check

1. Keep Demo mode OFF. Use the full base address in Settings, for example `http://10.116.6.67`, then Reconnect.
2. On the same phone, open `http://10.116.6.67/api/state`. Report only `firmware` and `storageHealthy` to diagnose the board. If the page cannot open, reconnect the phone and board to the same LAN/hotspot and check the current board address.
3. Install the latest 1.0.2 APK, then test one output and read any specific error shown.
4. `HTTP 503` with `storageHealthy: false` points to a board save problem; Settings also shows a storage warning. Preserve the current records while investigating rather than erasing storage as a first step.
5. An invalid-device-data message needs a compatible HomeEase state response. A command-sent/state-confirmation message means the command was acknowledged but the follow-up state could not be verified. Use Reconnect before issuing additional commands based on stale state.

The computer's read-only GET to the user-provided board address timed out. The actual board response and cause have not been verified from this computer. Regression tests use an injected HTTP client to reproduce plain-text acknowledgment, transient read failure, malformed JSON and board save-error cases.

## Separate firmware upload status

The compiled firmware 2.2 fixes the active-low Living Room AC on GPIO33 and Smart Wall Lamp on GPIO23. The authorized COM3 upload did not write firmware: Serial Monitor initially held the port; after releasing it, esptool reported wrong boot mode. Manual BOOT/EN button assistance is still needed before retrying the upload. The existing board firmware version is not yet confirmed.
