#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import os.path
import shutil
import zipfile
import time
import subprocess
import sys
import json

#------------------------------------------------------------------
# 读取配置信息
import configparser
config = configparser.ConfigParser()
config['air640w'] = {
    # ============================================================
    # 不要修改PLAT_ROOT!不要修改PLAT_ROOT!不要修改PLAT_ROOT!
    # PLAT_ROOT仅供SDK源码开发者使用!!!!
    # 不要把PLAT_ROOT指向任何存在的路径!!!!!
    "PLAT_ROOT" : "D:\\github\\air640w\\sdk\\PLAT\\",
    # ============================================================
    "FTC_PATH" : ".\\",
    "EC_PATH" : ".\\air640w_dev.ec",
    "USER_PATH": ".\\user\\",
    "LIB_PATH" : ".\\lib\\",
    "DEMO_PATH": ".\\demo\\",
    "TOOLS_PATH": ".\\tools\\",
    "MAIN_LUA_DEBUG" : "false",
    "LUA_DEBUG" : "false",
    "COM_PORT" : "COM28"
}
if os.path.exists("local.ini") :
    config.read("local.ini")
if os.path.exists(config["air640w"]["PLAT_ROOT"]):
    PLAT_ROOT = os.path.abspath(config["air640w"]["PLAT_ROOT"]) + os.sep # 源码地址
else:
    PLAT_ROOT = config["air640w"]["PLAT_ROOT"] 
FTC_PATH = os.path.abspath(config["air640w"]["FTC_PATH"])  + os.sep   # FlashToolCLI刷机工具的目录
EC_PATH = os.path.abspath(config["air640w"]["EC_PATH"])               # EC后缀的固件路径
USER_PATH = os.path.abspath(config["air640w"]["USER_PATH"]) + os.sep  # 用户脚本所在的目录
LIB_PATH = os.path.abspath(config["air640w"]["LIB_PATH"])  + os.sep   # 用户脚本所在的目录
DEMO_PATH = os.path.abspath(config["air640w"]["DEMO_PATH"])  + os.sep # 用户脚本所在的目录
MAIN_LUA_DEBUG = config["air640w"]["MAIN_LUA_DEBUG"] == "true"
LUA_DEBUG = config["air640w"]["LUA_DEBUG"] == "true"
COM_PORT = config["air640w"]["COM_PORT"]
TOOLS_PATH = os.path.abspath(config["air640w"]["TOOLS_PATH"])  + os.sep

# TODO 从环境变量获取上述参数

'''
获取git库的当前版本号,为一个hash值
'''
def get_git_revision_short_hash():
    try :
        if os.path.exists(PLAT_ROOT):
            return subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], cwd=PLAT_ROOT).strip()
        else:
            return subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD']).strip()
    except:
        return ""

'''
打印帮助信息
'''
def usage():
    print('''
    python air640w.py [action]

    lfs   - 编译文件系统
    dlrom - 下载底层固件
    dlfs  - 下载lua脚本(即整个文件系统)
    dlfull- 下载底层和lua脚本
    pkg   - 生成发布用的压缩包
    build - 构建源码(仅内部使用)

    用例1, 生成文件系统并下载到开发板
    python air640w.py lfs dlfs

    用例2, 生成文件系统,并下载固件和文件系统到开发板
    python air640w.py lfs dlfull

    用例3, 仅下载底层固件
    python air640w.py dlrom
    
    用例四, 编译,打包,构建文件系统,全量下载
    python air640w.py build lfs pkg dlfull
    ''')

