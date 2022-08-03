#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import os.path
import shutil
import zipfile
import time
import subprocess
import sys
import json
import io

BIG_VER = "V0013"
TAG_PROJECT = ""
TAG_VERSION = ""
TAG_UPDATE_NAME = ""

#------------------------------------------------------------------
# 读取配置信息
import configparser
config = configparser.ConfigParser()
config['air302'] = {
    # ============================================================
    #
    #          配置信息是读取local.ini为主的,以下的只是默认配置.
    #          请修改local.ini, 一般不需要修改本脚本里的配置信息.
    #
    # ============================================================
    # 不要修改PLAT_ROOT!不要修改PLAT_ROOT!不要修改PLAT_ROOT!
    # PLAT_ROOT仅供SDK源码开发者使用!!!!
    # 不要把PLAT_ROOT指向任何存在的路径!!!!!
    "PLAT_ROOT" : "E:\\code\\codeup\\air302\\sdk\\PLAT\\",
    # ============================================================
    "FTC_PATH" : ".\\FlashToolCLI\\",
    "EC_PATH" : ".\\Air302_dev.ec",
    "USER_PATH": ".\\user\\",
    "LIB_PATH" : ".\\lib\\",
    "DEMO_PATH": "..\\..\\demo\\",
    "TOOLS_PATH": ".\\tools\\",
    "MAIN_LUA_DEBUG" : "false",
    "LUA_DEBUG" : "false",
    "COM_PORT" : "COM59" # 请修改local.ini文件
}
if os.path.exists("local.ini") :
    config.read("local.ini")
if os.path.exists(config["air302"]["PLAT_ROOT"]):
    PLAT_ROOT = os.path.abspath(config["air302"]["PLAT_ROOT"]) + os.sep # 源码地址
else:
    PLAT_ROOT = config["air302"]["PLAT_ROOT"] 
FTC_PATH = os.path.abspath(config["air302"]["FTC_PATH"])  + os.sep   # FlashToolCLI刷机工具的目录
EC_PATH = os.path.abspath(config["air302"]["EC_PATH"])               # EC后缀的固件路径
USER_PATH = os.path.abspath(config["air302"]["USER_PATH"]) + os.sep  # 用户脚本所在的目录
LIB_PATH = os.path.abspath(config["air302"]["LIB_PATH"])  + os.sep   # 用户脚本所在的目录
DEMO_PATH = os.path.abspath(config["air302"]["DEMO_PATH"])  + os.sep # 用户脚本所在的目录
MAIN_LUA_DEBUG = config["air302"]["MAIN_LUA_DEBUG"] == "true"
LUA_DEBUG = config["air302"]["LUA_DEBUG"] == "true"
COM_PORT = config["air302"]["COM_PORT"]
TOOLS_PATH = os.path.abspath(config["air302"]["TOOLS_PATH"])  + os.sep

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
    python air302.py [action]

    lfs   - 编译文件系统
    dlrom - 下载底层固件
    dlfs  - 下载lua脚本(即整个文件系统)
    dlfull- 下载底层和lua脚本
    pkg   - 生成发布用的压缩包
    build - 构建源码(仅内部使用)

    用例1, 生成文件系统并下载到开发板
    python air302.py lfs dlfs

    用例2, 生成文件系统,并下载固件和文件系统到开发板
    python air302.py lfs dlfull

    用例3, 仅下载底层固件
    python air302.py dlrom
    
    用例四, 编译,打包,构建文件系统,全量下载
    python air302.py build lfs pkg dlfull

    用例五, 生成量产所需要的文件
    python air302.py lfs pkg
    ''')

'''
FlashToolCLI所需要的配置信息
'''
FTC_CNF_TMPL = '''
[config]
line_0_com = ${COM}
agbaud = 921600

;bootloader.bin file infomation
[bootloader]
blpath = .\\image\\bootloader.bin
blloadskip = 0

;system.bin file infomation
[system]
syspath = .\\system.bin
sysloadskip = 0

;control such as reset before download
[control]
reset = 0

[flexfile0]
filepath = .\\rfCaliTb\\MergeRfTable.bin
burnaddr = 0x3A4000

[flexfile1]
filepath = .\\rfCaliTb\\MergeRfTable.bin
burnaddr = 0x16000

