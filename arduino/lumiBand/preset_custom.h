// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PRESET — Plays back uploaded effect matrices
//
// Timing:
//   Each row is shown for CUSTOM_ROW_MS  (0.5 s).
//   After CUSTOM_SLOT_MS (3 min) the next uploaded matrix starts.
//   Slots cycle endlessly through however many the app uploaded (customCount).
//
// Requires (declared in lumiBand.ino before this include):
//   Effect  effects[NUM_EFFECTS];
//   bool    effectLoaded[NUM_EFFECTS];
//   #define NUM_EFFECTS, NUM_ROWS, NUM_LEDS
//   void showRow(int slot, int row);
// ═══════════════════════════════════════════════════════════════════════════════
#pragma once

#define CUSTOM_ROW_MS  500UL       // 0.5 s per row
#define CUSTOM_SLOT_MS 180000UL    // 3 minutes per effect slot

static int  customCount        = 1;    // how many uploaded slots to cycle through
static int  customSlot         = 0;    // currently playing slot index (0..customCount-1)
static int  customRow          = 0;    // current row within the active slot
static bool customBounceForward = true;
static unsigned long customRowTick  = 0;  // timestamp of last row advance
static unsigned long customSlotTick = 0;  // timestamp of last slot advance

// ── Internal helpers ──────────────────────────────────────────────────────────

static void _customShowCurrent() {
  if (effectLoaded[customSlot]) showRow(customSlot, customRow);
}

static void _customAdvanceRow() {
  const bool bounce = (effects[customSlot].settings & 0x10) != 0;
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
  _customShowCurrent();
}

static void _customAdvanceSlot() {
  customSlot          = (customSlot + 1) % customCount;
  customRow           = 0;
  customBounceForward = true;
  customRowTick       = millis();   // reset row timer for the new slot
  _customShowCurrent();
}

// ── Public interface ──────────────────────────────────────────────────────────

// Called by the CMD handler when Custom mode is activated.
// count = number of uploaded effect slots to cycle through (1–NUM_EFFECTS).
void customInit(int count) {
  customCount         = constrain(count, 1, NUM_EFFECTS);
  customSlot          = 0;
  customRow           = 0;
  customBounceForward = true;
  customRowTick       = millis();
  customSlotTick      = millis();
  strip.setBrightness(255);   // dim() is applied inline by showRow()
  _customShowCurrent();
}

void customTick() {
  unsigned long now = millis();

  // After 3 minutes: advance to the next effect slot.
  if (now - customSlotTick >= CUSTOM_SLOT_MS) {
    customSlotTick = now;
    _customAdvanceSlot();
    return;   // skip row check this iteration
  }

  // Every 0.5 s: advance to the next row within the current slot.
  if (now - customRowTick >= CUSTOM_ROW_MS) {
    customRowTick = now;
    _customAdvanceRow();
  }
}