'''
执行打包程序,内部使用
'''
def _pkg():
    # TODO 扩展为用户可用的打包ec固件的工具
    if os.path.exists("tmp"):
        shutil.rmtree("tmp")

    _tag = time.strftime("%Y%m%d%H%M%S", time.localtime())
    _tag = _tag + "-" + get_git_revision_short_hash().decode()

    os.mkdir("tmp")
    # 拷贝固件文件
    if os.path.exists("../w60x/Bin/rtthread_1M.FLS") :
        shutil.copy("../w60x/Bin/rtthread_1M.FLS", "tmp/LuatOS_Air640W_V0002.FLS")
    # 拷贝库文件和demo
    shutil.copytree(LIB_PATH, "tmp/lib")
    shutil.copytree(DEMO_PATH, "tmp/demo")
    shutil.copytree(TOOLS_PATH, "tmp/tools")
    
    #拷贝自身
    shutil.copy(sys.argv[0], "tmp/air640w.py")
    shutil.copy("README.md", "tmp/README.md")
    shutil.copy("YModem.py", "tmp/YModem.py")
    shutil.copy("YMTask.py", "tmp/YMTask.py")

    if os.path.exists("userdoc") :
        shutil.copytree("userdoc", "tmp/userdoc")
    if os.path.exists("../../docs/api/lua"):
        shutil.copytree("../../docs/api/lua", "tmp/userdoc/api")
    if os.path.exists(USER_PATH):
        shutil.copytree(USER_PATH, "tmp/user")

    with open("tmp/文档在userdoc目录.txt", "w") as f:
        f.write("QQ群: 1061642968")
    # 写入默认配置文件
    with open("tmp/local.ini", "w") as f:
        f.write('''
[air640]
USER_PATH = user\\
LIB_PATH = lib\\
DEMO_PATH = demo\\
TOOLS_PATH = tools\\
MAIN_LUA_DEBUG = false
LUA_DEBUG = false
COM_PORT = COM56
''')

    pkg_name = "air640w_V0002_"+_tag + ".zip"
    shutil.make_archive("air640w_V0002_"+_tag, 'zip', "tmp")

    print("ALL DONE===================================================")
    print("Package Name", pkg_name)

'''
下载底层或脚本
'''
def _dl(tp, _path=None):
    if tp == "fs":
        import serial
        from YModem import YModem
        serial_io = serial.Serial()
        serial_io.port = COM_PORT
        serial_io.baudrate = "115200"
        serial_io.parity = "N"
        serial_io.bytesize = 8
        serial_io.stopbits = 1
        serial_io.timeout = 2

        try:
            serial_io.open()
        except Exception as e:
            raise Exception("Failed to open serial port!")

        def sender_getc(size):
            return serial_io.read(size) or None

        def sender_putc(data, timeout=15):
            return serial_io.write(data)

        serial_io.write("reboot\r\n".encode())

        for k in range(10) :
            serial_io.write("reinit\r\n".encode())
            resp = serial_io.read_until()
            try :
                print(resp.decode(), )
                if "DONE!" in resp.decode() :
                    print("格式化完成")
                    break
            except:
                pass
            time.sleep(0.03) # 50ms
        for k in range(10) :
            resp = serial_io.read_until()
        time.sleep(1)
        print(">> 开始ymodem发送文件")
        
        
        os.chdir("disk")
        for root, dirs, files in os.walk(".", topdown=False):
            for name in files:
                serial_io.write("ry\r\n".encode())
                serial_io.read_until()
                sender = YModem(sender_getc, sender_putc)
                _path = os.path.join(root, name)
                sent = sender.send_file(_path, retry=1)
        #print (">>" + sent)
        serial_io.close()

