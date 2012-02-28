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
#ifndef TWI_FREQ
#define TWI_FREQ 400000L
#endif 

#include <Wire.h>
#include <stdio.h>
#include <avr/wdt.h>
	 	 
#define DS1307_ADDRESS 0x68

#define SHOW_TIME	0
#define SHOW_DATE	1
#define SHOW_YEAR	2

#define N_NIXIES	4

// Pin assignments
#define NIXIE1		2
#define NIXIE2		3
#define NIXIE3		13
#define NIXIE4		12

#define DECIMAL		9

#define BIT_A		A2
#define BIT_B		A0
#define BIT_C		A1
#define BIT_D		A3

#define SWITCH_UP	5
#define SWITCH_DOWN	6

#define BUTTON		8


// Holds the current time and date
static struct {
	uint8_t hour;
	uint8_t minute;
 	uint8_t second;
 	uint8_t dayOfWeek;
 	uint8_t day;
 	uint8_t month;
 	uint8_t year;
} ds;

static const uint8_t nixies[N_NIXIES]	= { NIXIE1, NIXIE2, NIXIE3, NIXIE4 };
static const uint8_t bits[4]			= { BIT_A, BIT_B, BIT_C, BIT_D };

static const uint8_t nums[10][4] = {
	{ 0, 0, 0, 0 }, { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 1, 1, 0, 0 }, { 0, 0, 1, 0 },
	{ 1, 0, 1, 0 }, { 0, 1, 1, 0 },	{ 1, 1, 1, 0 }, { 0, 0, 0, 1 }, { 1, 0, 0, 1 }
};

// The values that are currently being displayed
static volatile uint8_t nixie_val[N_NIXIES] = { 0 };

// The values that are actually to be displayed in the end 
static uint8_t nixie_set[N_NIXIES] = { 0 };

static volatile uint8_t time_passed = 1;

// Position of the number in the tube
static const uint8_t nixie_level[10+1] = {
	10, 1, 2, 6, 7,	5, 0, 4, 9, 8, 3
};

static const uint8_t animation_speed = 10;
static volatile uint8_t animation_step = 0;

static uint8_t switchup	= 0;
static uint8_t switchdn	= 0;

static uint8_t btn = 0;
static uint8_t mode = 0;

static uint8_t cur_sec = 0;
static uint8_t cnt = 0;

static uint8_t active_nixie = 0;


// Converts binary-coded decimal back to decimal
static uint8_t bcdToDec(uint8_t val) {
	return ((val / 16 * 10) + (val % 16));
}


// Converts decimal values to binary-coded decimal
static uint8_t decToBcd(uint8_t val) {
  return ((val / 10 * 16) + (val % 10));
}


static void getTime(void) {
	// Reset the register pointer
	Wire.beginTransmission(DS1307_ADDRESS);
	Wire.send(0);
	Wire.endTransmission();

	Wire.requestFrom(DS1307_ADDRESS, 7);

	ds.second	 = bcdToDec(Wire.receive());
	ds.minute	 = bcdToDec(Wire.receive());
	ds.hour		 = bcdToDec(Wire.receive() & 0b111111);	// 24 hour time
	ds.dayOfWeek = bcdToDec(Wire.receive());
	ds.day 		 = bcdToDec(Wire.receive());
	ds.month	 = bcdToDec(Wire.receive());
	ds.year		 = bcdToDec(Wire.receive());
}


/**
 * Sets the date and time on the DS1307, starts the clock,
 * sets hour mode to 24 hour clock, assumes that valid numbers are passed.
 */
static void setTime(void) {
   Wire.beginTransmission(DS1307_ADDRESS);
   Wire.send(0);
   Wire.send(decToBcd(ds.second));	// 0 to bit 7 starts the clock
   Wire.send(decToBcd(ds.minute));
   Wire.send(decToBcd(ds.hour));		
   Wire.send(decToBcd(ds.dayOfWeek));
   Wire.send(decToBcd(ds.day));
   Wire.send(decToBcd(ds.month));
   Wire.send(decToBcd(ds.year));
   Wire.endTransmission();
}


static void setNixieNum(uint8_t num) {
	uint8_t i;
	for(i=0; i<4; i++) {
		digitalWrite(bits[i], nums[num][i]);
	}
}


