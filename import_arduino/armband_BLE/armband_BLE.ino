/*************************************************************************

   CONFIDENTIAL
   __________________

    [2023] - WAVELIGHTS - Markus E. Loeffler
    All Rights Reserved.

   NOTICE:  All information contained herein is, and remains
   the property of Markus E. Loeffler and suppliers,
   if any.  The intellectual and technical concepts contained
   herein are proprietary to Markus E. Loeffler
   and suppliers and may be covered by U.S. and Foreign Patents,
   patents in process, and are protected by trade secret or copyright law.
   Dissemination of this information or reproduction of this material
   is strictly forbidden unless prior written permission is obtained
   from Markus E. Loeffler.
*/
#define LED_COUNT 15
#define LED_OFFSET 0
#define LED_BRIGHNESS 16

#ifdef __AVR_ATtiny85__
#define tinyblink 1
#endif

#ifdef tinyblink
// ATTiny85 --------------------------- ATTiny85
#define RAW_BUFFER_SIZE 160
#define auto_advance 1
//int NOISE_FLOOR = 0;
#define LED_PIN 1
#define MIC_PIN A1
#define POTI_PIN A3
#else
// Nano --------------------------- Nano
#define RAW_BUFFER_SIZE 160
// #define auto_advance 1
//int NOISE_FLOOR = 0;
#define doprint 1
#define measure_fps 1
#define LED_PIN 12
#define MIC_PIN A3
#define POTI_PIN A4
#endif

#define MIN_AMBIENT_FLOOR 8.f
#define BEAT_INCREASE 2
#define AUTO_COLOR_TIMER 262144  // 4,3 m
#define AUTO_STORY_TIMER 262144

//#define decay 0.95f;

#include <Adafruit_NeoPixel.h>


#define LED_COUNT_HALF (LED_COUNT / 2)
#define RANDOM_ARRAY_SIZE 8192
#define BEATCOUNT_MAX 64
#define COLOR_COUNT 8
#define STORY_COUNT 9
#define STORY_START 0  // STORY_START
#define WHITE_FLASH_COLOR 0xffffaf
#define WHITE_FLASH_COLOR_SHIFT 0xafaf6f
#define pi 3.141592653589793f
#define MIN_LED_LUMA 25

Adafruit_NeoPixel strip(LED_COUNT + LED_OFFSET, LED_PIN, NEO_GRB + NEO_KHZ800);

typedef struct {
  uint8_t r;
  uint8_t g;
  uint8_t b;
} pixFormat;

#ifdef measure_fps
unsigned long lastTimeFPS = 0;
unsigned long frame = 0;
#endif

bool gOnBeat;
uint8_t gBeatCounter;
uint32_t gNOW = 0;
uint8_t gStoryPtr;
uint8_t gColorPtr;
uint32_t gTimeDif;
uint8_t gEffect;
uint32_t gLastBeatTime;
float gLastPegel, gAmbient;

uint8_t randomSync() {
  uint16_t index = gNOW % RANDOM_ARRAY_SIZE;
  return pgm_read_byte(index);
}

float fract(float x) {
  return x - floor(x);
}

float triwave(float v)  // input 0..1 output -1..1
{
  float x = 2.f * v;
  float res = 1.0f - 4.f * fabs(0.5f - fract(0.5f * x + 0.25f));
  return res;
}

float gRelativePegel;
float gDirection2 = 1.f;
float gSpin2 = 0.f;
float gPegel_smooth = 0.;
uint16_t stars_buffer[LED_COUNT];
const uint8_t gManuColor = 0;

