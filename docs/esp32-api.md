# HomeEase ESP32 REST API

Implemented by `firmware/HomeEase/HomeEase.ino`. The app starts in demo mode; all HTTP traffic lives in `lib/services/esp32_service.dart`, behind `Esp32Gateway`. See [hardware setup](hardware-integration.md) before upload. Physical integration remains pending.

## Connect

Firmware `homeease-2.2` returns seven appliances: `living-light`, `bedroom-light`, `mini-tv`, `mini-fridge`, `living-ac`, `bedroom-wall-lamp`, `bedroom-ac`. See the [complete GPIO/wiring/migration guide](system-update-2026-10-31.md). The [1 November pin update](wiring-update-2026-11-01.md) assigns the fridge to GPIO14, Living Room AC to GPIO33, and INA219 bus to SDA16/SCL17. INA219 measurements are not yet included. GPIO32 is always untouched; the retired fan is absent from current telemetry and fan power PUTs return 503. Legacy responses containing a fan entry remain readable and the app filters it out. New devices missing from old firmware are shown unavailable, never simulated as live successes.

1. Connect the phone and ESP32 to the same Wi-Fi.
2. Configure and upload the included ESP32 firmware.
3. In Settings, enter the base URL, such as `http://192.168.1.100` (a port is allowed).
4. Turn Demo mode off and save. Allow local-network access if prompted.

The service appends `/api/…`, polls every 5 seconds while the app is active, and times requests out after 6 seconds. A failed command or refresh marks readings as stale and disables controls until a refresh succeeds. Device state is refreshed after each acknowledged write. PUT commands set an explicit value so retries do not toggle an appliance twice.

| Method | Endpoint | Request | Success |
| --- | --- | --- | --- |
| GET | `/api/state` | None | 200 JSON snapshot below |
| PUT | `/api/devices/{id}/power` | `{"isOn": true}` | 200 `{}` or 204 |
| PUT | `/api/devices/{id}/priority` | `{"priority": "high"}` | 200 `{}` or 204 |
| PUT | `/api/schedules` | `{"schedules": [...]}` | 200 `{}` or 204 |

Use `Content-Type: application/json`. Return a non-2xx status for rejected commands. Schedule writes replace the full list and should be validated and committed atomically. Unsupported device IDs must return 404. Never acknowledge a write before the firmware has accepted it.

Living Room AC (GPIO33) and Smart Wall Lamp (GPIO23) use active-low wiring in firmware 2.2. `isOn: true` drives these pins LOW; `isOn: false` and firmware startup drive them HIGH. Other LED outputs retain active-high wiring. API power values remain logical ON/OFF for every device.

### Command acknowledgment and confirmation

The mobile client accepts a successful 2xx command response with an empty, JSON or plain-text acknowledgment body. It then reads `/api/state`, which must return a valid JSON object with the documented arrays and fields. Power controls report success only when the refreshed device is online and reports the requested `isOn` value.

A failed state GET caused by a connection error or timeout is retried once. Physical PUT commands are never automatically replayed. Explicit HTTP errors and invalid state JSON are not retried as transient connection failures.

If a PUT returns an error, the client makes a read-only state refresh because the output might already have changed before a board-side save failure. It retains the explicit command error even if the refreshed state matches the requested output. HTTP failures, malformed state, timeouts and local-network permission failures have separate user messages.

## State schema

```json
{
  "devices": [
    {
      "id": "living-light",
      "name": "Living Room Light",
      "roomId": "living",
      "kind": "light",
      "ratedWatts": 12,
      "isOn": true,
      "online": true,
      "watts": 12,
      "totalKwh": 1.2084,
      "priority": "high",
      "onSince": "2026-09-28T10:00:00+08:00",
      "sessionStartKwh": 1.2
    }
  ],
  "rooms": [
    {"id": "living", "name": "Living room", "occupied": true}
  ],
  "history": [
    {
      "id": "session-0001",
      "applianceId": "living-light",
      "applianceName": "Living Room Light",
      "onTime": "2026-09-27T18:00:00+08:00",
      "offTime": "2026-09-27T20:00:00+08:00",
      "energyKwh": 0.024,
      "rate": 11.5
    }
  ],
  "schedules": [
    {
      "id": "morning",
      "applianceId": "living-light",
      "name": "A brighter morning",
      "minuteOfDay": 390,
      "turnOn": true,
      "days": [1, 2, 3, 4, 5],
      "enabled": true
    }
  ]
}
```

