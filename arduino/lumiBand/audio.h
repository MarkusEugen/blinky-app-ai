// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO — shared microphone sampling
//
// Samples the mic every 20 ms and updates six globals that every mode can read:
//   gAmbient        — long-running ambient noise floor
//   gRelativePegel  — current level relative to ambient  (0..1)
//   gOnBeat         — true for exactly one tick per detected beat
//   gDirection2     — spin direction ±1, flips on beat
//   gPegel_smooth   — smoothed version of gRelativePegel
//   gSpin2          — accumulating phase value driven by audio energy
//
// Requires (declared in lumiBand.ino before this include):
//   #define MIC_PIN
//
// Include this file before any mode headers.
// Call audioInit() once before entering the main loop, then audioTick() every
// iteration of loop() before runModeTick().
// ═══════════════════════════════════════════════════════════════════════════════
#pragma once

#define RAW_BUFFER_SIZE   160
#define MIN_AMBIENT_FLOOR 8.f
#define BEATCOUNT_MAX     64

// ── Audio globals — written by audioTick(), read by all modes ─────────────────

bool     gOnBeat        = false;
uint8_t  gBeatCounter   = 0;
uint32_t gNOW           = 0;
uint32_t gTimeDif       = 0;
uint32_t gLastBeatTime  = 0;
float    gLastPegel     = 0.f;
float    gAmbient       = 0.f;
float    gRelativePegel = 0.f;
float    gDirection2    = 1.f;
float    gSpin2         = 0.f;
float    gPegel_smooth  = 0.f;

// Reset all audio state — call once on startup and whenever switching to
// Classic mode so beat detection starts from a clean baseline.
void audioInit() {
  gOnBeat        = false;
  gBeatCounter   = 0;
  gNOW           = millis();
  gTimeDif       = 0;
  gLastBeatTime  = gNOW;
  gLastPegel     = 0.f;
  gAmbient       = 0.f;
  gRelativePegel = 0.f;
  gDirection2    = 1.f;
  gSpin2         = 0.f;
  gPegel_smooth  = 0.f;
}

// Sample the microphone and update all audio globals.
// Called unconditionally — rate-limiting is handled by the caller in loop().
void audioTick() {
  gNOW = millis();

  // ── Raw mic sampling ────────────────────────────────────────────────────────
  uint16_t minA = 1023, maxA = 0;
  for (uint8_t i = 0; i < RAW_BUFFER_SIZE; i++) {
    uint16_t aIN = analogRead(MIC_PIN);
    maxA = max(aIN, maxA);
    minA = min(aIN, minA);
  }
  uint16_t variation = maxA - minA;

  // ── Level + beat detection ──────────────────────────────────────────────────
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

  // ── Derived animation state ──────────────────────────────────────────────────
  if (gOnBeat) gDirection2  = gBeatCounter % 8 > 3 ? 1.f : -1.f;
  else         gDirection2 *= 0.98f;

  gPegel_smooth = min(1.f, 0.9f * gPegel_smooth + 0.1f * gRelativePegel);
  gSpin2       += gDirection2 * gPegel_smooth;
}
