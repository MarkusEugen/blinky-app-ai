/*
 * LumiBand — Arduino Nano 33 BLE firmware
 *
 * Hardware:
 *   - Arduino Nano 33 BLE (nRF52840)
 *   - WS2812B strip, 15 LEDs, data on pin D12, powered from 5 V (VIN/USB)
 *   - Microphone on A3 (required for Classic mode)
 *
 * Modes (BLE command [0x02, index] or [0x02, 5, count] for Custom):
 *   0 = Classic  — sound-reactive animation engine  (preset_classic.h)
 *   1 = Static   — solid white, full brightness     (preset_static.h)
 *   2 = Party    — fast cycling rainbow             (preset_party.h)
 *   3 = Lava     — slow red-orange pulses           (preset_lava.h)
 *   4 = Dim      — soft warm candle glow            (preset_dim.h)
 *   5 = Custom   — plays uploaded effect matrices   (preset_custom.h)
 *
 * Custom effects: up to 8 user-uploadable slots stored in internal flash.
 *
 * Libraries (Arduino Library Manager):
 *   - ArduinoBLE        (by Arduino)
 *   - Adafruit NeoPixel (by Adafruit)
 */

// ── Hardware ─────────────────────────────────────────────────────────────────

#define NEO_PIN   12
#define NUM_LEDS  15   // must equal kMaxLed in Flutter app
#define MIC_PIN   A3   // electret mic input (Classic mode)

#include <ArduinoBLE.h>
#include <Adafruit_NeoPixel.h>
#include <FlashIAP.h>   // Mbed OS — available on all Arduino Mbed boards

// Must be declared after includes so Arduino's auto-prototype injector sees
// the types before it generates forward declarations for functions that use them.
struct pixFormat { uint8_t r; uint8_t g; uint8_t b; };

// Declared here (before the first function definition) so the auto-generated
// prototype for modeInit(Mode m) can resolve the type.
enum class Mode { Classic = 0, Static = 1, Party = 2, Lava = 3, Dim = 4, Custom = 5 };

Adafruit_NeoPixel strip(NUM_LEDS, NEO_PIN, NEO_GRB + NEO_KHZ800);

// ── BLE UUIDs — must match ble_service.dart ───────────────────────────────────

#define SVC_UUID    "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define COLOR_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BRIGHT_UUID "beb5483f-36e1-4688-b7f5-ea07361b26a8"
#define CMD_UUID    "beb54840-36e1-4688-b7f5-ea07361b26a8"
#define FX_UUID     "beb54841-36e1-4688-b7f5-ea07361b26a8"
#define STATUS_UUID "beb54842-36e1-4688-b7f5-ea07361b26a8"

BLEService          svc(SVC_UUID);
BLECharacteristic   colorChar (COLOR_UUID,  BLEWrite,            3);   // [R, G, B]
BLECharacteristic   brightChar(BRIGHT_UUID, BLEWrite,            1);   // [0–255]
BLECharacteristic   cmdChar   (CMD_UUID,    BLEWrite,            20);  // [type, arg, ...]
BLECharacteristic   fxChar    (FX_UUID,     BLEWrite,            20);  // chunked upload
// STATUS: app reads on connect to sync mode + brightness.
// [0] = mode index 0-5  [1] = brightness 0-255
BLECharacteristic   statusChar(STATUS_UUID, BLERead | BLENotify, 2);

// ── Custom effect storage ─────────────────────────────────────────────────────

#define NUM_EFFECTS  8
#define NUM_ROWS     15

struct __attribute__((packed)) Effect {
  uint16_t rgb565[NUM_ROWS][NUM_LEDS];  // [row][led] RGB565  450 bytes
  uint8_t  settings;                    // bits 0-3: SoundMode, bit 4: LoopMode
  uint16_t rowMs;                       // row advance interval in ms (20–1000)
};

Effect effects[NUM_EFFECTS];
bool   effectLoaded[NUM_EFFECTS] = {};

// Upload accumulator (453 bytes: 15×15×2 RGB565 + 1 settings + 2 rowMs)
uint8_t uploadBuf[453];
int     uploadSlot = -1;
int     uploadLen  = 0;

// ── Runtime state ─────────────────────────────────────────────────────────────
// Declared here (before flashLoad/flashSave) so those functions can access them.
// Also before mode includes so tick functions can read them directly.

