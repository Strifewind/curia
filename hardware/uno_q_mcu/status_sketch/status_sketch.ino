#include <ArduinoJson.h>
#include <Arduino_RouterBridge.h>
#include <U8g2lib.h>
#include <Wire.h>
#include <string.h>

#if defined(OLED_SH1106)
U8G2_SH1106_128X64_NONAME_F_HW_I2C display(U8G2_R0, U8X8_PIN_NONE);
#else
U8G2_SSD1306_128X64_NONAME_F_HW_I2C display(U8G2_R0, U8X8_PIN_NONE);
#endif

constexpr unsigned long kStaleAfterMs = 45000;
unsigned long lastUpdateMs = 0;
bool staleScreenShown = false;

void setStatus(String payload) {
  DynamicJsonDocument status(payload.length() * 2 + 256);
  if (deserializeJson(status, payload)) {
    return;
  }

  JsonObject cluster = status["cluster"];
  const char *clusterState = cluster["state"] | "unknown";
  int ready = cluster["ready"] | 0;
  int total = cluster["total"] | 0;
  bool alert = strcmp(clusterState, "healthy") != 0;

  display.clearBuffer();
  display.setFont(u8g2_font_6x12_tf);
  display.drawStr(0, 10, "CURIA HOMELAB");
  display.drawHLine(0, 14, 128);

  char line[32];
  snprintf(line, sizeof(line), "Cluster: %s", clusterState);
  display.drawStr(0, 26, line);
  snprintf(line, sizeof(line), "Nodes ready: %d/%d", ready, total);
  display.drawStr(0, 38, line);

  JsonArray services = status["services"].as<JsonArray>();
  for (JsonObject service : services) {
    const char *serviceState = service["state"] | "unknown";
    JsonObject storage = service["storage"].as<JsonObject>();

    if (strcmp(serviceState, "healthy") != 0 || (storage["alert?"] | false)) {
      alert = true;
    }
  }

#if defined(CURIA_STATUS_LED_PIN)
  digitalWrite(CURIA_STATUS_LED_PIN, alert ? HIGH : LOW);
#endif

  if (!services.isNull() && services.size() > 0) {
    JsonObject service = services[0];
    const char *name = service["name"] | "Service";
    const char *state = service["state"] | "unknown";
    int latency = service["latency_ms"] | -1;
    snprintf(line, sizeof(line), "%.8s %s %dms", name, state, latency);
    display.drawStr(0, 50, line);
  } else {
    display.drawStr(0, 50, "No service checks");
  }

  for (JsonObject service : services) {
    JsonObject storage = service["storage"].as<JsonObject>();
    if (!storage.isNull()) {
      int usedPercent = storage["percent"] | 0;
      bool alert = storage["alert?"] | false;
      snprintf(line, sizeof(line), "Storage: %d%% %s", usedPercent, alert ? "ALERT" : "OK");
      display.drawStr(0, 60, line);
      break;
    }
  }

  display.sendBuffer();
  lastUpdateMs = millis();
  staleScreenShown = false;
}

void setup() {
#if defined(CURIA_STATUS_LED_PIN)
  pinMode(CURIA_STATUS_LED_PIN, OUTPUT);
  digitalWrite(CURIA_STATUS_LED_PIN, HIGH);
#endif

  Wire.begin();
  display.begin();
  display.setContrast(180);
  display.clearBuffer();
  display.setFont(u8g2_font_6x12_tf);
  display.drawStr(0, 20, "CURIA");
  display.drawStr(0, 38, "Waiting for Linux");
  display.sendBuffer();

  Bridge.begin();
  Bridge.provide_safe("set_status", setStatus);
  lastUpdateMs = millis();
}

void loop() {
  if (!staleScreenShown && millis() - lastUpdateMs > kStaleAfterMs) {
#if defined(CURIA_STATUS_LED_PIN)
    digitalWrite(CURIA_STATUS_LED_PIN, HIGH);
#endif

    display.clearBuffer();
    display.setFont(u8g2_font_6x12_tf);
    display.drawStr(0, 22, "Linux status stale");
    display.drawStr(0, 40, "Check network/link");
    display.sendBuffer();
    staleScreenShown = true;
  }

  delay(50);
}