uint32_t getColor(float valu) {
  valu = min(1.0f, max(0.f, valu));
  valu *= valu;
  uint16_t hue = gNOW >> 1;
  uint8_t sat = gOnBeat ? 180 : 255;
  //  uint8_t val = valu * 255.f;
  uint8_t  val = MIN_LED_LUMA + valu * 230.f;

  // --------------------- color scheme
  uint32_t color;
  if (gManuColor == 0) {
    switch (gColorPtr) {
      case 0:  //luma ramp + sat shift
        {
          hue += valu * 30000 + gPegel_smooth * 40000;
          sat = sat - 35.f * valu;
          //          val = val <= 5 ? 10 : 50.f + 205.f * valu;
          break;
        }
      case 1:  // just red
        hue = 64000 + val * 30;
        break;
      case 2:  // hue + 180 degree
        {
          hue += val * 137;  //valu * 35000.f;
          //          val = 100.f + 155.f * valu;
          break;
        }
      case 3:  // luma ramp light blue in the middle
        {
          sat = 255;
          if (val > 150)
            hue += 32768;
          else if (val > 85) {
            sat = gRelativePegel * gRelativePegel * 255;
            sat = 255 - sat;
          }
          break;
        }
      case 4:  //--------FLASH dissolve to black----------------------------------------------------
        {
          sat = 255;
          hue += gRelativePegel * 255.f * 150;
          break;
        }
      case 5:         // just blue
        hue = gNOW / 2 - val * 50;
        break;
      case 6:  // fixed reds at upper end
        {
          hue = (val >= 128 ? 0 : hue * (1.f - valu));
          sat = sat - 60.f + 60.f * valu;
          //          val = 128 + (val >> 1);
          break;
        }
      case 7:
        float d = valu + gSpin2 / 40.f;
        hue +=  triwave(d) * 10000;
        sat = 200 + triwave(valu + d) * 55;
        break;
    }
    color = strip.ColorHSV(hue, sat, val);
  } 
  return color;
}


uint8_t pixelVal(int x)
{
  return  x < 0 ? stars_buffer[LED_COUNT + x] : stars_buffer[x % LED_COUNT];
}
/*
  void blur()
  {
  for (int h = 0; h < LED_COUNT; h++)
  {
    int sum = pixelVal(h - 2);
    sum += pixelVal(h - 1);
    sum += pixelVal(h);
    sum += pixelVal(h + 1);
    sum += pixelVal(h + 2);
    stars_buffer[h] = max(0, (sum - 3) / 5);
  }
  }

  void melt()
  {
  if (gOnBeat)
  {
    int dotsize = gPegel_smooth * LED_COUNT ;
    int dotpos = randomSync() * LED_COUNT / 256;

    for (int h = dotpos - dotsize / 2; h <  dotpos + dotsize / 2; h++)
    {
      if ( h < 0 || h >= LED_COUNT)
        continue;
      stars_buffer[h] = 255;
    }
  }
  else
    blur();

  for (int h = 0; h < LED_COUNT; h++)
  {
    uint32_t color = getColor( stars_buffer[h] / 255.f);
    strip.setPixelColor(h, color);
  }
  strip.fill(gOnBeat ? 0xffffff : getColor( gRelativePegel));
  }
*/

float modf(float x, float y)
{
  return x - y * floor(x / y);
}

/*
  float omega1 = 2.f;
  float omega2 = 2.5f;
  float phi1 = 0;
  float phi2 = pi / 4.;
  float k = 0.5;

  float trisine(float v)  // 0 - 2*PI, output -1..1
  {
  float x = v / (2 * pi);
  return triwave(x);
  }

  float theta1(float t)
  {
  return pi / 3.f * trisine(omega1 * t + phi1);
  }

  float theta2(float t)
  {
  return  pi / 3.f * trisine(omega2 * t + phi2 + k * trisine(theta1(t)));
  }

  void blackDot2()
  {
  //  uint16_t luma =  (1. - gPegel_smooth) * 63.;
  uint32_t color = gOnBeat ? 0xffffff : getColor( gRelativePegel);
  strip.fill(color);
  float t = gSpin2 / 10.f;
  float x1 =  1 + trisine(theta1(t));
  int x1i = x1 * (LED_COUNT / 2 - 1);
  float x2 = x1 + 1 + trisine(theta2(t));
  int x2i = x2 * (LED_COUNT / 2 - 1);

  //  int16_t v = fabs(x2) * (LED_COUNT - 1);
  //  strip.setPixelColor(v , 0 );
  for (uint8_t i = min(x1i, x2i); i <= max(x1i, x2i); ++i)
  {
    //    strip.setPixelColor((v + i ) % LED_COUNT , 0x010101 * luma );
    strip.setPixelColor((i ) % LED_COUNT , 0 );
  }

  //    int16_t v = int(fabs(getValue2(gSpin2 * 0.02f, (float)gNOW / 10000.f) * (LED_COUNT - 1.f))) % LED_COUNT;
  //    uint8_t f = 3 * abs((LED_COUNT - 1) / 2 - v) / ((LED_COUNT - 1) / 2);
  //    //  f *= f;
  //    //  Serial.println(f);
  //    uint8_t sizeP = 3 - f;
  //    for (uint8_t i = 0; i <= sizeP; ++i)
  //    {
  //    //    strip.setPixelColor((v + i ) % LED_COUNT , 0x010101 * luma );
  //    strip.setPixelColor((v + i ) % LED_COUNT , 0 );
  //    }

  }
*/

