# HomeEase ESP32 REST API

Implemented by `firmware/HomeEase/HomeEase.ino`. The app starts in demo mode; all HTTP traffic lives in `lib/services/esp32_service.dart`, behind `Esp32Gateway`. See [hardware setup](hardware-integration.md) before upload. Physical integration remains pending.

## Connect

Presentation firmware keeps `fan` in the device list but sends `online: false`, `isOn: false`, `watts: 0` and a not-connected `hardwareNote` when `HOMEEASE_ENABLE_FAN_RELAY=0` (default). Fan power PUTs return 503; stored fan routines are skipped, and GPIO32 is untouched. The other device IDs and endpoints are unchanged. Demo controls remain local and unaffected.

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

All four arrays are required; use empty arrays when appropriate. IDs are stable and unique. Device `roomId` must reference a room. Use `light`, `fan`, or `tv` for `kind`, and `high`, `medium`, or `low` for priority. Watts and energy must be finite and non-negative. History is a snapshot, not an incremental batch. The example illustrates one device; firmware returns `living-light`, `bedroom-light`, `fan`, `mini-tv` and both rooms.

### Additional telemetry

`energySource` is `estimated` in the included firmware; no INA219 is enabled. Missing values default to estimated for legacy snapshots; future meter firmware can explicitly send `measured`. `clockSynced` and `storageHealthy` are booleans; `pendingHardware` is a string shown in Settings. Optional appliance `hardwareNote` is shown in the existing card/details.

Sensors use the existing room objects:

```json
[
  {"id":"living","name":"Living room","occupied":true,
   "sensor":"HC-SR04","sensorOnline":true,"distanceCm":42.5},
  {"id":"bedroom","name":"Bedroom","occupied":true,
   "sensor":"PIR","sensorOnline":true,"motion":false}
]
```

False motion with true occupancy is valid during the 7-second hold. Ultrasonic timeout/out-of-range or PIR warm-up sends `sensorOnline: false` and null raw readings. These optional fields preserve compatibility with old cached room objects. Unavailable sensors never trigger vacant-room alerts.

Firmware accepts up to 16 schedules (3,500 serialized bytes) and retains up to 32 completed sessions. A 6,000-byte checkpoint cap trims the oldest history if needed. Invalid JSON/values return 400, oversized bodies/schedule lists 413, unknown IDs/routes 404, LCD/persistence failures 503. OPTIONS supports CORS preflight. Schedule validation occurs before replacement.

`totalKwh` is a cumulative energy estimate in this firmware. `sessionStartKwh` captures it at switch-on. Their difference gives active-session energy. Counters are checkpointed and restored; see the hardware guide for power-loss limits. Send `onSince: null` when off or awaiting clock sync. Times use ISO 8601 UTC; NTP synchronizes the board. `days` uses Monday=1 through Sunday=7; `minuteOfDay` is 0–1439 in the configured local timezone (default UTC+08:00).

Firmware should maintain completed sessions independently of the phone, including ON/OFF timestamps, energy, and the applicable tariff. The app's rate setting calculates current cost estimates locally; it is not sent to firmware. When recording real sessions, configure the same rate on the firmware or extend the contract to synchronize it. History keeps its recorded rate when the app's estimate rate changes.

## Ownership

- **Firmware:** sensor readings, relay state, meter readings, persistent schedules, schedule execution, completed usage records.
- **App:** UI, local tariff estimates, alert preferences/thresholds, cached telemetry, in-app alerts, priority editing.
- **Demo mode:** simulated occupancy and relay controls; simulated watt-hours accumulated while running. Demo schedules execute only in their matching minute while the app is open. Missed schedules are not replayed.

Load priorities are metadata for reviewing and managing consumption. This app does not automatically shed loads. Alerts are in-app, evaluated while running; push notifications and background monitoring are not included.

## Platforms and deployment

Android declares Internet and local-network permissions and permits HTTP for ESP32 development. The Android 17 permission prompt is handled before the first LAN request. On iOS, the local-network usage description is supplied; allow it in system settings if previously denied. Firmware supplies CORS headers, but browser local-network and HTTPS mixed-content restrictions still apply. Use Android for the initial physical integration check; iOS builds need macOS/Xcode.

The starter contract uses a trusted local development network without authentication. Add an authenticated transport and device provisioning when preparing a deployed installation. Replace or extend `Esp32Gateway` without changing widgets if you later choose MQTT or Bluetooth.

References: [Flutter networking](https://docs.flutter.dev/cookbook/networking/fetch-data), [Android LAN permission](https://docs.flutter.dev/platform-integration/android/local-network-permission).
