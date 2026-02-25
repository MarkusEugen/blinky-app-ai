/*
 * LumiBand — Arduino Nano 33 BLE firmware
 *
 * Hardware:
 *   - Arduino Nano 33 BLE (nRF52840)
 *   - WS2812B strip, 15 LEDs, data on pin D6, powered from 5 V (VIN/USB)
 *
 * Libraries (install via Arduino Library Manager):
 *   - ArduinoBLE       (by Arduino)
 *   - Adafruit NeoPixel (by Adafruit)
 *
 * BLE protocol — see ble_service.dart for the Flutter side.
 */

#include <ArduinoBLE.h>
#include <Adafruit_NeoPixel.h>

// ── Hardware ─────────────────────────────────────────────────────────────────

#define NEO_PIN   6
#define NUM_LEDS  15   // must equal kMaxLed in Flutter app

Adafruit_NeoPixel strip(NUM_LEDS, NEO_PIN, NEO_GRB + NEO_KHZ800);

// ── BLE UUIDs — must match ble_service.dart ───────────────────────────────────

#define SVC_UUID    "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define COLOR_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BRIGHT_UUID "beb5483f-36e1-4688-b7f5-ea07361b26a8"
#define CMD_UUID    "beb54840-36e1-4688-b7f5-ea07361b26a8"
#define FX_UUID     "beb54841-36e1-4688-b7f5-ea07361b26a8"

BLEService          svc(SVC_UUID);
BLECharacteristic   colorChar (COLOR_UUID,  BLEWrite, 3);   // [R, G, B]
BLECharacteristic   brightChar(BRIGHT_UUID, BLEWrite, 1);   // [0-255]
BLECharacteristic   cmdChar   (CMD_UUID,    BLEWrite, 2);   // [type, arg]
BLECharacteristic   fxChar    (FX_UUID,     BLEWrite, 20);  // chunked upload

// ── Effect storage ────────────────────────────────────────────────────────────

#define NUM_EFFECTS  8
#define NUM_ROWS     8

struct Effect {
  uint8_t rgb[NUM_ROWS][NUM_LEDS][3];  // [row][led][R/G/B]
  uint8_t settings;                    // bits 0-3: SoundMode, bit 4: LoopMode
};

Effect effects[NUM_EFFECTS];
bool   effectLoaded[NUM_EFFECTS] = {};

// Upload accumulator (481 bytes: 8×15×4 ARGB + 1 settings)
uint8_t uploadBuf[481];
int     uploadSlot = -1;
int     uploadLen  = 0;

// ── Runtime state ─────────────────────────────────────────────────────────────

enum class Mode { Solid, Effect } currentMode = Mode::Solid;

uint8_t solidR = 0, solidG = 0, solidB = 0;
uint8_t bright = 255;  // 0–255

int  activeSlot    = 0;
int  currentRow    = 0;
bool bounceForward = true;

unsigned long lastTick = 0;
const uint16_t ROW_MS = 500;  // ms per row during playback

// ── Helpers ───────────────────────────────────────────────────────────────────

// Apply global brightness to a channel value.
static inline uint8_t dim(uint8_t v) {
  return (uint16_t)v * bright / 255;
}

void showSolid(uint8_t r, uint8_t g, uint8_t b) {
  for (int i = 0; i < NUM_LEDS; i++) {
    strip.setPixelColor(i, dim(r), dim(g), dim(b));
  }
  strip.show();
}

void showRow(int slot, int row) {
  const uint8_t (*rgb)[3] = effects[slot].rgb[row];
  for (int i = 0; i < NUM_LEDS; i++) {
    strip.setPixelColor(i, dim(rgb[i][0]), dim(rgb[i][1]), dim(rgb[i][2]));
  }
  strip.show();
}

// Parse the 481-byte ARGB+settings buffer into an Effect struct.
// Flutter Color.value layout: 0xAARRGGBB (big-endian in the stream).
void commitUpload(int slot) {
  Effect &e = effects[slot];
  int idx = 0;
  for (int row = 0; row < NUM_ROWS; row++) {
    for (int led = 0; led < NUM_LEDS; led++) {
      e.rgb[row][led][0] = uploadBuf[idx + 1]; // R
      e.rgb[row][led][1] = uploadBuf[idx + 2]; // G
      e.rgb[row][led][2] = uploadBuf[idx + 3]; // B
      idx += 4;
    }
  }
  e.settings = uploadBuf[480];
  effectLoaded[slot] = true;
  Serial.print("FX committed slot ");
  Serial.println(slot);
}