Mode    activeMode       = Mode::Classic;
uint8_t bright           = 255;   // 0–255, master brightness for all modes
uint8_t savedCustomCount = 1;     // Custom-mode slot count — persisted in flash
uint8_t solidR = 0, solidG = 0, solidB = 0;  // last received RGB (stored for future use)

// ── BLE power management ──────────────────────────────────────────────────────

#define BLE_SLEEP_MS  (5UL * 60 * 1000)  // stop advertising after 5 min if never connected

bool          bleSleeping        = false;
unsigned long bleAdvertiseStartMs = 0;

// ── Flash persistence ─────────────────────────────────────────────────────────

#define FLASH_MAGIC  0x4C551E04UL   // bumped: RGB565 + 15 rows

struct __attribute__((packed)) FlashStore {
  uint32_t magic;
  Effect   effects[NUM_EFFECTS];
  uint8_t  loaded[NUM_EFFECTS];   // 8 bytes
  uint8_t  savedBright;           // master brightness (0–255)
  uint8_t  savedMode;             // Mode enum value (0–5)
  uint8_t  savedCustomSlots;      // slots to cycle in Custom mode (1–NUM_EFFECTS)
  uint8_t  _pad;                  // keeps total size 4-byte aligned
};

static_assert(sizeof(FlashStore) % 4 == 0,
              "FlashStore must be 4-byte aligned for FlashIAP::program()");

mbed::FlashIAP flash;

static uint32_t flashStoreAddr() {
  uint32_t start  = flash.get_flash_start();
  uint32_t size   = flash.get_flash_size();
  uint32_t sector = flash.get_sector_size(start + size - 1);
  return start + size - sector;
}

void flashLoad() {
  flash.init();
  FlashStore store;
  flash.read(&store, flashStoreAddr(), sizeof(store));
  flash.deinit();

  if (store.magic != FLASH_MAGIC) {
    Serial.println("Flash: no valid data — using defaults");
    return;
  }
  for (int i = 0; i < NUM_EFFECTS; i++) {
    effects[i]      = store.effects[i];
    effectLoaded[i] = store.loaded[i];
  }
  bright           = store.savedBright;
  activeMode       = (Mode)constrain((int)store.savedMode, 0, 5);
  savedCustomCount = constrain((int)store.savedCustomSlots, 1, NUM_EFFECTS);
  Serial.print("Flash: restored — mode="); Serial.print((int)activeMode);
  Serial.print(" bright=");               Serial.println(bright);
}

void flashSave() {
  flash.init();
  uint32_t addr   = flashStoreAddr();
  uint32_t sector = flash.get_sector_size(addr);

  FlashStore store;
  store.magic = FLASH_MAGIC;
  for (int i = 0; i < NUM_EFFECTS; i++) {
    store.effects[i] = effects[i];
    store.loaded[i]  = effectLoaded[i];
  }
  store.savedBright       = bright;
  store.savedMode         = (uint8_t)activeMode;
  store.savedCustomSlots  = (uint8_t)savedCustomCount;
  store._pad              = 0;

  int err = flash.erase(addr, sector);
  if (err != 0) {
    Serial.print("Flash erase error: "); Serial.println(err);
    flash.deinit();
    return;
  }
  err = flash.program(&store, addr, sizeof(store));
  flash.deinit();
  if (err != 0) { Serial.print("Flash program error: "); Serial.println(err); }
  else           { Serial.println("Flash: saved"); }
}

// ── Core helpers ──────────────────────────────────────────────────────────────
// Declared before mode includes so all mode files can call them.

static inline uint8_t dim(uint8_t v) {
  return (uint16_t)v * bright / 255;
}

// showSolid: fills the strip with a solid colour, applying master brightness.
// Pass raw 0-255 values — dim() is applied internally.
void showSolid(uint8_t r, uint8_t g, uint8_t b) {
  for (int i = 0; i < NUM_LEDS; i++) strip.setPixelColor(i, dim(r), dim(g), dim(b));
  strip.show();
}

// showRow: renders one row of an uploaded effect, unpacking RGB565 and
// applying master brightness.
void showRow(int slot, int row) {
  for (int i = 0; i < NUM_LEDS; i++) {
    uint16_t c = effects[slot].rgb565[row][i];
    uint8_t r5 = (c >> 11) & 0x1F;
    uint8_t g5 = (c >> 5)  & 0x1F;
    uint8_t b5 =  c        & 0x1F;
    strip.setPixelColor(i, dim(r5 * 8), dim(g5 * 8), dim(b5 * 8));
  }
  strip.show();
}