void interval()
{
  for (uint8_t i = 0; i < LED_COUNT; i++)
  {
    float scale = 0.5f * triwave(gSpin2 / 200.f);
    int mod = i - (gBeatCounter % LED_COUNT);
    float val = 0.5f + 0.5f * triwave(mod * scale);
    strip.setPixelColor(i + LED_OFFSET, getColor(val ));
  }
}

#define maxMem 2
float e9_posMem[maxMem];
uint16_t e9_bpmMem[maxMem];
int8_t e9_dirMem[maxMem];
unsigned long e9_lastSpin;

void spin(float& pos, int16_t bpm, uint16_t timeDiff)
{
  float realPos = modf(pos + (float)(LED_COUNT * timeDiff ) / (float)bpm , LED_COUNT);
  //  Serial.print((LED_COUNT * digits * timeDiff ) / (int)bpm); Serial.print(' ');
  //  Serial.print(pos); Serial.print(' ');
  //  Serial.print(bpm); Serial.print(' ');
  //  Serial.print(timeDiff); Serial.print(' ');
  //  Serial.println();

  //  realPos += realPos < 0 ? LED_COUNT : -LED_COUNT;
  realPos += realPos < 0 ? LED_COUNT : 0;
  pos = realPos;
  uint8_t pixPos = realPos;
  stars_buffer[pixPos % LED_COUNT] = 255;
}

void binkieEffect9_reset()  // 4x spinner
{
  e9_lastSpin = gNOW;
  for (uint16_t  i = 0; i < maxMem; i++)
  {
    e9_posMem[i] = 0;
    e9_bpmMem[i] = 500;
    e9_dirMem[i] = (i % 2 == 0 ? 1 : -1);
  }
}

void spinner()
{
  bool over = gNOW - gLastBeatTime > 10000;
  if (gOnBeat)
  {
    e9_bpmMem[randomSync() % maxMem] = gTimeDif;
  }

  for (uint8_t i = 0; i < LED_COUNT; i++)
    stars_buffer[i] = 0;

  uint32_t color;
  for ( uint8_t mem = 0; mem < maxMem; mem++)
  {
    if (over)
    {
      e9_bpmMem[mem] *= 2;
      gLastBeatTime = gNOW ;
    }

    spin(e9_posMem[mem],
         e9_dirMem[mem] * e9_bpmMem[mem] ,
         gNOW - e9_lastSpin );
    //         Serial.print("\t\t\t");
  }
  //    Serial.println();

  for (uint8_t i = 0; i < LED_COUNT; i++)
  {
    //    bool lumaTrig = stars_buffer[i] < 5;
    //    float light = lumaTrig ? e9_shiftPos : stars_buffer[i];
    color = getColor(stars_buffer[i] > 0 ? gRelativePegel * 0.3 + 0.7f : 0.3f );
    strip.setPixelColor(i + LED_OFFSET, color);
  }
  e9_lastSpin = gNOW;
}

void binkieEffect10()  //  half/quarter split bounce
{
  uint32_t color;
  //  beats += gBeatCounter % 2 == 0 ? 0.05f : -0.05f;
  //  beats = min(0.5f, max(0.f, beats));
  float beats = gBeatCounter % 2 == 0 ? 0.0f : 0.5f;
  uint8_t more = 1 + (gBeatCounter / 8) % 2;
  for (uint8_t i = 0; i < LED_COUNT; i++) {
    float val = 0.45f + triwave(beats + 0.5f * gPegel_smooth * more + more * float(i) / LED_COUNT);
    color = getColor(val);

    strip.setPixelColor(i + LED_OFFSET, color);
  }
}

