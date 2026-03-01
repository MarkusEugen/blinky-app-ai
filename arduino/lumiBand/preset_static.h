// ═══════════════════════════════════════════════════════════════════════════════
// STATIC PRESET — Solid white, full brightness
// ═══════════════════════════════════════════════════════════════════════════════
#pragma once

static unsigned long staticLastDraw = 0;

void staticInit() {
  showSolid(255, 255, 255);   // showSolid applies dim() internally
  staticLastDraw = millis();
  strip.setBrightness(255);
}

void staticTick() {
  // Redraw at 10 Hz so brightness changes take effect promptly.
  unsigned long now = millis();
  if (now - staticLastDraw < 100) return;
  staticLastDraw = now;
  showSolid(255, 255, 255);
}
