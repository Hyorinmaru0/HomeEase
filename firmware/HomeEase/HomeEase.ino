#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <ArduinoJson.h>
#include <time.h>
#include <memory>
#include "HomeEaseConfig.h"

struct Device {
  const char *id, *name, *room, *kind;
  int pin;
  bool activeLow;
  double rated;
  bool on = false;
  double total = 0, startKwh = 0;
  time_t onSince = 0;
  String priority = "medium";
};
Device devices[] = {
  {"living-light", "Living Room Light", "living", "light", LIVING_LIGHT_PIN, false, LIVING_RATED_WATTS},
  {"bedroom-light", "Bedroom Light", "bedroom", "light", BEDROOM_LIGHT_PIN, false, BEDROOM_RATED_WATTS},
  {"fan", "Fan", "bedroom", "fan", FAN_RELAY_PIN, FAN_RELAY_ACTIVE_LOW, FAN_RATED_WATTS},
  {"mini-tv", "Mini TV (LCD 16\xc3\x97" "2)", "living", "tv", -1, false, TV_RATED_WATTS}
};
WebServer server(80);
Preferences prefs;
LiquidCrystal_I2C lcd(LCD_ADDRESS, 16, 2);
JsonDocument schedules, history;
bool storageReady = false, storageHealthy = true, lcdOnline = false;
bool pirReady = false, motion = false, pirSeen = false, bedroomOccupied = false;
bool distanceValid = false;
float distanceCm = 0;
uint32_t lastMotion = 0, lastSensor = 0, lastEnergy = 0, lastCheckpoint = 0;
uint32_t lastLcdProbe = 0;
String lastScheduleMinute;
uint32_t bootId;

