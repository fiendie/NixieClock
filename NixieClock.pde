/**
 * NixieClock 
 * 
 * An Arduino Sketch for multiplexing 4 NIXIE tubes to show the 
 * current time.
 * The time is read from a Philips PCF8583 RTC chip. 
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
#include <PCF8583.h>

#define N_NIXIES	4

#define NIXIE1		2
#define NIXIE2		3
#define NIXIE3		13
#define NIXIE4		12

#define DECIMAL		9

#define BIT_A		A2
#define BIT_B		A0
#define BIT_C		A1
#define BIT_D		A3

#define SWITCH_UP	6
#define SWITCH_DOWN	7

static const uint8_t nixies[N_NIXIES]	= { NIXIE1, NIXIE2, NIXIE3, NIXIE4 };
static const uint8_t bits[4]			= { BIT_A, BIT_B, BIT_C, BIT_D };

static const uint8_t nums[10][4] = {
	{0, 0, 0, 0}, {1, 0, 0, 0}, {0, 1, 0, 0}, {1, 1, 0, 0}, {0, 0, 1, 0},
	{1, 0, 1, 0}, {0, 1, 1, 0},	{1, 1, 1, 0}, {0, 0, 0, 1},	{1, 0, 0, 1}
};

static volatile uint8_t nixie_val[N_NIXIES] = { 0 };
static volatile uint8_t time_passed = 1;

static uint8_t switchup	= 0;
static uint8_t switchdn	= 0;

static uint8_t cur_sec = 0;
static int cnt = 0;

static uint8_t active_nixie = 0;

PCF8583 p (0xA0);


void setNixieNum(uint8_t num) {
	int i;
	for(i=0; i<4; i++) {
		digitalWrite(bits[i], nums[num][i]);
	}
}


void setup(void) {
	// Disable the other timer
	TCCR1A	= 0;
	// Configure timer for 400Hz (refresh each NIXIE with 100Hz)
	TCCR1B	= (1 << WGM12) | (1<<CS10); 
	OCR1A	= 0x9C4;
	TIMSK1	= (1 << OCIE1A);
	
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
}


void updateNixies(void) {
	int i;
	for(i=0; i<4; i++) {
		digitalWrite(nixies[i], HIGH);
	}	
		
	setNixieNum(nixie_val[active_nixie]);
	digitalWrite(nixies[active_nixie], LOW);
		
	active_nixie++;
	active_nixie %= 4;	
}


static int mod_add(int value, int diff, int max) {
	if (diff < 0) {
		return (value + max + diff)%max;
	}
	if (diff > 0) {
		return (value+diff)%max;
	}
}


void adjustTime(int8_t v) {
	p.get_time();
	
	if (v > 0) {
		if (p.minute == 59) {
			p.hour = mod_add(p.hour, 1, 24);
		}
		p.minute = mod_add(p.minute, 1, 60);
	} 
	else if (v<0) {
		if (p.minute == 0) {
			p.hour = mod_add(p.hour, -1, 24);
		}
		p.minute = mod_add(p.minute, -1, 60);
	} 
	p.set_time();
}


void refreshNixieVals(void) {
	nixie_val[0] = (p.hour / 10);
	nixie_val[1] = p.hour % 10;
	nixie_val[2] = (p.minute / 10);
	nixie_val[3] = p.minute % 10;	
}


void loop(void) {	
	switchup = digitalRead(SWITCH_UP);
	switchdn = digitalRead(SWITCH_DOWN);
	
	if(switchup) {
		adjustTime(1);
		refreshNixieVals();
		delay(100);
	}
	
	if(switchdn) {
		adjustTime(-1);
		refreshNixieVals();
		delay(100);
	}
			
	
	if (time_passed) {	
		cnt++;
		
		if(cnt == 1) {
			p.get_time();
			refreshNixieVals();
		}
		
		cnt %= 100;		
		time_passed = 0;
	}
			
	// Flash decimal point every even second
	if(p.second != cur_sec) {		
		digitalWrite(DECIMAL, (cur_sec % 2));		
		cur_sec = p.second;
	}
}


ISR(TIMER1_COMPA_vect) {
	updateNixies();
	time_passed = 1;
}
