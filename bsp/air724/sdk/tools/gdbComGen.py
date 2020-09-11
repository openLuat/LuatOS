'''
@Author: your name
@Date: 2020-08-01 10:45:37
@LastEditTime: 2020-08-01 18:33:19
@LastEditors: Please set LastEditors
@Description: In User Settings Edit
@FilePath: \iot_sdk_4g_8910Main\tools\gdb.py
'''

import os
import sys

# 生成gdb调试时所需的加载app.elf的指令
if __name__ == "__main__":
    # D:/AirJob/RDA8910CSDK/iot_sdk_4g_8910Main/hex/Air720U_CSDK_demo_hello_map/app.elf
    GenPath = sys.argv[1]
    MapPath = sys.argv[2]

    path = GenPath+MapPath
    d = os.popen(
        "prebuilts\\win32\\gcc-arm-none-eabi\\bin\\arm-none-eabi-readelf.exe -S "+path)
    SectionHeaders = {}
    for i in d.readlines():
        # print(i)
        s1 = i[7:25].rstrip()
        s2 = i[41:49]
        SectionHeaders[s1] = s2
    d.close()

    with open("start.gdb", "w") as f:
        # f.write("cd "+GenPath+"\n")
        f.write("bt\n")
        f.write("add-symbol-file \""+path+"\" " +
                "0x"+SectionHeaders[".text"]+"\n")
        f.write("bt\n")