All four arrays are required; use empty arrays when appropriate. IDs are stable and unique. Device `roomId` must reference a room. Kinds are `light`, `tv`, `fridge`, `ac`, and `wall-lamp`; priority is `high`, `medium`, or `low`. Watts and energy must be finite and non-negative. The example illustrates one device; current firmware returns all seven and both rooms. `living-fridge`/`bedroom-lamp` are migrated to `mini-fridge`/`bedroom-wall-lamp` in old app caches, firmware routines and database preferences/settings.

### Additional telemetry

`energySource` is `estimated`, `stateSource` is `commanded`, and `energyNote` explains hypothetical wattage estimates. LED GPIO entries also include `gpio`. There is no physical electricity meter or independent LED-state sensor. `clockSynced` and `storageHealthy` are booleans. Optional appliance `hardwareNote` explains simulated fridge/AC operation. The app never treats fridge power as door position.

Sensors use the existing room objects:

```json
[
  {"id":"living","name":"Living room","occupied":true,
   "sensor":"HC-SR04","sensorOnline":true,"distanceCm":42.5},
  {"id":"bedroom","name":"Bedroom","occupied":true,
   "sensor":"PIR","sensorOnline":true,"motion":false}
]
```

Current PIR occupancy follows its motion signal after warm-up; older firmware may report a held occupancy value. Ultrasonic timeout/out-of-range or PIR warm-up sends `sensorOnline: false` and null raw readings. The proximity threshold remains 9 cm. These indications are not proof of human presence or departure. Optional sensor fields preserve old cached room objects; unavailable sensors never trigger vacant-room alerts.

Firmware accepts up to 16 schedules (3,500 serialized bytes) and retains up to 32 completed sessions. A 6,000-byte checkpoint cap trims the oldest history if needed. Invalid JSON/values return 400, oversized bodies/schedule lists 413, unknown IDs/routes 404, LCD/persistence failures 503. OPTIONS supports CORS preflight. Schedule validation occurs before replacement.

`totalKwh` is a cumulative energy estimate in this firmware. `sessionStartKwh` captures it at switch-on. Their difference gives active-session energy. Counters are checkpointed and restored; see the hardware guide for power-loss limits. Send `onSince: null` when off or awaiting clock sync. Times use ISO 8601 UTC; NTP synchronizes the board. `days` uses Monday=1 through Sunday=7; `minuteOfDay` is 0–1439 in the configured local timezone (default UTC+08:00).

Firmware should maintain completed sessions independently of the phone, including ON/OFF timestamps, energy, and the applicable tariff. The app's rate setting calculates current cost estimates locally; it is not sent to firmware. When recording real sessions, configure the same rate on the firmware or extend the contract to synchronize it. History keeps its recorded rate when the app's estimate rate changes.

## Ownership

- **Firmware:** sensor readings, commanded LED/LCD states, persistent schedules, schedule execution and bounded estimated usage records. Outputs start OFF; ID-based checkpoints preserve old TV totals safely.
- **App:** UI, local tariff estimates, alert preferences/thresholds, cached telemetry, in-app alerts, priority editing.
- **Demo mode:** explicitly simulated occupancy and appliance controls; hypothetical watt-hours accumulated while running. Demo schedules execute only in their matching minute while the app is open. Missed schedules are not replayed.

Load priorities are metadata for reviewing and managing consumption. This app does not automatically shed loads. Alerts are in-app, evaluated while running; push notifications and background monitoring are not included.

## Platforms and deployment

Android declares Internet and local-network permissions and permits HTTP for ESP32 development. The Android 17 permission prompt is handled before the first LAN request. On iOS, the local-network usage description is supplied; allow it in system settings if previously denied. Firmware supplies CORS headers, but browser local-network and HTTPS mixed-content restrictions still apply. Use Android for the initial physical integration check; iOS builds need macOS/Xcode.

The starter contract uses a trusted local development network without authentication. Add an authenticated transport and device provisioning when preparing a deployed installation. Replace or extend `Esp32Gateway` without changing widgets if you later choose MQTT or Bluetooth.

References: [Flutter networking](https://docs.flutter.dev/cookbook/networking/fetch-data), [Android LAN permission](https://docs.flutter.dev/platform-integration/android/local-network-permission).