// ── Audio engine — must come before mode includes ─────────────────────────────
// Provides audioInit(), audioTick(), and the shared globals:
//   gAmbient, gRelativePegel, gOnBeat, gDirection2, gPegel_smooth, gSpin2

#include "audio.h"

// ── Mode implementations ──────────────────────────────────────────────────────

#include "preset_classic.h"
#include "preset_static.h"
#include "preset_party.h"
#include "preset_lava.h"
#include "preset_dim.h"
#include "preset_custom.h"

// ── Mode dispatch ─────────────────────────────────────────────────────────────

// Initialise a mode that does not need extra parameters (modes 0-4).
// Custom (5) is initialised via customInit(count) directly in the CMD handler.
void modeInit(Mode m) {
  switch (m) {
    case Mode::Classic: classicInit(); break;
    case Mode::Static:  staticInit();  break;
    case Mode::Party:   partyInit();   break;
    case Mode::Lava:    lavaInit();    break;
    case Mode::Dim:     dimInit();     break;
    default: break;
  }
}

void runModeTick() {
  switch (activeMode) {
    case Mode::Classic: classicTick(); break;
    case Mode::Static:  staticTick();  break;
    case Mode::Party:   partyTick();   break;
    case Mode::Lava:    lavaTick();    break;
    case Mode::Dim:     dimTick();     break;
    case Mode::Custom:  customTick();  break;
  }
}

// ── STATUS characteristic ─────────────────────────────────────────────────────
// Notify the app whenever mode or brightness changes.
// Byte [0] = mode index (0-5), byte [1] = brightness (0-255).

void updateStatus() {
  uint8_t buf[2] = { (uint8_t)activeMode, bright };
  statusChar.writeValue(buf, 2);
}

// ── Effect upload helpers ─────────────────────────────────────────────────────

// Parse the 453-byte RGB565+settings+rowMs buffer into the Effect struct, then persist.
// bytes   0–449  15 rows × 15 LEDs × 2-byte big-endian RGB565
// byte  450      settings bitmask
// bytes 451–452  rowMs big-endian uint16 (20–1000 ms)
void commitUpload(int slot) {
  Effect &e = effects[slot];
  int idx = 0;
  for (int row = 0; row < NUM_ROWS; row++) {
    for (int led = 0; led < NUM_LEDS; led++) {
      e.rgb565[row][led] = ((uint16_t)uploadBuf[idx] << 8) | uploadBuf[idx + 1];
      idx += 2;
    }
  }
  e.settings = uploadBuf[450];
  uint16_t ms = ((uint16_t)uploadBuf[451] << 8) | uploadBuf[452];
  e.rowMs    = (ms >= 20 && ms <= 1000) ? ms : 500;
  effectLoaded[slot] = true;
  Serial.print("FX committed slot "); Serial.println(slot);
  flashSave();
}

// ── setup ─────────────────────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);

  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);

  strip.begin();
  strip.setBrightness(16);
  strip.show();

  audioInit();   // establish baseline before any mode starts
  flashLoad();

  // Initialise the restored (or default) mode before BLE is up.
  // Custom needs customInit(count); all others use the generic dispatcher.
  if (activeMode == Mode::Custom) {
    customInit(savedCustomCount);
  } else {
    modeInit(activeMode);
  }

  if (!BLE.begin()) {
    Serial.println("BLE init failed — halting");
    while (true);
  }

  // Build a unique name from the last 2 bytes of the BLE MAC address,
  // e.g. "LumiBand-A3F2" so multiple bands are distinguishable in the list.
  String mac = BLE.address();          // "aa:bb:cc:dd:ee:ff"
  String suffix = mac.substring(mac.length() - 5); // "ee:ff"
  suffix.replace(":", "");
  suffix.toUpperCase();                // "EEFF"
  String deviceName = "LumiBand-" + suffix;
  BLE.setLocalName(deviceName.c_str());
  BLE.setAdvertisedService(svc);
  svc.addCharacteristic(colorChar);
  svc.addCharacteristic(brightChar);
  svc.addCharacteristic(cmdChar);
  svc.addCharacteristic(fxChar);
  svc.addCharacteristic(statusChar);
  BLE.addService(svc);

  // Power-saving settings (must be set before advertise()).
  BLE.setAdvertisingInterval(800);     // ~500 ms interval (default ~100 ms)
  BLE.setConnectionInterval(80, 160);  // 100–200 ms connection interval

  BLE.advertise();
  bleAdvertiseStartMs = millis();

  Serial.print("Advertising as: ");
  Serial.println(deviceName);
}

