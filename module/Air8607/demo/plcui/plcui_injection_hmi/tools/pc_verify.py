#!/usr/bin/env python3
"""PC 模拟器端到端验证：把工程真实 Lua 代码跑在 LVGL 上，抓四页真实渲染位图。

用法：python tools/pc_verify.py [--keep]
产出：preview/sim_*.png（真实渲染）、build/pc_verify.log（原始日志）

为什么不用 PLCUI 的 snapshot 直接出 PNG：PC 平台只支持 SDL_SaveBMP，
所以先出 BMP 再用 Pillow 转 PNG；BMP 必须落在 app 目录之外，
否则会把模拟器启动毒化（历史坑：app 目录里有 BMP 必崩）。
"""

import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE = os.path.join(ROOT, "code")
RES = os.path.join(CODE, "res")
TMP = os.path.join(os.environ.get("TEMP", "/tmp"), "pc_verify")
APP = os.path.join(TMP, "app")
OUT = os.path.join(TMP, "out")      # 必须与 APP 分叉，不能是 APP 的父目录
SNAP = os.path.join(TMP, "snap")
RESULT = os.path.join(TMP, "result.txt")
LOG = os.path.join(TMP, "run.log")
EXE = "C:/gitee/LuatOS/bsp/pc/build/out/luatos-lua.exe"
CWD = "C:/gitee/LuatOS/bsp/pc"
PREVIEW = os.path.join(ROOT, "preview")
BUILD = os.path.join(ROOT, "build")

# 跑在模拟器里的文件：业务三件套 + 验证脚本；不带 boot_app（它会点硬件）
LUA_FILES = ["data_app.lua", "ui_app.lua", "ui_vars.lua"]


def stage():
    for d in (APP, OUT, SNAP):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d, exist_ok=True)
    for fn in LUA_FILES:
        shutil.copy(os.path.join(CODE, fn), os.path.join(APP, fn))
    for fn in sorted(os.listdir(RES)):
        if fn.lower().endswith((".png", ".jpg", ".xml")):
            shutil.copy(os.path.join(RES, fn), os.path.join(APP, fn))
    shutil.copy(os.path.join(ROOT, "tools", "pc_verify", "main.lua"),
                os.path.join(APP, "main.lua"))
    n = len(os.listdir(APP))
    print("staging: %s (%d 个文件)" % (APP, n))
    return n


def clean_dumps():
    """pclogs 里堆积的 .dmp 会让模拟器启动期随机 ACCESS_VIOLATION（READ 0x8），
    跑之前清干净，否则会误判成脚本 bug。"""
    d = os.path.join(CWD, "pclogs")
    if not os.path.isdir(d):
        return 0
    n = 0
    for fn in os.listdir(d):
        if fn.lower().endswith(".dmp"):
            try:
                os.remove(os.path.join(d, fn))
                n += 1
            except OSError:
                pass
    return n


def run(timeout=90):
    for f in (LOG, RESULT):
        if os.path.exists(f):
            os.remove(f)
    with open(LOG, "wb") as fh:
        p = subprocess.Popen([EXE, APP + "/", OUT + "/"], cwd=CWD,
                             stdout=fh, stderr=subprocess.STDOUT)
        deadline = time.time() + timeout
        done = False
        while time.time() < deadline:
            time.sleep(1.5)
            try:
                with open(RESULT, "r", encoding="utf-8") as r:
                    if "TOTAL" in r.read():     # 汇总行出现即视为脚本跑完
                        done = True
                        break
            except OSError:
                pass
            if p.poll() is not None:            # 进程自己退了：崩了，或者被崩溃看门狗重启
                break
        time.sleep(1.0)
        p.terminate()
        try:
            p.wait(timeout=8)
        except subprocess.TimeoutExpired:
            p.kill()
    return done


def report():
    text = open(LOG, "rb").read().decode("utf-8", "ignore")
    try:
        lines = [ln for ln in open(RESULT, encoding="utf-8").read().splitlines() if ln.strip()]
    except OSError:
        lines = []
    fails = [ln for ln in lines if ln.startswith("FAIL") or ln.startswith("FAIL ")]
    for ln in lines:
        print("  " + ln)
    # 顺手把 PLCUI 自己的报错捞出来
    extra = [ln.split("] ", 1)[-1] for ln in text.splitlines()
             if "E/" in ln and "verify" not in ln]
    if extra:
        print("\n-- 其它错误 --")
        for ln in extra[:15]:
            print("  " + ln)
    print("\nFAIL 行数 = %d" % len(fails))
    return len(fails)


def convert():
    try:
        from PIL import Image
    except ImportError:
        print("没装 Pillow，跳过 BMP→PNG")
        return []
    os.makedirs(PREVIEW, exist_ok=True)
    out = []
    for fn in sorted(os.listdir(SNAP)):
        if not fn.lower().endswith(".bmp"):
            continue
        src = os.path.join(SNAP, fn)
        dst = os.path.join(PREVIEW, "sim_" + fn[:-4] + ".png")
        Image.open(src).convert("RGB").save(dst)
        out.append(dst)
    print("转换 %d 张位图到 preview/sim_*.png" % len(out))
    return out


def main():
    os.makedirs(BUILD, exist_ok=True)
    stage()
    n = clean_dumps()
    if n:
        print("清理 pclogs 崩溃转储 %d 个" % n)

    # PC 模拟器的 load/show 存在偶发段错误竞态（与工程文件数正相关），
    # 所以「跑到出汇总行为止」重试几次，别把竞态当代码 bug。
    ok = False
    for attempt in range(1, 4):
        print("第 %d 次运行模拟器…" % attempt)
        ok = run()
        if ok:
            break
        clean_dumps()
        shutil.rmtree(SNAP, ignore_errors=True)
        os.makedirs(SNAP, exist_ok=True)

    fails = report()
    convert()
    if os.path.exists(LOG):
        shutil.copy(LOG, os.path.join(BUILD, "pc_verify.log"))
    if not ok:
        print("\n!! 三次都没跑到底（模拟器竞态），原始日志见 build/pc_verify.log")
        return 2
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