'''
生成文件系统镜像
'''
def _lfs(_path=None):
    _disk = FTC_PATH + "disk"
    if os.path.exists(_disk) :
        shutil.rmtree(_disk)
    os.mkdir(_disk)

    if not _path:
        _path = USER_PATH
    # 收集需要处理的文件列表
    _paths = []
    # 首先,遍历lib目录
    if os.path.exists(LIB_PATH) :
        for name in os.listdir(LIB_PATH) :
            _paths.append(LIB_PATH + name)
    # 然后遍历user目录
    for name in os.listdir(_path) :
        _paths.append(_path + name)
    TAG_PROJECT = ""
    TAG_VERSION = ""
    for name in _paths :
        # 如果是lua文件, 编译之
        if name.endswith(".lua") :
            cmd = [TOOLS_PATH + "luac_536_32bits.exe"]
            print ("Using Lua 32bits!!!")
            if name.endswith("main.lua") :
                if not MAIN_LUA_DEBUG :
                    cmd += ["-s"]
                with open(name, "rb") as f :
                    for line in f.readlines() :
                        if line :
                            line = line.strip().decode()
                            if line.startswith("PROJECT =") :
                                TAG_PROJECT = line[line.index("\"") + 1:][:-1]
                            elif line.startswith("VERSION =") :
                                TAG_VERSION = line[line.index("\"") + 1:][:-1]
            elif not LUA_DEBUG :
                cmd += ["-s"]
            else:
                print("LUA_DEBUG", LUA_DEBUG, "False" == LUA_DEBUG)
            cmd += ["-o", FTC_PATH + "disk/" + os.path.basename(name) + "c", os.path.basename(name)]
            print("CALL", " ".join(cmd))
            subprocess.check_call(cmd, cwd=os.path.dirname(name))
        # 其他文件直接拷贝
        else:
            print("COPY", name, FTC_PATH + "disk/" + os.path.basename(name))
            shutil.copy(name, FTC_PATH + "disk/" + os.path.basename(name))
    if TAG_PROJECT == "" or TAG_VERSION == "" :
        print("!!!!!!!miss PROJECT or/and VERSION!!!!!!!!!!")

    for root, dirs, files in os.walk("disk", topdown=False):
        import struct
        print("write flashx.tlv", root)
        with open("disk/flashx.tlv", "wb") as f :
            # 写入文件头
            f.write(struct.pack("<HHI", 0x1234, 0x00, 0x00))
            for name in files:
                # 写入文件名
                f.write(struct.pack("<HHI", 0x0101, 0x00, len(name)))
                f.write(name.encode())
                # 写入文件内容
                _path = os.path.join(root, name)
                _size = os.path.getsize(_path)
                f.write(struct.pack("<HHI", 0x0202, 0x00, _size))
                with open(_path, "rb") as f2 :
                    shutil.copyfileobj(f2, f, _size)
    if TAG_PROJECT != "" and TAG_VERSION != "":
        # otademo_1.2.7_LuatOS_V0003_w60x
        TAG_NAME = "%s_%s_LuatOS_V0003_w60x.tlv" % (TAG_PROJECT, TAG_VERSION)
        shutil.copy("disk/flashx.tlv", TAG_NAME)

def main():
    argc = 1
    while len(sys.argv) > argc :
        if sys.argv[argc] == "build" :
            print("Action Build ----------------------------------")
            #subprocess.check_call([PLAT_ROOT + "KeilBuild.bat"], cwd=PLAT_ROOT)
        elif sys.argv[argc] == "lfs" :
            print("Action mklfs ----------------------------------")
            _lfs()
        elif sys.argv[argc] == "pkg" :
            print("Action pkg ------------------------------------")
            _pkg()
        # elif sys.argv[argc] == "dlrom": #下载底层
        #     print("Action download ROM ---------------------------")
        #     if len(sys.argv) > argc + 1 and sys.argv[argc+1].startsWith("-path="):
        #         _dl("rom", sys.argv[argc+1][6:])
        #         argc += 1
        #     else:
        #         _dl("rom")
        elif sys.argv[argc] == "dlfs":
            print("Action download FS  ---------------------------")
            if len(sys.argv) > argc + 1 and sys.argv[argc+1].startsWith("-path="):
                _dl("fs", sys.argv[argc+1][6:])
                argc += 1
            else:
                _dl("fs")
        # elif sys.argv[argc] == "dlfull":
        #     if len(sys.argv) > argc + 1 and sys.argv[argc+1].startsWith("-path="):
        #         _dl("full", sys.argv[argc+1][6:])
        #         argc += 1
        #     else:
        #         _dl("full")
        elif sys.argv[argc] == "clean":
            if os.path.exists("tmp"):
                shutil.rmtree("tmp")
            if os.path.exists(FTC_PATH + "disk"):
                shutil.rmtree(FTC_PATH + "disk")
        else:
            usage()
            return
        argc += 1
    print("============================================================================")
    print("every done, bye")


if len(sys.argv) == 1 :
    usage()
else :
    main()
