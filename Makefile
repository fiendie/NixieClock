#
# Makefile for NixieClock
#

ARDUINO_PORT					?= /dev/tty.usbmodem621
ARDUINO_AVRDUDE_PROGRAMMER		?= stk500v2
ARDUINO_MCU						?= atmega168
ARDUINO_F_CPU					?= 1000000

include arduino-tpl.mk