float getValue2(float factor, float x) {
  //  x = x * 6.283185f;
  float a0 = triwave(factor * 2.f / 6.283185 + x);
  float a1 = triwave(factor * -1.1f / 6.283185 + x);
  float a2 = triwave(factor * 1.2f / 6.283185 + x);
  a2 *= a2;
  //  float a3 = trisine(factor * -1.3f + x);
  //  a3 = a3 * a3 * a3;
  //  float y = a0 + a1 + a2 + a3;
  float y = a0 + a1 + a2;
  return y;
}

void polynom() {
  for (uint16_t i = 0; i < LED_COUNT; i++) {
    float v = fabs(getValue2(gSpin2 * 0.15f, float(i) / float(LED_COUNT - 1))) * 0.75;
    //    v = v > 0.f ? v * 0.75f : v * -0.75f;
    uint32_t color = getColor(v);
    strip.setPixelColor(i + LED_OFFSET, gOnBeat ? WHITE_FLASH_COLOR : color);
  }
}

void mirrorPixels(pixFormat* pArray, bool quart) {

  if (quart)
    for ( uint8_t i = 0; i < LED_COUNT / 4; i++)
    {
      uint8_t half = LED_COUNT / 2 - 2 - i;
      pArray[half + LED_OFFSET].r = pArray[i + LED_OFFSET].r;
      pArray[half + LED_OFFSET].g = pArray[i + LED_OFFSET].g;
      pArray[half + LED_OFFSET].b = pArray[i + LED_OFFSET].b;
    }
  for (uint8_t i = 0; i < LED_COUNT_HALF; i++) {
    // ###  use for even led count:
    //    uint8_t half = LED_COUNT - 1 - i;
    uint8_t half = LED_COUNT - 2 - i;
    //    Serial.print(half); Serial.print(' '); Serial.println(i);
    pArray[half + LED_OFFSET].r = pArray[i + LED_OFFSET].r;
    pArray[half + LED_OFFSET].g = pArray[i + LED_OFFSET].g;
    pArray[half + LED_OFFSET].b = pArray[i + LED_OFFSET].b;
  }
}

//void pegeleffect() {
//  pixFormat* px = (pixFormat*)strip.getPixels();
//
//  uint32_t color = getColor(0.5 + gRelativePegel / 2.f);
//  uint32_t colorOff = getColor(0.1f);
//  uint16_t pm2 = gPegel_smooth * gPegel_smooth * 255.f;
//
//  for (uint8_t n = 0; n < LED_COUNT / 2; ++n) {
//    uint8_t pegel = (255 * n) / (LED_COUNT / 2 - 1);
//    uint32_t col = pm2 >= pegel ? color : colorOff;
//    strip.setPixelColor(n + LED_OFFSET, col);
//  }
//  mirrorPixels(px, false);
//}

uint16_t e8_persSat;
uint16_t e8_hue;
void fullflash()
{
  uint32_t rgb;
  if (gOnBeat)
  {
    e8_hue = randomSync() * 257 + analogRead(MIC_PIN) * 10;
    e8_persSat = randomSync() / 4 + 192;
    rgb = 0xffffff;
  }
  else
  {
    if (gManuColor == 0)
    {
      uint16_t lum =  (255 - MIN_LED_LUMA) * gPegel_smooth + MIN_LED_LUMA;
      rgb = strip.ColorHSV(e8_hue, e8_persSat, lum );
    }
    else
      rgb = getColor(gRelativePegel);
  }

  strip.fill(rgb);
}

void pegeleffect() {
  uint32_t color = getColor(0.5 + gPegel_smooth / 2.f);
  uint32_t colorOff = getColor(0.1f);
  uint8_t pm2 = gPegel_smooth * gRelativePegel * 255.f;

  for (uint8_t n = 0; n < LED_COUNT; ++n) {

    int div = ((n % 2) == 1 ? -2 : 2);
    int pos = LED_COUNT_HALF + (n + 1) / div;
    uint8_t pegel = (255 * n) / (LED_COUNT - 1);
    uint32_t col = pm2 >= pegel ? color : colorOff;
    strip.setPixelColor(pos, col);
  }
}

uint8_t gShiftDir = 0;