[flexfile2]
filepath = .\\disk.fs
burnaddr = 0x350000
'''.replace("${COM}", COM_PORT)

'''
执行打包程序,内部使用
'''
def _pkg():
    # TODO 扩展为用户可用的打包ec固件的工具
    if os.path.exists("tmp"):
        shutil.rmtree("tmp")

    _tag = time.strftime("%Y%m%d%H%M%S", time.localtime())
    _git_sha1 = get_git_revision_short_hash()
    if _git_sha1 and _git_sha1 != "" :
        _tag = _tag + "-" + _git_sha1.decode()

    os.mkdir("tmp")
    os.mkdir("tmp/ec")
    # 拷贝固件文件
    if os.path.exists(PLAT_ROOT) :
        shutil.copy(PLAT_ROOT + "out/ec616_0h00/air302/air302.bin", "tmp/ec/luatos.bin")
        shutil.copy(PLAT_ROOT + "out/ec616_0h00/air302/comdb.txt", "tmp/ec/comdb.txt")
        shutil.copy(FTC_PATH + "image/bootloader.bin", "tmp/ec/bootloader.bin")
        with open("tmp/ec/bootloader_head.bin", "w") as f:
            f.write("")
        #shutil.copy(FTC_PATH + "image/bootloader_head.bin", "tmp/ec/bootloader_head.bin")
    elif os.path.exists(EC_PATH) and EC_PATH.endswith(".ec") :
        with zipfile.ZipFile(EC_PATH) as zip :
            zip.extractall(path="tmp/ec/")
    # 拷贝库文件和demo
    shutil.copytree(LIB_PATH, "tmp/lib")
    # shutil.copytree(DEMO_PATH, "tmp/demo")
    shutil.copytree(TOOLS_PATH, "tmp/tools")
    
    #拷贝自身
    shutil.copy(sys.argv[0], "tmp/air302.py")
    shutil.copy("air302.bat", "tmp/air302.bat")

    # 写入默认配置文件
    with open("tmp/local.ini", "w") as f:
        f.write('''