void advanceRow() {
  const bool bounce = (effects[activeSlot].settings & 0x10) != 0;
  if (!bounce) {
    currentRow = (currentRow + 1) % NUM_ROWS;
  } else {
    if (bounceForward) {
      if (currentRow >= NUM_ROWS - 1) { bounceForward = false; currentRow = NUM_ROWS - 2; }
      else                             { currentRow++; }
    } else {
      if (currentRow <= 0) { bounceForward = true; currentRow = 1; }
      else                 { currentRow--; }
    }
  }
}

// ── setup ─────────────────────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);

  // Built-in LED: off = disconnected, on = connected.
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);

  strip.begin();
  strip.setBrightness(255);
  strip.show();

  if (!BLE.begin()) {
    Serial.println("BLE init failed — halting");
    while (true);
  }

  BLE.setLocalName("LumiBand");
  BLE.setAdvertisedService(svc);

  svc.addCharacteristic(colorChar);
  svc.addCharacteristic(brightChar);
  svc.addCharacteristic(cmdChar);
  svc.addCharacteristic(fxChar);

  BLE.addService(svc);
  BLE.advertise();

  Serial.println("LumiBand advertising…");
}

// ── loop ──────────────────────────────────────────────────────────────────────

void loop() {
  BLEDevice central = BLE.central();

  if (!central || !central.connected()) return;

  // Central just connected.
  digitalWrite(LED_BUILTIN, HIGH);
  Serial.print("Connected: ");
  Serial.println(central.address());

  while (central.connected()) {
    BLE.poll();

    // ── Color ──────────────────────────────────────────────────────────────
    if (colorChar.written()) {
      const uint8_t *d = colorChar.value();
      solidR = d[0]; solidG = d[1]; solidB = d[2];
      currentMode = Mode::Solid;
      showSolid(solidR, solidG, solidB);
    }

    // ── Brightness ─────────────────────────────────────────────────────────
    if (brightChar.written()) {
      bright = brightChar.value()[0];
      if (currentMode == Mode::Solid) showSolid(solidR, solidG, solidB);
      // Effect mode: brightness applied on next row tick.
    }

    // ── Command ────────────────────────────────────────────────────────────
    if (cmdChar.written()) {
      const uint8_t *d = cmdChar.value();
      switch (d[0]) {

        case 0x01: // Activate effect slot
          if (d[1] < NUM_EFFECTS && effectLoaded[d[1]]) {
            activeSlot    = d[1];
            currentRow    = 0;
            bounceForward = true;
            lastTick      = millis();
            currentMode   = Mode::Effect;
            showRow(activeSlot, currentRow);
          }
          break;

        case 0x02: // Activate preset (placeholder — add your presets here)
          currentMode = Mode::Solid;
          showSolid(0, 0, 255);
          break;

        case 0x03: // Return to solid colour
          currentMode = Mode::Solid;
          showSolid(solidR, solidG, solidB);
          break;
      }
    }

    // ── Effect upload ──────────────────────────────────────────────────────
    //
    // Packet types written to fxChar:
    //   [0x00, slot]         begin upload for slot
    //   [0x01, d0…d18]       append data bytes
    //   [0x02, slot]         commit
    //
    if (fxChar.written()) {
      const uint8_t *d = fxChar.value();
      const int      len = fxChar.valueLength();

      if (d[0] == 0x00 && len >= 2) {
        // Begin
        uploadSlot = d[1];
        uploadLen  = 0;
        Serial.print("FX begin slot "); Serial.println(uploadSlot);

      } else if (d[0] == 0x01 && uploadSlot >= 0) {
        // Data chunk — payload starts at d[1]
        int payloadLen = len - 1;
        if (uploadLen + payloadLen <= 481) {
          memcpy(uploadBuf + uploadLen, d + 1, payloadLen);
          uploadLen += payloadLen;
        }

      } else if (d[0] == 0x02 && uploadSlot >= 0) {
        // Commit
        if (uploadLen == 481) {
          commitUpload(uploadSlot);
        } else {
          Serial.print("FX upload size mismatch: "); Serial.println(uploadLen);
        }
        uploadSlot = -1;
        uploadLen  = 0;
      }
    }

    // ── Effect animation tick ──────────────────────────────────────────────
    if (currentMode == Mode::Effect && effectLoaded[activeSlot]) {
      if (millis() - lastTick >= ROW_MS) {
        advanceRow();
        showRow(activeSlot, currentRow);
        lastTick = millis();
      }
    }
  }

  // Central disconnected.
  digitalWrite(LED_BUILTIN, LOW);
  Serial.println("Disconnected");
}