void discoBlink() {
  uint16_t on = gBeatCounter % 2;
  float light = gRelativePegel;
  if (gOnBeat)
    gShiftDir = randomSync();

  for (uint16_t i = 0; i < LED_COUNT; i++) {
    bool showit = (on + i) % 2;
    float aVal = 0.4f + 0.1f * light;
    uint32_t color = getColor(aVal + 0.5f * triwave(float(gShiftDir) / 128.f +
                              0.6f * float(i) / (LED_COUNT - 1)));
    strip.setPixelColor(i + LED_OFFSET, showit ? color : 0);
  }
}

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
      {
        for (uint8_t k = 0; k < LED_COUNT - 1; ++k)
          px[k + LED_OFFSET] = px[k + 1 + LED_OFFSET];
        newPixPos = LED_COUNT - 1;
      }
      break;
    case 1:
      {
        for (uint8_t k = LED_COUNT - 1; k > 0; --k)
          px[k + LED_OFFSET] = px[k - 1 + LED_OFFSET];
        newPixPos = 0;
      }
      break;
    default:
      {
        strip.setPixelColor(LED_COUNT - 1 + LED_OFFSET, color);
        for (uint8_t k = LED_COUNT_HALF - 1; k > 0; --k)
          px[k + LED_OFFSET] = px[k - 1 + LED_OFFSET];
        newPixPos = 0;
        mirrorPixels(px, gShiftDir == 2);
        delay(6);
      }
      break;
  }
  strip.setPixelColor(newPixPos + LED_OFFSET, color);
}

uint16_t hueshift;
void glitzer() {
  if (gOnBeat) {
    hueshift = 40000;
    // hueshift = (hueshift < 1000) ? 40000 : hueshift;
    uint8_t pos = randomSync() % LED_COUNT;
    stars_buffer[pos] = 43690 + gBeatCounter << 9;
    // stars_buffer[pos] = analogRead(MIC_PIN) << 10;
  }
  // uint8_t val = 10 + gRelativePegel * 245.f;
  uint8_t val = MIN_LED_LUMA + gPegel_smooth * (255.f - MIN_LED_LUMA);
  for (uint8_t h = 0; h < LED_COUNT; h++) {
    // uint16_t hue = stars_buffer[h] + gSpin2;
    uint32_t color;
    uint16_t hue = stars_buffer[h] + hueshift;
    if (gManuColor == 0)
      color = strip.ColorHSV(hue, gOnBeat ? 100 : 255, val);
    else {
      //      uint16_t v = (hue >> 8) * val;
      //      color = getColor(float(v) / 65535.f);
      color = getColor(max(0.25f, gPegel_smooth) * hue / 65535.f);
    }
    strip.setPixelColor(h + LED_OFFSET, color);
  }
  hueshift = max(0, hueshift - 1000);
}
// Service routine called by a timer interrupt

void showcolor() {
  for (uint8_t i = 0; i < LED_COUNT; i++) {
    uint32_t color = getColor(float(i) / (LED_COUNT - 1));
    strip.setPixelColor(i + LED_OFFSET, color);
  }
}

//----------------------------------- setup

void setup() {
#ifdef doprint
  Serial.begin(115200);
#endif
  pinMode(POTI_PIN, INPUT_PULLUP);
  strip.begin();
  strip.brightness = LED_BRIGHNESS;
  binkieEffect9_reset();
}

int minLuma = 0;

