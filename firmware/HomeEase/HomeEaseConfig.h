#pragma once
#include <Arduino.h>

// Copy secrets.example.h to secrets.h and enter your Wi-Fi credentials.
#if __has_include("secrets.h")
#include "secrets.h"
#else
#define HOMEEASE_WIFI_SSID "YOUR_WIFI_SSID"
#define HOMEEASE_WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
#endif

// ESP32-WROOM-32 / Arduino IDE: ESP32 Dev Module. User-tested wiring.
constexpr uint8_t LIVING_LIGHT_PIN = 25;
constexpr uint8_t BEDROOM_LIGHT_PIN = 26;
constexpr uint8_t FAN_RELAY_PIN = 32;
#ifndef HOMEEASE_ENABLE_FAN_RELAY
#define HOMEEASE_ENABLE_FAN_RELAY 0
#endif
// October 15 presentation: relay and motor are disconnected. No GPIO32 access.
// Set to 1 only after reconnecting and verifying the future relay/fan assembly.
constexpr bool FAN_RELAY_ENABLED = HOMEEASE_ENABLE_FAN_RELAY != 0;
constexpr bool FAN_RELAY_ACTIVE_LOW = true; // Change to false for active-HIGH.
constexpr uint8_t ULTRASONIC_TRIG_PIN = 5;
constexpr uint8_t ULTRASONIC_ECHO_PIN = 18; // Via the tested 1k/2k divider.
constexpr uint8_t PIR_PIN = 27;
constexpr uint8_t LCD_SDA_PIN = 21;
constexpr uint8_t LCD_SCL_PIN = 22;
constexpr uint8_t LCD_ADDRESS = 0x27;
constexpr uint32_t PIR_WARMUP_MS = 60000;
constexpr uint32_t PIR_VACANCY_DELAY_MS = 7000;
constexpr float OCCUPIED_DISTANCE_CM = 100; // Calibrate to the room placement.
constexpr uint32_t SENSOR_INTERVAL_MS = 250;
constexpr uint32_t ECHO_TIMEOUT_US = 25000;
constexpr long TIMEZONE_OFFSET_SECONDS = 8 * 3600; // Asia/Manila
constexpr double ELECTRICITY_RATE = 11.50; // Match the app's rate setting.
// Illustrative ratings only, NOT INA219 readings. Set actual load ratings here.
constexpr double LIVING_RATED_WATTS = 12;
constexpr double BEDROOM_RATED_WATTS = 9;
constexpr double FAN_RATED_WATTS = 45;
constexpr double TV_RATED_WATTS = 1;
constexpr size_t MAX_SCHEDULES = 16;
constexpr size_t MAX_HISTORY = 32;
// Keep two checkpoint generations within the default 20 KiB NVS partition.
constexpr size_t MAX_CHECKPOINT_BYTES = 6000;
constexpr size_t MAX_SCHEDULE_BYTES = 3500;
// GPIO33 reed switch, INA219 and buzzer are pending; intentionally not enabled.
