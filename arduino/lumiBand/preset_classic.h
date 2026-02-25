// ═══════════════════════════════════════════════════════════════════════════════
// CLASSIC PRESET
// Sound-reactive LED animation engine
// Ported from armband_BLE.ino (© 2023 Markus E. Loeffler / WAVELIGHTS)
//
// Requires (declared in lumiBand.ino before this include):
//   Adafruit_NeoPixel strip;
//   uint8_t bright;
//   #define NUM_LEDS, MIC_PIN
// ═══════════════════════════════════════════════════════════════════════════════
#pragma once

// Classic aliases — keep effect function bodies unchanged from the original
#define LED_COUNT  NUM_LEDS
#define LED_OFFSET 0

#define RAW_BUFFER_SIZE         160
#define MIN_AMBIENT_FLOOR       8.f
#define LED_COUNT_HALF          (LED_COUNT / 2)
#define BEATCOUNT_MAX           64
#define COLOR_COUNT             8
#define STORY_COUNT             9
#define WHITE_FLASH_COLOR       0xffffaf
#define WHITE_FLASH_COLOR_SHIFT 0xafaf6f
#define pi                      3.141592653589793f
#define MIN_LED_LUMA            25
#define maxMem                  2

// Global audio / animation state
bool     gOnBeat        = false;
uint8_t  gBeatCounter   = 0;
uint32_t gNOW           = 0;
uint8_t  gStoryPtr      = 0;
uint8_t  gColorPtr      = 0;
uint32_t gTimeDif       = 0;
uint8_t  gEffect        = 0;
uint32_t gLastBeatTime  = 0;
float    gLastPegel     = 0.f;
float    gAmbient       = 0.f;
float    gRelativePegel = 0.f;
float    gDirection2    = 1.f;
float    gSpin2         = 0.f;
float    gPegel_smooth  = 0.f;
uint16_t stars_buffer[LED_COUNT];
uint16_t hueshift       = 0;
uint8_t  gShiftDir      = 0;
uint16_t e8_persSat     = 255;
uint16_t e8_hue         = 0;
float    e9_posMem[maxMem];
uint16_t e9_bpmMem[maxMem];
int8_t   e9_dirMem[maxMem];
unsigned long e9_lastSpin = 0;

const uint8_t gManuColor = 0;  // always 0 = auto-color mode

// Pseudo-random source — replaces PROGMEM lookup table from original sketch
uint8_t randomSync() {
  return (uint8_t)random(256);
}

float fract(float x) { return x - floor(x); }

float triwave(float v) {   // input 0..1 → output -1..1
  float x = 2.f * v;
  return 1.0f - 4.f * fabs(0.5f - fract(0.5f * x + 0.25f));
}

float modf(float x, float y) { return x - y * floor(x / y); }

uint32_t getColor(float valu) {
  valu = min(1.0f, max(0.f, valu));
  valu *= valu;
  uint16_t hue = gNOW >> 1;
  uint8_t  sat = gOnBeat ? 180 : 255;
  uint8_t  val = MIN_LED_LUMA + valu * 230.f;

  uint32_t color;
  switch (gColorPtr) {
    case 0:  // luma ramp + sat shift
      hue += valu * 30000 + gPegel_smooth * 40000;
      sat  = sat - 35.f * valu;
      break;
    case 1:  // just red
      hue = 64000 + val * 30;
      break;
    case 2:  // hue + 180 degree
      hue += val * 137;
      break;
    case 3:  // luma ramp, light blue in the middle
      sat = 255;
      if      (val > 150) hue += 32768;
      else if (val > 85)  { sat = gRelativePegel * gRelativePegel * 255; sat = 255 - sat; }
      break;
    case 4:  // flash dissolve to black
      sat  = 255;
      hue += gRelativePegel * 255.f * 150;
      break;
    case 5:  // just blue
      hue = gNOW / 2 - val * 50;
      break;
    case 6:  // fixed reds at upper end
      hue = (val >= 128 ? 0 : hue * (1.f - valu));
      sat  = sat - 60.f + 60.f * valu;
      break;
    case 7:
      {
        float d = valu + gSpin2 / 40.f;
        hue += triwave(d) * 10000;
        sat  = 200 + triwave(valu + d) * 55;
        break;
      }
  }
  color = strip.ColorHSV(hue, sat, val);
  return color;
}

void mirrorPixels(pixFormat* pArray, bool quart) {
  if (quart)
    for (uint8_t i = 0; i < LED_COUNT / 4; i++) {
      uint8_t half = LED_COUNT / 2 - 2 - i;
      pArray[half + LED_OFFSET].r = pArray[i + LED_OFFSET].r;
      pArray[half + LED_OFFSET].g = pArray[i + LED_OFFSET].g;
      pArray[half + LED_OFFSET].b = pArray[i + LED_OFFSET].b;
    }
  for (uint8_t i = 0; i < LED_COUNT_HALF; i++) {
    uint8_t half = LED_COUNT - 2 - i;
    pArray[half + LED_OFFSET].r = pArray[i + LED_OFFSET].r;
    pArray[half + LED_OFFSET].g = pArray[i + LED_OFFSET].g;
    pArray[half + LED_OFFSET].b = pArray[i + LED_OFFSET].b;
  }
}