// ── loop ──────────────────────────────────────────────────────────────────────
// Non-blocking design: runModeTick() is called every iteration regardless of
// BLE state, so LEDs keep animating when the phone disconnects.

void loop() {
  BLE.poll();   // must always run — keeps the BLE stack healthy

  BLEDevice central   = BLE.central();
  bool      connected = central && central.connected();

  static bool wasConnected = false;

  // ── Connect / disconnect edge detection ───────────────────────────────────
  if (connected && !wasConnected) {
    wasConnected = true;
    bleSleeping  = false;
    digitalWrite(LED_BUILTIN, HIGH);
    Serial.print("Connected: ");
    Serial.println(central.address());
    updateStatus();  // prime STATUS so app can read it immediately
  } else if (!connected && wasConnected) {
    wasConnected = false;
    digitalWrite(LED_BUILTIN, LOW);
    Serial.println("Disconnected — resuming advertising");
    BLE.advertise();
    bleAdvertiseStartMs = millis();  // reset sleep timer after each session
  }

  // ── BLE sleep after 5 min with no connection ──────────────────────────────
  // stopAdvertise() is enough to save radio power; BLE.poll() must keep running
  // so the stack stays healthy and can resume advertising later.
  if (!bleSleeping && !connected &&
      millis() - bleAdvertiseStartMs >= BLE_SLEEP_MS) {
    BLE.stopAdvertise();
    bleSleeping = true;
    Serial.println("BLE: radio idle (not advertising). Wakes on power cycle.");
  }

  // ── BLE characteristic writes (only processed while connected) ────────────
  if (connected) {

    // Colour (stored for future use — does not change the active mode).
    if (colorChar.written()) {
      const uint8_t *d = colorChar.value();
      solidR = d[0]; solidG = d[1]; solidB = d[2];
    }

    // Brightness — all mode tick functions read `bright` directly, so the
    // change is picked up on the very next tick. No mode re-init required.
    if (brightChar.written()) {
      bright = brightChar.value()[0];
      updateStatus();
      flashSave();
    }

    // Command:
    //   [0x02, modeIndex]      — activate mode 0-4
    //   [0x02, 5, count]       — activate Custom mode with `count` slots
    if (cmdChar.written()) {
      const uint8_t *d   = cmdChar.value();
      const int      len = cmdChar.valueLength();

      if (d[0] == 0x02) {
        uint8_t idx = d[1];
        if (idx <= 5) {
          activeMode = (Mode)idx;
          if (activeMode == Mode::Custom) {
            int count = (len >= 3) ? (int)d[2] : 1;
            savedCustomCount = (uint8_t)count;
            customInit(count);
          } else {
            modeInit(activeMode);
          }
          updateStatus();
          flashSave();
          Serial.print("Mode → "); Serial.println(idx);
        }
      }
    }

    // Effect upload:
    //   [0x00, slot]     — begin upload (resets accumulator)
    //   [0x01, d0…d18]   — append up to 19 bytes of payload
    //   [0x02, slot]     — commit → parse + save to flash
    if (fxChar.written()) {
      const uint8_t *d   = fxChar.value();
      const int      len = fxChar.valueLength();

      if (d[0] == 0x00 && len >= 2) {
        uploadSlot = d[1];
        uploadLen  = 0;
        Serial.print("FX begin slot "); Serial.println(uploadSlot);

      } else if (d[0] == 0x01 && uploadSlot >= 0) {
        int payloadLen = len - 1;
        if (uploadLen + payloadLen <= 453) {
          memcpy(uploadBuf + uploadLen, d + 1, payloadLen);
          uploadLen += payloadLen;
        }

      } else if (d[0] == 0x02 && uploadSlot >= 0) {
        if (uploadLen == 453) {
          commitUpload(uploadSlot);
        } else {
          Serial.print("FX upload size mismatch: "); Serial.println(uploadLen);
        }
        uploadSlot = -1;
        uploadLen  = 0;
      }
    }
  }

  // ── Audio + mode tick — rate-limited to ~50 fps ───────────────────────────
  static unsigned long lastTick = 0;
  unsigned long now = millis();
  unsigned long elapsed = now - lastTick;
  if (elapsed < 20) {
    delay(20 - elapsed);  // Mbed OS sleep (System ON Low Power) until next tick
    return;
  }
  lastTick = millis();
  audioTick();    // sample mic, update shared audio globals
  runModeTick();
}