static void updateNixies(void) {
	uint8_t i;
	for(i=0; i<4; i++) {
		digitalWrite(nixies[i], HIGH);
	}	
		
	setNixieNum(nixie_val[active_nixie]);
	digitalWrite(nixies[active_nixie], LOW);
		
	active_nixie++;
	active_nixie %= 4;	
}


static uint8_t modAdd(int8_t value, int8_t diff, int8_t v_max) {
	if (diff < 0) {
		return (value + v_max + diff) % v_max;
	}
	if (diff > 0) {
		return (value + diff) % v_max;
	}
}


static void adjustTime(int8_t v) {
	getTime();
	
	if (v > 0) {
		if (ds.minute == 59) {
			ds.hour = modAdd(ds.hour, 1, 24);
		}
		ds.minute = modAdd(ds.minute, 1, 60);
	} 
	else if (v < 0) {
		if (ds.minute == 0) {
			ds.hour = modAdd(ds.hour, -1, 24);
		}
		ds.minute = modAdd(ds.minute, -1, 60);
	} 
	ds.second = 0;
	
	setTime();
}


static void refreshNixieVals(void) {
	switch(mode) {
		case SHOW_TIME:
			nixie_set[0] = ds.hour / 10;
			nixie_set[1] = ds.hour % 10;
			nixie_set[2] = ds.minute / 10;
			nixie_set[3] = ds.minute % 10;
			break;
		case SHOW_DATE:
			nixie_set[0] = ds.day / 10;
			nixie_set[1] = ds.day % 10;
			nixie_set[2] = ds.month / 10;
			nixie_set[3] = ds.month % 10;
			break;
		case SHOW_YEAR:
			nixie_set[0] = 2;
			nixie_set[1] = 0;
			nixie_set[2] = ds.year / 10;
			nixie_set[3] = ds.year % 10;
			break;
	}	
}


static uint8_t get_level(uint8_t v) {
	uint8_t l = sizeof(nixie_level);
	while (--l && nixie_level[l] != v) {}
	return l;
}


static void animate(void) {
	uint8_t i = 0;
	uint8_t cl = 0;
	uint8_t tl = 0;
	for (i = 0; i<N_NIXIES; i++) {
		cl = get_level(nixie_val[i]);
		tl = get_level(nixie_set[i]);
		
		if (cl > tl) {
			// Move down a level
			nixie_val[i] = nixie_level[cl-1];
		} else if (cl < tl) {
			nixie_val[i] = nixie_level[cl+1];
		}
	}
}


void setup(void) {
	// Disable the other timer
	TCCR1A	= 0;
	
	// Configure timer for 500Hz (refresh each NIXIE with 125Hz)
	TCCR1B	= (1 << WGM12) | (1<<CS10); 
	OCR1A	= 0x7D0;
	TIMSK1	= (1 << OCIE1A);
	
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
	
	pinMode(SWITCH_UP, INPUT);
	pinMode(SWITCH_DOWN, INPUT);
	
	pinMode(BUTTON, INPUT);
}


void loop(void) {
	// Woof woof!
	wdt_reset();
	
	switchup = digitalRead(SWITCH_UP);
	switchdn = digitalRead(SWITCH_DOWN);
	btn = digitalRead(BUTTON);
	
	if(switchup) {
		adjustTime(1);
		refreshNixieVals();
		delay(150);
	}
	
	if(switchdn) {
		adjustTime(-1);
		refreshNixieVals();
		delay(150);
	}
		
	if(btn) {
		mode++;
		mode %= 3;
		refreshNixieVals();
		delay(200);
	}	
	
	if (time_passed) {	
		cnt++;
		
		if(cnt == 1) {
			getTime();
			refreshNixieVals();
		}
		
		cnt %= 100;		
		time_passed = 0;
	}
			
	if(ds.second != cur_sec) {
		cur_sec = ds.second;
	}
	
	switch(mode) {
		case SHOW_TIME:
			digitalWrite(DECIMAL, (cur_sec % 2));
			break;
		case SHOW_DATE:
			digitalWrite(DECIMAL, HIGH);
			break;
		case SHOW_YEAR:
			digitalWrite(DECIMAL, LOW);
			break;
	}
	

	if (animation_step) {
		animate();
		animation_step = 0;
	}
}


ISR(TIMER1_COMPA_vect) {
	updateNixies();

	static uint8_t count = 0;
	if (count++ >= animation_speed) {
		animation_step = 1;
		count = 0;
	}
	
	time_passed = 1;
}
