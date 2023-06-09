#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import os, sys, serial.tools.list_ports, time


for item in serial.tools.list_ports.comports():
    if not item.pid or not item.location :
        continue
    if item.vid == 0x19d1 and item.pid == 0x0001 and "x.6" in item.location :
        print(dir(item))
        print(item.name)
        with serial.Serial(item.name, 115200, timeout=1) as ser:
            while 1:
                data = ser.read(128)
                if data :
                    print( str(time.time()) + ">> " + str(data))
                else :
                    ser.write("Hi from PC".encode())

