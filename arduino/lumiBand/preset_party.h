// ═══════════════════════════════════════════════════════════════════════════════
// PARTY PRESET — Fast cycling rainbow colors
// ═══════════════════════════════════════════════════════════════════════════════
#pragma once

static uint16_t partyHue = 0;
static unsigned long partyLastTick = 0;

void partyInit() {
  partyHue     = 0;
  partyLastTick = millis();
  strip.setBrightness(255);
}

void partyTick() {
  unsigned long now = millis();
  if (now - partyLastTick < 20) return;   // ~50 fps
  partyLastTick = now;

  partyHue += 512;  // fast hue rotation

  for (int i = 0; i < NUM_LEDS; i++) {
    uint16_t hue = partyHue + (uint16_t)(i * 65536UL / NUM_LEDS);
    strip.setPixelColor(i, strip.ColorHSV(hue, 255, dim(255)));
  }
  strip.show();
}
