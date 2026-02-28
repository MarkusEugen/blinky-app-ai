// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PRESET — Plays back uploaded effect matrices
//
// Sound-reactive modes (settings byte bitmask):
//   SOUND_ORGEL      (0x01)  Scale each LED luma by audio level every tick
//   SOUND_FLASH_BEAT (0x02)  Flash entire row white for one tick on every beat
//   SOUND_NEXT_BEAT  (0x04)  Advance row on beat instead of on a timer
//   SOUND_PEGEL      (0x08)  Select row by audio level (ignores row timer)
//   LOOP_BOUNCE      (0x10)  Bounce instead of loop when advancing rows
//
// Modes can be combined freely.  Priority when multiple modes are active:
//   Pegel   → overrides row selection (Next on Beat is ignored for row timing)
//   Flash   → overrides pixel output on beat (applied after Orgel luma scaling)
//   Orgel   → modifies pixel luma continuously
//
// Timer-based timing (used when neither Pegel nor Next on Beat is set):
//   Row advances every effects[slot].rowMs ms (20–1000, default 500)
//   Slot advances every CUSTOM_SLOT_MS (3 min)
//
// Requires (declared in lumiBand.ino before this include):
//   Effect  effects[NUM_EFFECTS];  bool effectLoaded[NUM_EFFECTS];
//   uint8_t bright;
//   #define NUM_EFFECTS, NUM_ROWS, NUM_LEDS
//   void showRow(int slot, int row);  uint8_t dim(uint8_t v);
//   audio.h included  (gOnBeat, gRelativePegel)
//   preset_classic.h included before this  (MIN_LED_LUMA)
// ═══════════════════════════════════════════════════════════════════════════════
#pragma once

#define SOUND_ORGEL       0x01
#define SOUND_FLASH_BEAT  0x02
#define SOUND_NEXT_BEAT   0x04
#define SOUND_PEGEL       0x08
#define LOOP_BOUNCE       0x10

#define CUSTOM_SLOT_MS 180000UL    // 3 minutes per effect slot

static int  customCount         = 1;
static int  customSlot          = 0;
static int  customRow           = 0;
static bool customBounceForward = true;
static unsigned long customRowTick  = 0;
static unsigned long customSlotTick = 0;
static uint8_t customLastBright     = 255;

// ── Internal helpers ──────────────────────────────────────────────────────────

// Render customRow of customSlot, applying active sound-reactive modes.
//
// Flash on Beat  — overrides everything: full-white row for one audio tick.
// Orgel          — scales each LED's RGB by the current pegel luma factor.
// Default        — showRow() at master brightness.
static void _customRender() {
  if (!effectLoaded[customSlot]) return;

  uint8_t settings = effects[customSlot].settings;

  // Flash on Beat: one tick of solid white, overrides all colour data.
  if ((settings & SOUND_FLASH_BEAT) && gOnBeat) {
    for (int i = 0; i < NUM_LEDS; i++)
      strip.setPixelColor(i, dim(255), dim(255), dim(255));
    strip.show();
    return;
  }

  // Orgel: multiply each stored LED colour by the audio-driven luma factor.
  // Formula: luma = (255 - MIN_LED_LUMA) × gRelativePegel + MIN_LED_LUMA
  // At silence (gRelativePegel = 0) → dim glow at MIN_LED_LUMA / 255 of stored colour.
  // At peak    (gRelativePegel = 1) → full stored colour.
  if (settings & SOUND_ORGEL) {
    uint8_t luma = (uint8_t)((255.f - MIN_LED_LUMA) * gRelativePegel + MIN_LED_LUMA);
    for (int i = 0; i < NUM_LEDS; i++) {
      uint16_t c = effects[customSlot].rgb565[customRow][i];
      uint8_t r = ((c >> 11) & 0x1F) * 8;
      uint8_t g = ((c >> 5)  & 0x1F) * 8;
      uint8_t b = ( c        & 0x1F) * 8;
      r = (uint16_t)r * luma / 255;
      g = (uint16_t)g * luma / 255;
      b = (uint16_t)b * luma / 255;
      strip.setPixelColor(i, dim(r), dim(g), dim(b));
    }
    strip.show();
    return;
  }

  // Default: show stored row colours at master brightness.
  showRow(customSlot, customRow);
}