void spin(float& pos, int16_t bpm, uint16_t timeDiff) {
  float realPos = modf(pos + (float)(LED_COUNT * timeDiff) / (float)bpm, LED_COUNT);
  realPos += realPos < 0 ? LED_COUNT : 0;
  pos = realPos;
  uint8_t pixPos = realPos;
  stars_buffer[pixPos % LED_COUNT] = 255;
}

void binkieEffect9_reset() {
  e9_lastSpin = gNOW;
  for (uint16_t i = 0; i < maxMem; i++) {
    e9_posMem[i] = 0;
    e9_bpmMem[i] = 500;
    e9_dirMem[i] = (i % 2 == 0 ? 1 : -1);
  }
}

// Effect 0: 2-dot spinner, BPM-locked
void spinner() {
  bool over = gNOW - gLastBeatTime > 10000;
  if (gOnBeat) e9_bpmMem[randomSync() % maxMem] = gTimeDif;

  for (uint8_t i = 0; i < LED_COUNT; i++) stars_buffer[i] = 0;

  for (uint8_t mem = 0; mem < maxMem; mem++) {
    if (over) { e9_bpmMem[mem] *= 2; gLastBeatTime = gNOW; }
    spin(e9_posMem[mem], e9_dirMem[mem] * e9_bpmMem[mem], gNOW - e9_lastSpin);
  }
  for (uint8_t i = 0; i < LED_COUNT; i++) {
    uint32_t color = getColor(stars_buffer[i] > 0 ? gRelativePegel * 0.3f + 0.7f : 0.3f);
    strip.setPixelColor(i + LED_OFFSET, color);
  }
  e9_lastSpin = gNOW;
}

// Effect 1: pixel shift ring with random direction on beat
void shiftRing() {
  pixFormat* px = (pixFormat*)strip.getPixels();
  uint32_t color;
  if (gOnBeat && gBeatCounter % 4 == 1) {
    gShiftDir = randomSync() % 4;
    color = WHITE_FLASH_COLOR_SHIFT;
  } else
    color = getColor(gRelativePegel);

  uint8_t newPixPos;
  switch (gShiftDir) {
    case 0:
      for (uint8_t k = 0; k < LED_COUNT - 1; ++k) px[k + LED_OFFSET] = px[k + 1 + LED_OFFSET];
      newPixPos = LED_COUNT - 1;
      break;
    case 1:
      for (uint8_t k = LED_COUNT - 1; k > 0; --k) px[k + LED_OFFSET] = px[k - 1 + LED_OFFSET];
      newPixPos = 0;
      break;
    default:
      strip.setPixelColor(LED_COUNT - 1 + LED_OFFSET, color);
      for (uint8_t k = LED_COUNT_HALF - 1; k > 0; --k) px[k + LED_OFFSET] = px[k - 1 + LED_OFFSET];
      newPixPos = 0;
      mirrorPixels(px, gShiftDir == 2);
      delay(6);
      break;
  }
  strip.setPixelColor(newPixPos + LED_OFFSET, color);
}

// Effect 2: full white flash on beat, fades with audio level
void fullflash() {
  uint32_t rgb;
  if (gOnBeat) {
    e8_hue     = randomSync() * 257 + analogRead(MIC_PIN) * 10;
    e8_persSat = randomSync() / 4 + 192;
    rgb = 0xffffff;
  } else {
    uint16_t lum = (255 - MIN_LED_LUMA) * gPegel_smooth + MIN_LED_LUMA;
    rgb = strip.ColorHSV(e8_hue, e8_persSat, lum);
  }
  strip.fill(rgb);
}

// Effect 3: triwave interval
void interval() {
  for (uint8_t i = 0; i < LED_COUNT; i++) {
    float scale = 0.5f * triwave(gSpin2 / 200.f);
    int   mod   = i - (gBeatCounter % LED_COUNT);
    float val   = 0.5f + 0.5f * triwave(mod * scale);
    strip.setPixelColor(i + LED_OFFSET, getColor(val));
  }
}

// Effect 4: VU-meter style pegel display
void pegeleffect() {
  uint32_t color    = getColor(0.5f + gPegel_smooth / 2.f);
  uint32_t colorOff = getColor(0.1f);
  uint8_t  pm2      = gPegel_smooth * gRelativePegel * 255.f;
  for (uint8_t n = 0; n < LED_COUNT; ++n) {
    int      div   = ((n % 2) == 1 ? -2 : 2);
    int      pos   = LED_COUNT_HALF + (n + 1) / div;
    uint8_t  pegel = (255 * n) / (LED_COUNT - 1);
    uint32_t col   = pm2 >= pegel ? color : colorOff;
    strip.setPixelColor(pos, col);
  }
}

// Effect 5: half/quarter split bounce
void binkieEffect10() {
  float   beats = gBeatCounter % 2 == 0 ? 0.0f : 0.5f;
  uint8_t more  = 1 + (gBeatCounter / 8) % 2;
  for (uint8_t i = 0; i < LED_COUNT; i++) {
    float    val   = 0.45f + triwave(beats + 0.5f * gPegel_smooth * more + more * float(i) / LED_COUNT);
    uint32_t color = getColor(val);
    strip.setPixelColor(i + LED_OFFSET, color);
  }
}

