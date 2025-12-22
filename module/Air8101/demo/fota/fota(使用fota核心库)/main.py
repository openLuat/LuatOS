#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import serial, serial.tools.list_ports, sys, argparse

def find_virtual_port():
    for port in serial.tools.list_ports.comports():
        if port.vid == 0x19d1 and port.pid == 0x0001 and port.location and "x.6" in port.location:
            return port.device
    return None

# 解析命令行参数
parser = argparse.ArgumentParser()
parser.add_argument('-p', '--port', help='串口名称，如COM1或/dev/ttyS0')
args = parser.parse_args()

# 确定使用的串口
port = args.port or find_virtual_port()
if not port:
    print("错误: 未找到虚拟串口且未指定串口")
    sys.exit(1)

print(f"使用串口: {port}")

try:
    with serial.Serial(port, 115200, timeout=1) as ser:
        ser.write(b"#FOTA\n")
        data = ser.read(128)
        if data and data.startswith(b"#FOTA"):
            print("设备响应", data)
            with open("fota_uart.bin", "rb") as f:
                while fdata := f.read(1024):
                    print("发送升级包数据", len(fdata))
                    ser.write(fdata)
                    if resp := ser.read(128):
                        print("设备响应", resp)
            print("发送完毕,退出")
        else:
            print("设备没响应", data)
except Exception as e:
    print(f"错误: {e}")
    sys.exit(1)