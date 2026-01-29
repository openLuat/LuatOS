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
                ser.write(b"#FOTA\n")
                data = ser.read(128)
                if data and data.startswith(b"#FOTA") :
                    print("设备响应", data)
                    with open("fota_uart.bin", "rb") as f :
                        while 1 :
                            fdata = f.read(256)
                            if not fdata :
                                print("发送完毕,退出")
                                sys.exit(0)
                            print("发送升级包数据", len(fdata))
                            ser.write(fdata)
                            data = ser.read(128)
                            if data :
                                print("设备响应", data)
                else :
                    print("设备没响应", data)
                break


