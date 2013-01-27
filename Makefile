#
# Makefile for NixieClock
#

AVRDUDE_ARD_BAUDRATE	?= 115200
AVRDUDE_ARD_PROGRAMMER	?= stk500v2

MCU					?= atmega8
F_CPU					?= 1000000
ARDUINO_PORT		?= /dev/tty.usbmodem*

TARGET				?= NixieClock
ARDUINO_LIBS		?= Wire

include Arduino.mk