[air302]
FTC_PATH = FlashToolCLI\\
EC_PATH = ${EC}
USER_PATH = user\\
LIB_PATH = lib\\
DEMO_PATH = demo\\
TOOLS_PATH = tools\\
MAIN_LUA_DEBUG = false
LUA_DEBUG = false
COM_PORT = COM56
'''.replace("${EC}", "Air302_"+BIG_VER+"_"+_tag+".ec"))

    if os.path.exists("userdoc") :
        shutil.copytree("userdoc", "tmp/userdoc")
    if os.path.exists("../../docs/api/lua"):
        shutil.copytree("../../docs/api/lua", "tmp/userdoc/api")
    if os.path.exists(USER_PATH):
        shutil.copytree(USER_PATH, "tmp/user")

    with open("tmp/文档在userdoc目录.txt", "w") as f:
        f.write("QQ群: 1061642968")

    with zipfile.ZipFile("tmp/Air302_"+BIG_VER+"_"+_tag+".ec", mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zip :
        zip.write("tmp/ec/luatos.bin", "luatos.bin")                   # 底层固件
        zip.write("tmp/ec/comdb.txt", "comdb.txt")                     # uart0输出的unilog所需要的数据库文件,备用
        zip.write("tmp/ec/bootloader.bin", "bootloader.bin")           # bootloader,备用
        if os.path.exists("tmp/ec/bootloader_head.bin"):
            zip.write("tmp/ec/bootloader_head.bin", "bootloader_head.bin") # bootloader_header,备用
        zip.write(FTC_PATH + "disk.fs", "disk.bin")                    # 默认磁盘镜像

    
    if os.path.exists(FTC_PATH):
        shutil.copytree(FTC_PATH, "tmp/FlashToolCLI")

    if TAG_PROJECT != "" and TAG_VERSION != "" :
        print(u"为 %s %s 生成量产文件" % (TAG_PROJECT, TAG_VERSION))
        prod_path = u"量产文件/Air302量产文件/" + TAG_PROJECT + "_" + TAG_VERSION
        update_bin_dir = u"量产文件/Air302远程升级文件"
        if not os.path.exists(prod_path + "/image/"):
            os.makedirs(prod_path + "/image/")
        if not os.path.exists(update_bin_dir):
            os.makedirs(update_bin_dir)
        print("量产文件目录 --> ", prod_path)
        shutil.copyfile("tmp/ec/luatos.bin", prod_path + "/luatos.bin")
        shutil.copyfile("tmp/ec/bootloader.bin", prod_path + "/bootloader.bin")
        if os.path.exists("tmp/ec/bootloader_head.bin"):
            shutil.copyfile("tmp/ec/bootloader_head.bin", prod_path + "/bootloader_head.bin")
        shutil.copyfile(FTC_PATH + "disk.fs", prod_path + "/disk.fs")
        #with open((prod_path + "/config.ini"), "wb") as f:
        #    f.write(FTC_CNF_TMPL.encode())

        shutil.copyfile(TAG_UPDATE_NAME, update_bin_dir + "/" + TAG_UPDATE_NAME)
        print("远程升级文件 --> ", update_bin_dir + "/" + TAG_UPDATE_NAME)

        shutil.rmtree("tmp/ec/")

        if not os.path.exists("量产文件/Air302刷机包/") :
            os.makedirs("量产文件/Air302刷机包/")
        one_ec_path = "量产文件/Air302刷机包/" + TAG_PROJECT + "_" + TAG_VERSION  + "_LuatOS_Air302_"+BIG_VER + ".ec"
        shutil.copyfile("tmp/Air302_"+BIG_VER+"_"+_tag+".ec", one_ec_path)
        print("一体刷机包   --> ", one_ec_path)
    else :
        if not os.path.exists("量产文件"):
            os.makedirs("量产文件")
        pkg_name = "量产文件" + "/Air302_"+BIG_VER+"_"+_tag
        print(">>  " + pkg_name + ".zip")
        shutil.make_archive(pkg_name, 'zip', "tmp")

        ## 拷贝一份固定路径的
        shutil.copy("tmp/Air302_"+BIG_VER+"_"+_tag+".ec", "tmp/Air302_dev.ec")

'''
下载底层或脚本
'''
def _dl(tp, _path=None):
    with open(FTC_PATH + "config.ini", "w") as f :
        f.write(FTC_CNF_TMPL)
    cmd = [FTC_PATH + "FlashToolCLI.exe", "-p", COM_PORT, "burnbatch", "--imglist"]
    if tp == "rom" or tp == "full":
        if os.path.exists(PLAT_ROOT + "out/ec616_0h00/air302/air302.bin") :
            print("P1 COPY beta version from PLAT_ROOT dir", PLAT_ROOT + "out/ec616_0h00/air302/air302.bin")
            shutil.copy(PLAT_ROOT + "out/ec616_0h00/air302/air302.bin", FTC_PATH + "system.bin")
        elif EC_PATH.endswith(".ec") :
            print("P1. Unzip luatos.bin from " + EC_PATH)
            import zipfile
            with zipfile.ZipFile(EC_PATH) as zip :
                with open(FTC_PATH + "system.bin", "wb") as f:
                    f.write(zip.read("luatos.bin"))
        elif EC_PATH.endswith(".bin"):
            print("P1. Using bin file from " + EC_PATH)
            shutil.copy(EC_PATH, FTC_PATH + "system.bin")
        else:
            print("Bad EC_PATH : " + EC_PATH)
            return
        cmd += ["system"]
        cmd += ["bootloader"]
    if tp == "fs" or tp == "full" :
        cmd += ["flexfile2"]
    print("P2. Call", " ".join(cmd))
    subprocess.check_call(cmd, cwd=FTC_PATH)
    print("P3. Done")

'''
生成文件系统镜像
'''
def _lfs(_path=None):
    print("============================================================")
    print(" Build LittltFS disk image")
    print("============================================================")
    _disk = FTC_PATH + "disk"
    if os.path.exists(_disk) :
        shutil.rmtree(_disk)
    os.mkdir(_disk)

    if not _path:
        _path = USER_PATH
    print("P1. User Lua Dir == ", os.path.abspath(_path))
    # 收集需要处理的文件列表
    _paths = []
    # 首先,遍历lib目录
    if os.path.exists(LIB_PATH) :
        print("P1. Lib  Lua Dir == ", os.path.abspath(LIB_PATH))
        for name in os.listdir(LIB_PATH) :
            _paths.append(LIB_PATH + name)
    # 然后遍历user目录
    for name in os.listdir(_path) :
        _paths.append(_path + name)
    global TAG_PROJECT
    global TAG_VERSION
    global TAG_UPDATE_NAME
    for name in _paths :
        # 如果是lua文件, 编译之
        if name.endswith(".lua") :
            cmd = [TOOLS_PATH + "luac_536_32bits.exe"]
            if name.endswith("main.lua") :
                if not MAIN_LUA_DEBUG :
                    cmd += ["-s"]
                with io.open(name, mode="r", encoding="utf-8") as f :
                    for line in f.readlines() :
                        if line :
                            line = line.strip()
                            if line.startswith("PROJECT =") :
                                TAG_PROJECT = line[line.index("\"") + 1:][:-1]
                            elif line.startswith("VERSION =") :
                                TAG_VERSION = line[line.index("\"") + 1:][:-1]
            elif not LUA_DEBUG :
                cmd += ["-s"]
            else:
                print("LUA_DEBUG", LUA_DEBUG, "False" == LUA_DEBUG)
            cmd += ["-o", FTC_PATH + "disk/" + os.path.basename(name) + "c", os.path.basename(name)]
            print("P2. CALL Luac >> ", os.path.abspath(name))
            subprocess.check_call(cmd, cwd=os.path.dirname(name))
        # 其他文件直接拷贝
        else:
            print("P2. COPY", name, FTC_PATH + "disk/" + os.path.basename(name))
            shutil.copy(name, FTC_PATH + "disk/" + os.path.basename(name))
    if TAG_PROJECT == "" or TAG_VERSION == "" :
        print("!!!!!!!miss PROJECT or/and VERSION!!!!!!!!!!")

    for root, dirs, files in os.walk(FTC_PATH + "disk", topdown=False):
        import struct
        print("P3. Make flashx.bin", FTC_PATH + "disk/flashx.bin")
        with open(FTC_PATH + "disk/flashx.bin", "wb") as f :
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
        # otademo_1.2.7_LuatOS_"+BIG_VER+"_ec616
        TAG_UPDATE_NAME = ("%s_%s_LuatOS_"+BIG_VER+"_ec616.bin") % (TAG_PROJECT, TAG_VERSION)
        print("P4. OTA Update bin --> " + TAG_UPDATE_NAME)
        shutil.copy(FTC_PATH + "disk/flashx.bin", TAG_UPDATE_NAME)

    print("P5. CALL mklfs to make disk.fs")
    subprocess.check_call([TOOLS_PATH + "mklfs.exe"], cwd=FTC_PATH)
    print("P6. LFS DONE")

def main():
    argc = 1
    while len(sys.argv) > argc :
        if sys.argv[argc] == "build" :
            print("Action Build 编译 ----------------------------------")
            subprocess.check_call([PLAT_ROOT + "KeilBuild.bat"], cwd=PLAT_ROOT)
        elif sys.argv[argc] == "lfs" :
            print("Action mklfs ----------------------------------")
            _lfs()
        elif sys.argv[argc] == "pkg" :
            print("Action pkg 打包固件和生成量产文件------------------------------------")
            _pkg()
        elif sys.argv[argc] == "dlrom": #下载底层
            print("Burn ROM 下载固件 ---------------------------")
            if len(sys.argv) > argc + 1 and sys.argv[argc+1].startsWith("-path="):
                _dl("rom", sys.argv[argc+1][6:])
                argc += 1
            else:
                _dl("rom")
        elif sys.argv[argc] == "dlfs":
            print("Burn FS 下载文件系统 ---------------------------")
            if len(sys.argv) > argc + 1 and sys.argv[argc+1].startsWith("-path="):
                _dl("fs", sys.argv[argc+1][6:])
                argc += 1
            else:
                _dl("fs")
        elif sys.argv[argc] == "dlfull":
            if len(sys.argv) > argc + 1 and sys.argv[argc+1].startsWith("-path="):
                _dl("full", sys.argv[argc+1][6:])
                argc += 1
            else:
                _dl("full")
        elif sys.argv[argc] == "clean":
            if os.path.exists("tmp"):
                shutil.rmtree("tmp")
            if os.path.exists(PLAT_ROOT) :
                subprocess.call([PLAT_ROOT + "KeilBuild.bat", "clall"], cwd=PLAT_ROOT)
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