bool clockReady() { return time(nullptr) > 1700000000; }
String isoTime(time_t stamp) {
  if (!stamp) return "";
  struct tm utc;
  gmtime_r(&stamp, &utc);
  char out[25];
  strftime(out, sizeof(out), "%Y-%m-%dT%H:%M:%SZ", &utc);
  return String(out);
}
int deviceIndex(const String &id) {
  for (int i = 0; i < 4; ++i) if (id == devices[i].id) return i;
  return -1;
}
bool deviceEnabled(int index) {
  return index >= 0 && index < 4 && (index != 2 || FAN_RELAY_ENABLED);
}
bool probeLcd() {
  Wire.beginTransmission(LCD_ADDRESS);
  return Wire.endTransmission() == 0;
}
void drawTv(bool on) {
  lcd.clear();
  if (on) {
    lcd.display();
    lcd.backlight();
    lcd.setCursor(0, 0); lcd.print("HomeEase TV");
    lcd.setCursor(0, 1); lcd.print("TV ON");
  } else {
    lcd.noDisplay();
    lcd.noBacklight();
  }
}
void integrateEnergy() {
  const uint32_t stamp = millis();
  const double hours = (uint32_t)(stamp - lastEnergy) / 3600000.0;
  lastEnergy = stamp;
  for (Device &d : devices) {
    if (!d.on || (d.pin == FAN_RELAY_PIN && !FAN_RELAY_ENABLED)) continue;
    d.total += d.rated * hours / 1000.0;
    // Never invent wall-clock timestamps before NTP has synchronized.
    if (!d.onSince && clockReady()) {
      d.onSince = time(nullptr);
      d.startKwh = d.total;
    }
  }
}
void recordSession(Device &d, time_t end) {
  if (!d.onSince || end < d.onSince) return;
  JsonArray records = history.as<JsonArray>();
  if (records.size() >= MAX_HISTORY) records.remove(0);
  JsonObject r = records.add<JsonObject>();
  r["id"] = String(bootId) + "-" + d.id + "-" + String((long)end) + "-" + String(millis());
  r["applianceId"] = d.id; r["applianceName"] = d.name;
  r["onTime"] = isoTime(d.onSince); r["offTime"] = isoTime(end);
  r["energyKwh"] = max(0.0, d.total - d.startKwh);
  r["rate"] = ELECTRICITY_RATE;
}
bool checkpoint() {
  if (!storageReady) return storageHealthy = false;
  JsonDocument data;
  data["schedules"] = schedules.as<JsonArray>();
  data["history"] = history.as<JsonArray>();
  data["lastScheduleMinute"] = lastScheduleMinute;
  data["checkpointTime"] = clockReady() ? time(nullptr) : 0;
  JsonArray saved = data["devices"].to<JsonArray>();
  for (Device &d : devices) {
    JsonObject o = saved.add<JsonObject>();
    o["total"] = d.total; o["startKwh"] = d.startKwh;
    o["onSince"] = d.onSince; o["priority"] = d.priority;
  }
  String payload;
  // NVS strings are limited to 4000 bytes. Use a bounded blob and trim only
  // the oldest history entries to leave room for atomic NVS replacement.
  while (measureJson(data) > MAX_CHECKPOINT_BYTES && history.size() > 0) {
    history.as<JsonArray>().remove(0);
    data["history"] = history.as<JsonArray>();
  }
  serializeJson(data, payload);
  storageHealthy = payload.length() <= MAX_CHECKPOINT_BYTES &&
      prefs.putBytes("state", payload.c_str(), payload.length()) == payload.length();
  lastCheckpoint = millis();
  return storageHealthy;
}
void restore() {
  schedules.to<JsonArray>(); history.to<JsonArray>();
  storageReady = prefs.begin("homeease", false);
  if (!storageReady) { storageHealthy = false; return; }
  const size_t size = prefs.getBytesLength("state");
  if (!size) return;
  if (size > MAX_CHECKPOINT_BYTES) { storageHealthy = false; return; }
  std::unique_ptr<char[]> saved(new char[size + 1]);
  if (prefs.getBytes("state", saved.get(), size) != size) { storageHealthy = false; return; }
  saved[size] = '\0';
  JsonDocument data;
  if (deserializeJson(data, saved.get(), size)) { storageHealthy = false; return; }
  if (data["schedules"].is<JsonArray>()) schedules.set(data["schedules"]);
  if (data["history"].is<JsonArray>()) history.set(data["history"]);
  lastScheduleMinute = data["lastScheduleMinute"].as<String>();
  for (int i = 0; i < 4; ++i) {
    Device &d = devices[i];
    JsonObject o = data["devices"][i];
    d.total = o["total"] | 0.0;
    d.startKwh = o["startKwh"] | d.total;
    d.onSince = o["onSince"] | (time_t)0;
    d.priority = o["priority"] | "medium";
    // Boot always starts OFF; only account through the last durable checkpoint.
    recordSession(d, data["checkpointTime"] | (time_t)0);
    d.onSince = 0; d.startKwh = d.total;
  }
  checkpoint();
}
bool setPower(int index, bool on) {
  if (!deviceEnabled(index)) return false;
  if (index == 3) {
    lcdOnline = probeLcd();
    if (!lcdOnline) return false;
  }
  integrateEnergy();
  Device &d = devices[index];
  if (index == 3) drawTv(on);
  else digitalWrite(d.pin, on != d.activeLow ? HIGH : LOW);
  if (on == d.on) return storageHealthy || checkpoint(); // Retry storage, not the session.
  if (on) {
    d.onSince = clockReady() ? time(nullptr) : 0;
    d.startKwh = d.total;
  } else {
    recordSession(d, clockReady() ? time(nullptr) : 0);
    d.onSince = 0;
  }
  d.on = on;
  return checkpoint();
}
void sampleSensors() {
  const uint32_t stamp = millis();
  pirReady = pirReady || stamp >= PIR_WARMUP_MS;
  motion = pirReady && digitalRead(PIR_PIN) == HIGH;
  if (motion) { lastMotion = stamp; pirSeen = true; }
  bedroomOccupied = pirReady && pirSeen &&
      (motion || (uint32_t)(stamp - lastMotion) < PIR_VACANCY_DELAY_MS);
  if ((uint32_t)(stamp - lastSensor) < SENSOR_INTERVAL_MS) return;
  lastSensor = stamp;
  digitalWrite(ULTRASONIC_TRIG_PIN, LOW); delayMicroseconds(2);
  digitalWrite(ULTRASONIC_TRIG_PIN, HIGH); delayMicroseconds(10);
  digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
  const unsigned long duration = pulseIn(ULTRASONIC_ECHO_PIN, HIGH, ECHO_TIMEOUT_US);
  distanceCm = duration * 0.0343f / 2.0f;
  distanceValid = duration > 0 && distanceCm >= 2 && distanceCm <= 400;
}
void runSchedules() {
  if (!clockReady()) return;
  time_t stamp = time(nullptr);
  struct tm local;
  localtime_r(&stamp, &local);
  char minute[24]; strftime(minute, sizeof(minute), "%Y-%m-%d-%H-%M", &local);
  if (lastScheduleMinute == minute) return;
  lastScheduleMinute = minute;
  const int weekday = local.tm_wday == 0 ? 7 : local.tm_wday;
  for (JsonObject s : schedules.as<JsonArray>()) {
    if (!s["enabled"].as<bool>() || s["minuteOfDay"] != local.tm_hour * 60 + local.tm_min) continue;
    bool today = false;
    for (int day : s["days"].as<JsonArray>()) if (day == weekday) today = true;
    const int index = deviceIndex(s["applianceId"].as<String>());
    if (today && deviceEnabled(index)) setPower(index, s["turnOn"].as<bool>());
  }
}
void reply(int code, const String &body = "{}") {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, PUT, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.sendHeader("Cache-Control", "no-store");
  server.send(code, "application/json", body);
}
void sendState() {
  integrateEnergy();
  JsonDocument state;
  state["energySource"] = "estimated";
  state["clockSynced"] = clockReady();
  state["storageHealthy"] = storageHealthy;
  state["firmware"] = "homeease-1.1";
  state["fanRelayEnabled"] = FAN_RELAY_ENABLED;
  state["pendingHardware"] = FAN_RELAY_ENABLED
      ? "DC fan motor, INA219, door sensor, buzzer, LCD electrical compatibility"
      : "Relay and DC fan not connected (disabled for presentation); INA219, door sensor, buzzer; LCD electrical verification";
  JsonArray list = state["devices"].to<JsonArray>();
  for (int i = 0; i < 4; ++i) {
    Device &d = devices[i];
    JsonObject o = list.add<JsonObject>();
    o["id"] = d.id; o["name"] = d.name; o["roomId"] = d.room; o["kind"] = d.kind;
    o["ratedWatts"] = d.rated; o["isOn"] = deviceEnabled(i) && d.on;
    o["online"] = deviceEnabled(i) && (i != 3 || lcdOnline);
    if (i == 2) o["hardwareNote"] = FAN_RELAY_ENABLED
        ? "Relay control; fan motor verification pending"
        : "Not connected; relay and fan disabled for presentation";
    if (i == 3) o["hardwareNote"] = "LCD electrical verification pending";
    o["watts"] = deviceEnabled(i) && d.on ? d.rated : 0;
    o["totalKwh"] = d.total; o["sessionStartKwh"] = d.startKwh;
    o["priority"] = d.priority;
    if (d.onSince) o["onSince"] = isoTime(d.onSince); else o["onSince"] = nullptr;
  }
  JsonArray rooms = state["rooms"].to<JsonArray>();
  JsonObject living = rooms.add<JsonObject>();
  living["id"] = "living"; living["name"] = "Living room";
  living["occupied"] = distanceValid && distanceCm < OCCUPIED_DISTANCE_CM;
  living["sensor"] = "HC-SR04"; living["sensorOnline"] = distanceValid;
  if (distanceValid) living["distanceCm"] = distanceCm; else living["distanceCm"] = nullptr;
  JsonObject bedroom = rooms.add<JsonObject>();
  bedroom["id"] = "bedroom"; bedroom["name"] = "Bedroom";
  bedroom["occupied"] = bedroomOccupied;
  bedroom["sensor"] = "PIR"; bedroom["sensorOnline"] = pirReady;
  if (pirReady) bedroom["motion"] = motion; else bedroom["motion"] = nullptr;
  state["history"] = history.as<JsonArray>();
  state["schedules"] = schedules.as<JsonArray>();
  String payload; serializeJson(state, payload); reply(200, payload);
}
bool validSchedules(JsonVariant list) {
  if (!list.is<JsonArray>() || list.size() > MAX_SCHEDULES) return false;
  for (size_t i = 0; i < list.size(); ++i) {
    JsonObject s = list[i];
    if (!s["id"].is<String>() || s["id"].as<String>().isEmpty() ||
        s["id"].as<String>().length() > 80 || !s["name"].is<String>() ||
        s["name"].as<String>().length() > 100 ||
        !s["applianceId"].is<String>() || deviceIndex(s["applianceId"].as<String>()) < 0 ||
        !s["minuteOfDay"].is<int>() || s["minuteOfDay"].as<int>() < 0 ||
        s["minuteOfDay"].as<int>() >= 1440 || !s["turnOn"].is<bool>() ||
        !s["enabled"].is<bool>() || !s["days"].is<JsonArray>() ||
        s["days"].size() == 0 || s["days"].size() > 7) return false;
    for (JsonVariant day : s["days"].as<JsonArray>())
      if (!day.is<int>() || day.as<int>() < 1 || day.as<int>() > 7) return false;
    for (size_t j = 0; j < i; ++j)
      if (list[j]["id"].as<String>() == s["id"].as<String>()) return false;
  }
  return true;
}
void routeRequest() {
  if (server.method() == HTTP_OPTIONS) { reply(204, ""); return; }
  if (server.uri() == "/api/state" && server.method() == HTTP_GET) { sendState(); return; }
  if (server.method() != HTTP_PUT) { reply(404, "{\"error\":\"Unknown route\"}"); return; }
  const String body = server.arg("plain");
  if (body.length() > 8192) { reply(413); return; }
  JsonDocument request;
  if (deserializeJson(request, body) || !request.is<JsonObject>()) { reply(400); return; }
  if (server.uri() == "/api/schedules") {
    if (!validSchedules(request["schedules"])) { reply(400); return; }
    if (measureJson(request["schedules"]) > MAX_SCHEDULE_BYTES) { reply(413); return; }
    JsonDocument previous; previous.set(schedules);
    JsonDocument previousHistory; previousHistory.set(history);
    schedules.set(request["schedules"]);
    if (!checkpoint()) { schedules.set(previous); history.set(previousHistory); reply(503); return; }
    reply(200); return;
  }
  for (int i = 0; i < 4; ++i) {
    const String prefix = String("/api/devices/") + devices[i].id;
    if (server.uri() == prefix + "/power") {
      if (!request["isOn"].is<bool>()) { reply(400); return; }
      if (!deviceEnabled(i)) {
        reply(503, "{\"error\":\"Fan relay disabled; hardware not connected\"}"); return;
      }
      reply(setPower(i, request["isOn"].as<bool>()) ? 200 : 503); return;
    }
    if (server.uri() == prefix + "/priority") {
      const String value = request["priority"].as<String>();
      if (value != "high" && value != "medium" && value != "low") { reply(400); return; }
      const String previous = devices[i].priority;
      devices[i].priority = value;
      if (!checkpoint()) { devices[i].priority = previous; reply(503); return; }
      reply(200); return;
    }
  }
  reply(404, "{\"error\":\"Unknown device or route\"}");
}
void setup() {
  Serial.begin(115200);
  bootId = esp_random();
  for (Device &d : devices) {
    if (d.pin < 0 || (d.pin == FAN_RELAY_PIN && !FAN_RELAY_ENABLED)) continue;
    digitalWrite(d.pin, d.activeLow ? HIGH : LOW); // Establish OFF before output mode.
    pinMode(d.pin, OUTPUT);
  }
  pinMode(ULTRASONIC_TRIG_PIN, OUTPUT); digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
  pinMode(ULTRASONIC_ECHO_PIN, INPUT);
  pinMode(PIR_PIN, INPUT_PULLDOWN);
  Wire.begin(LCD_SDA_PIN, LCD_SCL_PIN);
  Wire.setTimeOut(50);
  lcdOnline = probeLcd();
  if (lcdOnline) { lcd.init(); drawTv(false); }
  restore();
  lastEnergy = millis();
  // The core owns reconnection. Calling reconnect() on a timer can collide
  // with an association already in progress ("sta is connecting").
  WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t info) {
    switch (event) {
      case ARDUINO_EVENT_WIFI_STA_CONNECTED:
        Serial.println("WiFi: associated with hotspot; waiting for IP.");
        break;
      case ARDUINO_EVENT_WIFI_STA_GOT_IP:
        Serial.print("WiFi: IP acquired: ");
        Serial.println(IPAddress(info.got_ip.ip_info.ip.addr));
        break;
      case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
        Serial.printf("WiFi: disconnected, reason=%u\n",
                      info.wifi_sta_disconnected.reason);
        break;
      case ARDUINO_EVENT_WIFI_STA_LOST_IP:
        Serial.println("WiFi: lost IP address.");
        break;
      default: break;
    }
  });
  WiFi.mode(WIFI_STA); WiFi.setAutoReconnect(true);
  WiFi.begin(HOMEEASE_WIFI_SSID, HOMEEASE_WIFI_PASSWORD);
  configTime(TIMEZONE_OFFSET_SECONDS, 0, "pool.ntp.org", "time.nist.gov");
  server.onNotFound(routeRequest);
  server.begin();
  Serial.println("HomeEase: outputs OFF. Waiting for Wi-Fi; sensors continue locally.");
  Serial.printf("Firmware: homeease-1.1; fan relay %s\n",
                FAN_RELAY_ENABLED ? "ENABLED" : "DISABLED (GPIO32 untouched)");
}
void loop() {
  static bool wasConnected = false;
  const bool connected = WiFi.status() == WL_CONNECTED;
  if (connected && !wasConnected) {
    Serial.print("HomeEase address: http://"); Serial.println(WiFi.localIP());
  }
  wasConnected = connected;
  server.handleClient();
  sampleSensors();
  integrateEnergy();
  runSchedules();
  if ((uint32_t)(millis() - lastLcdProbe) >= 2000) {
    lastLcdProbe = millis();
    const bool present = probeLcd();
    if (present && !lcdOnline) { lcd.init(); drawTv(devices[3].on); }
    lcdOnline = present;
  }
  if ((uint32_t)(millis() - lastCheckpoint) >= 60000) checkpoint();
  delay(2);
}
