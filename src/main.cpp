/**
 * NixieClock 
 * 
 * An Arduino Sketch for multiplexing 4 NIXIE tubes to show the 
 * current time.
 * The time is read from a DS1307 RTC chip. 
 * 
 * by Andreas Tacke (at@mail.fiendie.net).
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

// Increase i2C frequency
// #ifndef TWI_FREQ
// #define TWI_FREQ 100000L
// #endif

#include <Arduino.h>

#include <Wire.h>
#include <stdio.h>
#include <avr/wdt.h>

#include <Bounce2.h>

#include "RTClib.h"

#define SHOW_TIME 0
#define SHOW_DATE 1
#define SHOW_YEAR 2

#define N_NIXIES 4

// Pin assignments
#define NIXIE1 2
#define NIXIE2 3
#define NIXIE3 13
#define NIXIE4 12

#define DECIMAL 9

#define BIT_A A2
#define BIT_B A0
#define BIT_C A1
#define BIT_D A3

#define NUM_BUTTONS 3

// 5 = Up, 6 = Down, 8 = Mode
const uint8_t BUTTON_PINS[NUM_BUTTONS] = {8, 5, 6};

Bounce *buttons = new Bounce[NUM_BUTTONS];

RTC_DS1307 rtc;
DateTime dt;

static const uint8_t nixies[N_NIXIES] = {NIXIE1, NIXIE2, NIXIE3, NIXIE4};
static const uint8_t bits[4] = {BIT_A, BIT_B, BIT_C, BIT_D};

static const uint8_t nums[10][4] = {
    {0, 0, 0, 0}, {1, 0, 0, 0}, {0, 1, 0, 0}, {1, 1, 0, 0}, {0, 0, 1, 0}, {1, 0, 1, 0}, {0, 1, 1, 0}, {1, 1, 1, 0}, {0, 0, 0, 1}, {1, 0, 0, 1}};

// The values that are currently being displayed
static volatile uint8_t nixie_val[N_NIXIES] = {0};

// The values that are actually to be displayed in the end
static uint8_t nixie_set[N_NIXIES] = {0};

static volatile uint8_t time_passed = 1;

// Position of the number in the tube
static const uint8_t nixie_level[10 + 1] = {
    10, 1, 2, 6, 7, 5, 0, 4, 9, 8, 3};

static const uint8_t animation_speed = 10;
static volatile uint8_t animation_step = 0;

static uint8_t mode = 0;

static uint8_t cur_sec = 0;
static uint8_t cnt = 0;

static uint8_t active_nixie = 0;

static void setNixieNum(uint8_t num)
{
  uint8_t i;
  for (i = 0; i < 4; i++)
  {
    digitalWrite(bits[i], nums[num][i]);
  }
}

static void updateNixies(void)
{
  uint8_t i;
  for (i = 0; i < 4; i++)
  {
    digitalWrite(nixies[i], HIGH);
  }

  setNixieNum(nixie_val[active_nixie]);
  digitalWrite(nixies[active_nixie], LOW);

  active_nixie++;
  active_nixie %= 4;
}

static uint8_t modAdd(int8_t value, int8_t diff, int8_t v_max)
{
  if (diff < 0)
  {
    return (value + v_max + diff) % v_max;
  }
  if (diff > 0)
  {
    return (value + diff) % v_max;
  }

  return 0;
}

static void adjustTime(int8_t v)
{
  dt = rtc.now();

  int hour = dt.hour();
  int minute = dt.minute();

  if (v > 0)
  {
    if (dt.minute() == 59)
    {
      hour = modAdd(dt.hour(), 1, 24);
    }
    minute = modAdd(dt.minute(), 1, 60);
  }
  else if (v < 0)
  {
    if (dt.minute() == 0)
    {
      hour = modAdd(dt.hour(), -1, 24);
    }
    minute = modAdd(dt.minute(), -1, 60);
  }

  rtc.adjust(DateTime(dt.year(), dt.month(), dt.day(), hour, minute, 0));
}

static void refreshNixieVals(void)
{
  switch (mode)
  {
  case SHOW_TIME:
    nixie_set[0] = dt.hour() / 10;
    nixie_set[1] = dt.hour() % 10;
    nixie_set[2] = dt.minute() / 10;
    nixie_set[3] = dt.minute() % 10;
    break;
  case SHOW_DATE:
    nixie_set[0] = dt.day() / 10;
    nixie_set[1] = dt.day() % 10;
    nixie_set[2] = dt.month() / 10;
    nixie_set[3] = dt.month() % 10;
    break;
  case SHOW_YEAR:
    nixie_set[0] = 2;
    nixie_set[1] = 0;
    nixie_set[2] = dt.year() % 1000 / 10;
    nixie_set[3] = dt.year() % 10;
    break;
  }
}

static uint8_t get_level(uint8_t v)
{
  uint8_t l = sizeof(nixie_level);
  
  while (--l && nixie_level[l] != v)
  {
  }
  return l;
}

static void animate(void)
{
  uint8_t i = 0;
  uint8_t cl = 0;
  uint8_t tl = 0;

  for (i = 0; i < N_NIXIES; i++)
  {
    cl = get_level(nixie_val[i]);
    tl = get_level(nixie_set[i]);

    if (cl > tl)
    {
      // Move down a level
      nixie_val[i] = nixie_level[cl - 1];
    }
    else if (cl < tl)
    {
      nixie_val[i] = nixie_level[cl + 1];
    }
  }
}

void setup(void)
{
  // TIMER 1 for interrupt frequency 500 Hz:
  cli();      
  
  TCCR1A = 0; 
  TCCR1B = 0; 
  TCNT1 = 0;

  // Set compare match register for 500 Hz increments
  // 31999 = 16000000 / (1 * 500) - 1 (must be <65536)
  OCR1A = 31999; 
  
  // Turn on CTC mode
  TCCR1B |= (1 << WGM12);
  
  // Set CS12, CS11 and CS10 bits for 1 prescaler
  TCCR1B |= (0 << CS12) | (0 << CS11) | (1 << CS10);
  
  // Enable timer compare interrupt
  TIMSK1 |= (1 << OCIE1A);

  sei();

  // Enable watchdog timer with a 1 second time-out
  wdt_enable(WDTO_1S);

  pinMode(NIXIE1, OUTPUT);
  pinMode(NIXIE2, OUTPUT);
  pinMode(NIXIE3, OUTPUT);
  pinMode(NIXIE4, OUTPUT);

  pinMode(DECIMAL, OUTPUT);

  pinMode(BIT_A, OUTPUT);
  pinMode(BIT_B, OUTPUT);
  pinMode(BIT_C, OUTPUT);
  pinMode(BIT_D, OUTPUT);

  for (int i = 0; i < NUM_BUTTONS; i++)
  {
    // Set up the bounce instance for the current button
    buttons[i].attach(BUTTON_PINS[i], INPUT);

    // Interval in ms
    buttons[i].interval(50);
  }

  rtc.begin();
  // rtc.adjust(DateTime(2020, 10, 22, 9, 3, 0));
}

void loop(void)
{
  // Woof woof!
  wdt_reset();

  for (int i = 0; i < NUM_BUTTONS; i++)
  {
    // Update the Bounce instance :
    buttons[i].update();
  }

  // If it fell, flag the need to toggle the LED
  if (buttons[0].rose())
  {
    mode++;
    mode %= 3;
    refreshNixieVals();
  }
  else if (buttons[1].rose())
  {
    adjustTime(1);
    refreshNixieVals();
  }
  else if (buttons[2].rose())
  {
    adjustTime(-1);
    refreshNixieVals();
  }

  if (time_passed == 1)
  {
    cnt++;

    if (cnt == 1)
    {
      dt = rtc.now();
      refreshNixieVals();
    }

    cnt %= 100;
    time_passed = 0;
  }

  if (dt.second() != cur_sec)
  {
    cur_sec = dt.second();

    if (mode == SHOW_TIME)
    {
      digitalWrite(DECIMAL, (cur_sec % 2));
    }
  }

  switch (mode)
  {
  case SHOW_DATE:
    digitalWrite(DECIMAL, HIGH);
    break;
  case SHOW_YEAR:
    digitalWrite(DECIMAL, LOW);
    break;
  }

  if (animation_step)
  {
    animate();
    animation_step = 0;
  }
}

ISR(TIMER1_COMPA_vect)
{
  updateNixies();

  static uint8_t count = 0;
  if (count++ >= animation_speed)
  {
    animation_step = 1;
    count = 0;
  }

  time_passed = 1;
}
