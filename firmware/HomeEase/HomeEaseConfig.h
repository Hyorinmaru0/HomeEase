#pragma once
#include <Arduino.h>

#if __has_include("secrets.h")
#include "secrets.h"
#else
#define HOMEEASE_WIFI_SSID "YOUR_WIFI_SSID"
#define HOMEEASE_WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
#endif

constexpr char FIRMWARE_VERSION[] = "homeease-2.2";
constexpr uint8_t LIVING_LIGHT_PIN = 25;
constexpr uint8_t BEDROOM_LIGHT_PIN = 26;
constexpr uint8_t MINI_FRIDGE_PIN = 14;
constexpr uint8_t LIVING_AC_PIN = 33;
constexpr uint8_t WALL_LAMP_PIN = 23;
constexpr uint8_t BEDROOM_AC_PIN = 19;

constexpr bool LIVING_AC_ACTIVE_LOW = true;
constexpr bool WALL_LAMP_ACTIVE_LOW = true;

constexpr uint8_t outputLevelForPower(bool on, bool activeLow) {
  return on != activeLow ? HIGH : LOW;
}
static_assert(outputLevelForPower(false, true) == HIGH &&
              outputLevelForPower(true, true) == LOW &&
              outputLevelForPower(false, false) == LOW &&
              outputLevelForPower(true, false) == HIGH,
              "Invalid logical power to GPIO polarity conversion");

constexpr uint8_t RETIRED_FAN_PIN = 32;
constexpr uint8_t ULTRASONIC_TRIG_PIN = 5;
constexpr uint8_t ULTRASONIC_ECHO_PIN = 18;
constexpr uint8_t PIR_PIN = 27;
constexpr uint8_t LCD_SDA_PIN = 21;
constexpr uint8_t LCD_SCL_PIN = 22;
constexpr uint8_t LCD_ADDRESS = 0x27;

constexpr uint8_t INA219_SDA_PIN = 16;
constexpr uint8_t INA219_SCL_PIN = 17;
constexpr uint32_t INA219_I2C_HZ = 100000;
constexpr uint32_t PIR_WARMUP_MS = 60000;
constexpr float OCCUPIED_DISTANCE_CM = 9;
constexpr uint32_t SENSOR_INTERVAL_MS = 250;
constexpr uint32_t ECHO_TIMEOUT_US = 25000;
constexpr long TIMEZONE_OFFSET_SECONDS = 8 * 3600;
constexpr double ELECTRICITY_RATE = 11.50;

constexpr double LIVING_RATED_WATTS = 12;
constexpr double BEDROOM_RATED_WATTS = 9;
constexpr double TV_RATED_WATTS = 1;
constexpr double FRIDGE_RATED_WATTS = 100;
constexpr double LIVING_AC_RATED_WATTS = 750;
constexpr double WALL_LAMP_RATED_WATTS = 5;
constexpr double BEDROOM_AC_RATED_WATTS = 500;
constexpr size_t MAX_SCHEDULES = 16;
constexpr size_t MAX_HISTORY = 32;

constexpr size_t MAX_CHECKPOINT_BYTES = 6000;
constexpr size_t MAX_SCHEDULE_BYTES = 3500;
constexpr uint8_t ASSIGNED_PINS[] = {
  LIVING_LIGHT_PIN, BEDROOM_LIGHT_PIN, MINI_FRIDGE_PIN, LIVING_AC_PIN,
  WALL_LAMP_PIN, BEDROOM_AC_PIN, ULTRASONIC_TRIG_PIN, ULTRASONIC_ECHO_PIN,
  PIR_PIN, LCD_SDA_PIN, LCD_SCL_PIN, INA219_SDA_PIN, INA219_SCL_PIN
};
constexpr bool uniqueSafePins() {
  for (size_t i = 0; i < sizeof(ASSIGNED_PINS); ++i) {
    if (ASSIGNED_PINS[i] == RETIRED_FAN_PIN) return false;
    for (size_t j = i + 1; j < sizeof(ASSIGNED_PINS); ++j)
      if (ASSIGNED_PINS[i] == ASSIGNED_PINS[j]) return false;
  }
  return true;
}
static_assert(uniqueSafePins(), "HomeEase GPIO conflict or retired GPIO32 use");
