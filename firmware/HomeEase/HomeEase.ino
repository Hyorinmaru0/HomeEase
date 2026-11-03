#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <ArduinoJson.h>
#include <time.h>
#include <memory>
#include <driver/gpio.h>
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
  {"mini-tv", "Mini TV (LCD 16\xc3\x97" "2)", "living", "tv", -1, false, TV_RATED_WATTS},
  {"mini-fridge", "Mini Fridge", "living", "fridge", MINI_FRIDGE_PIN, false, FRIDGE_RATED_WATTS},
  {"living-ac", "Living Room AC", "living", "ac", LIVING_AC_PIN, LIVING_AC_ACTIVE_LOW, LIVING_AC_RATED_WATTS},
  {"bedroom-wall-lamp", "Smart Wall Lamp", "bedroom", "wall-lamp", WALL_LAMP_PIN, WALL_LAMP_ACTIVE_LOW, WALL_LAMP_RATED_WATTS},
  {"bedroom-ac", "Bedroom AC", "bedroom", "ac", BEDROOM_AC_PIN, false, BEDROOM_AC_RATED_WATTS}
};
constexpr size_t DEVICE_COUNT = sizeof(devices) / sizeof(devices[0]);
constexpr int TV_DEVICE_INDEX = 2;
static_assert(DEVICE_COUNT == 7, "Expected exactly seven appliances");
WebServer server(80);
Preferences prefs;
LiquidCrystal_I2C lcd(LCD_ADDRESS, 16, 2);
JsonDocument schedules, history;
bool storageReady = false, storageHealthy = true, lcdOnline = false;
bool pirReady = false, motion = false, bedroomOccupied = false;
bool distanceValid = false;
float distanceCm = 0;
uint32_t lastSensor = 0, lastEnergy = 0, lastCheckpoint = 0;
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
  for (size_t i = 0; i < DEVICE_COUNT; ++i) if (id == devices[i].id) return i;
  return -1;
}
bool deviceEnabled(int index) {
  return index >= 0 && index < (int)DEVICE_COUNT;
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
    if (!d.on) continue;
    d.total += d.rated * hours / 1000.0;

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
  data["schemaVersion"] = 2;
  data["schedules"] = schedules.as<JsonArray>();
  data["history"] = history.as<JsonArray>();
  data["lastScheduleMinute"] = lastScheduleMinute;
  data["checkpointTime"] = clockReady() ? time(nullptr) : 0;
  JsonArray saved = data["devices"].to<JsonArray>();
  for (Device &d : devices) {
    JsonObject o = saved.add<JsonObject>();
    o["id"] = d.id;
    o["total"] = d.total; o["startKwh"] = d.startKwh;
    o["onSince"] = d.onSince; o["priority"] = d.priority;
  }
  String payload;

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

  for (JsonDocument *document : {&schedules, &history}) {
    JsonArray list = document->as<JsonArray>();
    for (int i = (int)list.size() - 1; i >= 0; --i) {
      String id = list[i]["applianceId"].as<String>();
      if (id == "living-fridge") id = "mini-fridge";
      if (id == "bedroom-lamp") id = "bedroom-wall-lamp";
      if (deviceIndex(id) < 0) list.remove(i);
      else list[i]["applianceId"] = id;
    }
  }
  lastScheduleMinute = data["lastScheduleMinute"].as<String>();
  for (size_t i = 0; i < DEVICE_COUNT; ++i) {
    Device &d = devices[i];
    JsonObject o;
    if ((data["schemaVersion"] | 1) >= 2) {
      for (JsonObject candidate : data["devices"].as<JsonArray>())
        if (candidate["id"] == d.id) { o = candidate; break; }
    } else {

      const int legacy = i < 2 ? (int)i : i == TV_DEVICE_INDEX ? 3 : -1;
      if (legacy >= 0) o = data["devices"][legacy];
    }
    d.total = o["total"] | 0.0;
    d.startKwh = o["startKwh"] | d.total;
    d.onSince = o["onSince"] | (time_t)0;
    d.priority = o["priority"] | "medium";

    recordSession(d, data["checkpointTime"] | (time_t)0);
    d.onSince = 0; d.startKwh = d.total;
  }
  checkpoint();
}
bool setPower(int index, bool on) {
  if (!deviceEnabled(index)) return false;
  if (index == TV_DEVICE_INDEX) {
    lcdOnline = probeLcd();
    if (!lcdOnline) return false;
  }
  integrateEnergy();
  Device &d = devices[index];
  if (index == TV_DEVICE_INDEX) drawTv(on);
  else digitalWrite(d.pin, outputLevelForPower(on, d.activeLow));
  if (on == d.on) return storageHealthy || checkpoint();
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
  bedroomOccupied = motion;
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
  state["firmware"] = FIRMWARE_VERSION;
  state["fanRelayEnabled"] = false;
  state["stateSource"] = "commanded";
  state["energyNote"] = "Hypothetical appliance wattages, not LED-model electricity readings";
  JsonArray list = state["devices"].to<JsonArray>();
  for (size_t i = 0; i < DEVICE_COUNT; ++i) {
    Device &d = devices[i];
    JsonObject o = list.add<JsonObject>();
    o["id"] = d.id; o["name"] = d.name; o["roomId"] = d.room; o["kind"] = d.kind;
    o["ratedWatts"] = d.rated; o["isOn"] = deviceEnabled(i) && d.on;
    o["online"] = i != TV_DEVICE_INDEX || lcdOnline;
    if (d.pin >= 0) o["gpio"] = d.pin;
    if (i == 3) o["hardwareNote"] = "LED power indicator only; manual door, no door sensor; no refrigeration";
    if (i == 4 || i == 6) o["hardwareNote"] = "LED model only; no real cooling";
    o["watts"] = deviceEnabled(i) && d.on ? d.rated : 0;
    o["totalKwh"] = d.total; o["sessionStartKwh"] = d.startKwh;
    o["priority"] = d.priority;
    if (d.onSince) o["onSince"] = isoTime(d.onSince); else o["onSince"] = nullptr;
  }
  JsonArray rooms = state["rooms"].to<JsonArray>();
  JsonObject living = rooms.add<JsonObject>();
  living["id"] = "living"; living["name"] = "Living room";
  living["occupied"] = distanceValid && distanceCm <= OCCUPIED_DISTANCE_CM;
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
  if (server.uri() == "/api/devices/fan/power") {
    reply(503, "{\"error\":\"Fan retired; GPIO32 untouched\"}"); return;
  }
  for (size_t i = 0; i < DEVICE_COUNT; ++i) {
    const String prefix = String("/api/devices/") + devices[i].id;
    if (server.uri() == prefix + "/power") {
      if (!request["isOn"].is<bool>()) { reply(400); return; }
      if (!deviceEnabled(i)) {
        reply(503, "{\"error\":\"Device unavailable\"}"); return;
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
    if (d.pin < 0) continue;
    const uint8_t offLevel = outputLevelForPower(false, d.activeLow);
    gpio_set_level((gpio_num_t)d.pin, offLevel);
    pinMode(d.pin, OUTPUT);
    digitalWrite(d.pin, offLevel);
  }
  pinMode(ULTRASONIC_TRIG_PIN, OUTPUT); digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
  pinMode(ULTRASONIC_ECHO_PIN, INPUT);
  pinMode(PIR_PIN, INPUT_PULLDOWN);
  Wire.begin(LCD_SDA_PIN, LCD_SCL_PIN);
  Wire.setTimeOut(50);
  lcdOnline = probeLcd();
  if (lcdOnline) { lcd.init(); drawTv(false); }

  if (Wire1.begin(INA219_SDA_PIN, INA219_SCL_PIN, INA219_I2C_HZ)) {
    Wire1.setTimeOut(50);
    Serial.printf("INA219 I2C bus configured: SDA=%u, SCL=%u; measurements pending.\n",
                  INA219_SDA_PIN, INA219_SCL_PIN);
  } else {
    Serial.println("INA219 I2C bus initialization failed; measurements unavailable.");
  }
  restore();
  lastEnergy = millis();

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
  Serial.printf("Firmware: %s; seven appliances; GPIO32 untouched\n", FIRMWARE_VERSION);
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
    if (present && !lcdOnline) { lcd.init(); drawTv(devices[TV_DEVICE_INDEX].on); }
    lcdOnline = present;
  }
  if ((uint32_t)(millis() - lastCheckpoint) >= 60000) checkpoint();
  delay(2);
}
