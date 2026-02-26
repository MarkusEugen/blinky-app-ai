// ═══════════════════════════════════════════════════════════════════════════════
// DIM PRESET — Soft warm candle glow
// ═══════════════════════════════════════════════════════════════════════════════
#pragma once

static float dimPhase    = 0.f;
static unsigned long dimLastTick = 0;

void dimInit() {
  dimPhase   = 0.f;
  dimLastTick = millis();
}

void dimTick() {
  unsigned long now = millis();
  if (now - dimLastTick < 50) return;   // ~20 fps — slow, gentle
  dimLastTick = now;

  dimPhase += 0.015f;
  if (dimPhase > 2.f * 3.14159f) dimPhase -= 2.f * 3.14159f;

  for (int i = 0; i < NUM_LEDS; i++) {
    float offset = dimPhase + i * (3.14159f / NUM_LEDS);
    float wave   = 0.75f + 0.25f * sin(offset);        // 0.75..1.0 — subtle flicker
    uint8_t r    = dim((uint8_t)(139.f * wave));        // warm amber
    uint8_t g    = dim((uint8_t)( 90.f * wave));
    uint8_t b    = dim((uint8_t)( 20.f * wave));
    strip.setPixelColor(i, r, g, b);
  }
  strip.show();
}
