// ═══════════════════════════════════════════════════════════════════════════════
// LAVA PRESET — Slow red-orange pulses
// ═══════════════════════════════════════════════════════════════════════════════
#pragma once

static float lavaPhase  = 0.f;
static unsigned long lavaLastTick = 0;

void lavaInit() {
  lavaPhase   = 0.f;
  lavaLastTick = millis();
  strip.setBrightness(255);
}

void lavaTick() {
  unsigned long now = millis();
  if (now - lavaLastTick < 30) return;   // ~33 fps
  lavaLastTick = now;

  lavaPhase += 0.04f;
  if (lavaPhase > 2.f * 3.14159f) lavaPhase -= 2.f * 3.14159f;

  for (int i = 0; i < NUM_LEDS; i++) {
    float offset = lavaPhase + i * (3.14159f / NUM_LEDS);
    float wave   = 0.5f + 0.5f * sin(offset);           // 0..1
    uint8_t r    = dim(200 + (uint8_t)(wave * 55.f));   // 200–255 red
    uint8_t g    = dim((uint8_t)(wave * 60.f));          // 0–60 orange tint
    strip.setPixelColor(i, r, g, 0);
  }
  strip.show();
}