float getValue2(float factor, float x) {
  float a0 = triwave(factor *  2.f  / 6.283185f + x);
  float a1 = triwave(factor * -1.1f / 6.283185f + x);
  float a2 = triwave(factor *  1.2f / 6.283185f + x);
  a2 *= a2;
  return a0 + a1 + a2;
}

// Effect 6: polynomial waveform, white flash on beat
void polynom() {
  for (uint16_t i = 0; i < LED_COUNT; i++) {
    float    v     = fabs(getValue2(gSpin2 * 0.15f, float(i) / float(LED_COUNT - 1))) * 0.75f;
    uint32_t color = getColor(v);
    strip.setPixelColor(i + LED_OFFSET, gOnBeat ? (uint32_t)WHITE_FLASH_COLOR : color);
  }
}

// Effect 7: alternating disco-blink
void discoBlink() {
  uint16_t on    = gBeatCounter % 2;
  float    light = gRelativePegel;
  if (gOnBeat) gShiftDir = randomSync();
  for (uint16_t i = 0; i < LED_COUNT; i++) {
    bool     showit = (on + i) % 2;
    float    aVal   = 0.4f + 0.1f * light;
    uint32_t color  = getColor(aVal + 0.5f * triwave(float(gShiftDir) / 128.f
                                + 0.6f * float(i) / (LED_COUNT - 1)));
    strip.setPixelColor(i + LED_OFFSET, showit ? color : 0);
  }
}

// Effect 8: glitter sparks
void glitzer() {
  if (gOnBeat) {
    hueshift = 40000;
    uint8_t pos = randomSync() % LED_COUNT;
    stars_buffer[pos] = (43690 + gBeatCounter) << 9;
  }
  uint8_t val = MIN_LED_LUMA + gPegel_smooth * (255.f - MIN_LED_LUMA);
  for (uint8_t h = 0; h < LED_COUNT; h++) {
    uint16_t hue   = stars_buffer[h] + hueshift;
    uint32_t color = strip.ColorHSV(hue, gOnBeat ? 100 : 255, val);
    strip.setPixelColor(h + LED_OFFSET, color);
  }
  hueshift = (uint16_t)max(0, (int)hueshift - 1000);
}

// ── Public interface ──────────────────────────────────────────────────────────

void classicInit() {
  gNOW          = millis();
  gLastBeatTime = gNOW;
  gLastPegel    = 0.f;
  gAmbient      = 0.f;
  gStoryPtr     = 0;
  gColorPtr     = 0;
  gPegel_smooth = 0.f;
  gSpin2        = 0.f;
  gDirection2   = 1.f;
  hueshift      = 0;
  memset(stars_buffer, 0, sizeof(stars_buffer));
  binkieEffect9_reset();
}

void classicTick() {
  strip.setBrightness(bright);  // master brightness for Classic
  gNOW = millis();

  // ── Audio sampling ─────────────────────────────────────────────────────────
  uint16_t minA = 1023, maxA = 0;
  for (uint8_t i = 0; i < RAW_BUFFER_SIZE; i++) {
    uint16_t aIN = analogRead(MIC_PIN);
    maxA = max(aIN, maxA);
    minA = min(aIN, minA);
  }
  uint16_t variation = maxA - minA;

  gLastPegel *= 0.9025f;
  gAmbient   *= 0.9959675f;

  float    newPegel = max((float)variation, gLastPegel);
  uint32_t timeDiff = gNOW - gLastBeatTime;
  uint8_t  beatInc  = 2 + uint8_t(gAmbient) / 4;
  gOnBeat = (newPegel > (gLastPegel + beatInc)) && (timeDiff > 333);

  if (gOnBeat) {
    gBeatCounter  = (gBeatCounter + 1) % BEATCOUNT_MAX;
    gLastBeatTime = gNOW;
    gTimeDif      = timeDiff;
  }

  gLastPegel     = newPegel;
  gAmbient       = max(gAmbient, newPegel);
  gRelativePegel = newPegel / max(gAmbient, MIN_AMBIENT_FLOOR);

  if (gOnBeat)  gDirection2  = gBeatCounter % 8 > 3 ? 1.f : -1.f;
  else          gDirection2 *= 0.98f;

  gPegel_smooth = min(1.f, 0.9f * gPegel_smooth + 0.1f * gRelativePegel);
  gSpin2       += gDirection2 * gPegel_smooth;

  // ── Effect dispatch ────────────────────────────────────────────────────────
  gEffect = gStoryPtr % STORY_COUNT;

  switch (gEffect) {
    case 0: spinner();              break;
    case 1: shiftRing(); delay(10); break;
    case 2: fullflash();            break;
    case 3: interval();             break;
    case 4: pegeleffect();          break;
    case 5: binkieEffect10();       break;
    case 6: polynom();              break;
    case 7: discoBlink();           break;
    case 8: glitzer();              break;
  }

  strip.show();
}