// Advance to the next row (loop or bounce) and render.
static void _customAdvanceRow() {
  const bool bounce = (effects[customSlot].settings & LOOP_BOUNCE) != 0;
  if (!bounce) {
    customRow = (customRow + 1) % NUM_ROWS;
  } else {
    if (customBounceForward) {
      if (customRow >= NUM_ROWS - 1) { customBounceForward = false; customRow = NUM_ROWS - 2; }
      else                            { customRow++; }
    } else {
      if (customRow <= 0)             { customBounceForward = true;  customRow = 1; }
      else                            { customRow--; }
    }
  }
  _customRender();
}

// Advance to the next effect slot and render.
static void _customAdvanceSlot() {
  customSlot          = (customSlot + 1) % customCount;
  customRow           = 0;
  customBounceForward = true;
  customRowTick       = millis();
  _customRender();
}

// ── Public interface ──────────────────────────────────────────────────────────

void customInit(int count) {
  customCount         = constrain(count, 1, NUM_EFFECTS);
  customSlot          = 0;
  customRow           = 0;
  customBounceForward = true;
  customRowTick       = millis();
  customSlotTick      = millis();
  customLastBright    = bright;
  _customRender();
}

void customTick() {
  unsigned long now      = millis();
  uint8_t       settings = effectLoaded[customSlot] ? effects[customSlot].settings : 0;

  // ── Pegel mode: row continuously driven by audio level ───────────────────
  // Row = round(gRelativePegel × NUM_ROWS), clamped to [0, NUM_ROWS-1].
  // Slot still advances on the 3-minute timer.
  if (settings & SOUND_PEGEL) {
    customRowTick = now;  // keep row timer reset — same reason as SOUND_NEXT_BEAT
    if (now - customSlotTick >= CUSTOM_SLOT_MS) {
      customSlotTick = now;
      _customAdvanceSlot();
      return;
    }
    customRow = constrain((int)round(gRelativePegel * NUM_ROWS), 0, NUM_ROWS - 1);
    _customRender();   // also handles Flash on Beat / Orgel inside the render
    return;
  }

  // ── Next on Beat: row advances only on detected beats ────────────────────
  // Audio-reactive modes (Orgel, Flash on Beat) still render every tick.
  // Slot still advances on the 3-minute timer.
  if (settings & SOUND_NEXT_BEAT) {
    customRowTick = now;  // keep row timer reset — not used in this mode, but
                          // prevents a stale gap from firing instantly if the
                          // effect later reverts to timer-based advance.
    if (now - customSlotTick >= CUSTOM_SLOT_MS) {
      customSlotTick = now;
      _customAdvanceSlot();
      return;
    }
    if (gOnBeat) {
      _customAdvanceRow();   // advances row then renders (handles Orgel / Flash)
    } else {
      _customRender();       // keeps Orgel luma and Flash on Beat responsive
    }
    return;
  }

  // ── Timer-based (default): advance row every 0.5 s ───────────────────────
  if (now - customSlotTick >= CUSTOM_SLOT_MS) {
    customSlotTick = now;
    _customAdvanceSlot();
    return;
  }

  unsigned long rowMs = (effectLoaded[customSlot] && effects[customSlot].rowMs >= 20)
                        ? effects[customSlot].rowMs : 500UL;
  if (now - customRowTick >= rowMs) {
    customRowTick = now;
    _customAdvanceRow();
    return;
  }

  // In timer mode, re-render if brightness changed or a sound mode needs
  // per-tick updates (Orgel tracks audio continuously; Flash on Beat reacts
  // immediately on the beat tick even mid-row).
  bool needRedraw = (bright != customLastBright)
                 || (settings & (SOUND_ORGEL | SOUND_FLASH_BEAT));
  if (needRedraw) {
    customLastBright = bright;
    _customRender();
  }
}