//----------------------------------- loop
void loop() {
  uint32_t tt = millis();
  // timeSpent += tt - gNOW;
  gNOW = tt;

#ifndef tinyblink
  if (Serial.available() > 0) {
    int inByte = Serial.read();
    Serial.print("key: ");

    if (inByte == 'd') {
      gStoryPtr += 1;
      Serial.println(gStoryPtr);
    } else if (inByte == 'c') {
      gStoryPtr -= 1;
      Serial.println(gStoryPtr);
    } else if (inByte == 's') {
      gColorPtr += 1;
      Serial.println(gColorPtr);
    } else if (inByte == 'x') {
      gColorPtr -= 1;
      Serial.println(gColorPtr);
    }
    else if (inByte == 'a') {
      minLuma += 1;
      Serial.println(minLuma);
    } else if (inByte == 'z') {
      minLuma -= 1;
      Serial.println(minLuma);
    }
  }
#endif

  //------------------------- ------------------------- audio block -------------------------

  //#ifdef tinyblink
  uint16_t minA = 1023;
  uint16_t maxA = 0;
  for (uint8_t i = 0; i < RAW_BUFFER_SIZE; i++) {
    uint16_t aIN = analogRead(MIC_PIN);
    maxA = max(aIN, maxA);
    minA = min(aIN, minA);
  }
  uint16_t variation = maxA - minA;

#ifndef tinyblink
  // variation = variation <= 2 ? 0 : variation - 2;
#endif
  //  if (gAmbient < 1.5f) {
  //    variation = 4;
  //#ifndef tinyblink
  //    Serial.print("tick ");
  //#endif
  //  }

  //  for (uint8_t i = 0; i < 2; i++)
  //  {
  gLastPegel *= 0.9025f;
  gAmbient *= 0.9959675f;  //0.9979817f
  //  }

  float newPegel = max(variation, gLastPegel);
  uint32_t timeDiff = gNOW - gLastBeatTime;
  uint8_t beatInc = 2 + uint8_t(gAmbient) / 4;
  gOnBeat = newPegel > (gLastPegel + beatInc) && timeDiff > 333 ? true : false;

  if (gOnBeat)  // || timeDiff > 12000)  // auto beat every 12s
  {
    gBeatCounter = ++gBeatCounter % BEATCOUNT_MAX;
    gLastBeatTime = gNOW;
    gTimeDif = timeDiff;
  }

  gLastPegel = newPegel;

  gAmbient = max(gAmbient, newPegel);
  gRelativePegel = newPegel / max(gAmbient, MIN_AMBIENT_FLOOR);

  //-------------------------  gBrightness gBrightness gBrightness gBrightness
  //  uint16_t inVal = max(0, (gBrightEEPROM) - 6);
  //  //  int inVal = gBrightEEPROM;
  //  inVal *= inVal;
  //  inVal = inVal / 165;

  if (gOnBeat) {
    gDirection2 = gBeatCounter % 8 > 3 ? 1. : -1.f;
  } else {
    gDirection2 *= 0.98f;
  }

  gPegel_smooth = min(1.f, 0.9f * gPegel_smooth + 0.1f * gRelativePegel);
  gSpin2 += gDirection2 * gPegel_smooth;

  //------------------------- ------------------------- scheduling -------------------------

#ifdef auto_advance
  gStoryPtr =  STORY_START + (gNOW / AUTO_STORY_TIMER);
  gColorPtr = ( STORY_START + (gNOW / AUTO_COLOR_TIMER)) % COLOR_COUNT;
#endif
  gEffect = gStoryPtr % STORY_COUNT;
  //  gEffect = 1;

  // ---- effect blend logic end
  uint32_t color;

  switch (gEffect) {
    case 0:
      spinner();
      // showcolor();
      break;
    case 1:
      shiftRing();  // 26 fps
      delay(10);
      break;
    case 2:
      fullflash();
      break;
    case 3:
      interval();  // 65 fps
      break;
    case 4:
      pegeleffect();  // 65 fps
      break;
    case 5:
      binkieEffect10();  //83 fps
      break;
    case 6:
      polynom();  // 63 fps
      break;
    case 7:          // 6
      discoBlink();  // 80 fps
      break;
    case 8:  //
      glitzer();
      break;
  }

  //  strip.fill(getColor((float)minLuma/255.f));
  //  showcolor();
  strip.show();

#ifdef measure_fps
  frame++;
  if (frame >= 200) {
    Serial.print(timeDiff);
    Serial.print("\t");
    Serial.print(gAmbient);
    //    Serial.print("\n");
    //    Serial.print(float(timeSpentCnt)/float(frame));
    Serial.print("\t");
    Serial.print(gColorPtr);
    Serial.print("\t");
    Serial.print(gStoryPtr);
    Serial.print("\t");
    Serial.println(1000. * float(frame) / float((gNOW - lastTimeFPS)));
    frame = 0;
    //    timeSpentCnt = 0;
    lastTimeFPS = gNOW;
    //    gFindMax = 0.f;
    //    gFindMin = 1.f;
  }
#endif
}
