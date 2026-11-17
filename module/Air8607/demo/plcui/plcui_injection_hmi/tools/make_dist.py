#!/usr/bin/env python3
"""把工程铺成可直接烧录的平铺目录 dist/luadb（luadb 不支持子目录）。

用法：python tools/make_dist.py
     Luatools 里「选择目录」指向 dist/luadb 即可，不用手工挑 60 个文件。
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE = os.path.join(ROOT, "code")
RES = os.path.join(CODE, "res")
OUT = os.path.join(ROOT, "dist", "luadb")

LUA = ["main.lua", "boot_app.lua", "ui_app.lua", "ui_vars.lua", "data_app.lua",
       "exd_air8607_rgb.lua", "tp_app.lua"]


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    n_lua = 0
    for fn in LUA:
        src = os.path.join(CODE, fn)
        if not os.path.exists(src):
            print("缺少 %s" % fn)
            return 1
        shutil.copy(src, os.path.join(OUT, fn))
        n_lua += 1
    n_res = 0
    for fn in sorted(os.listdir(RES)):
        if fn.startswith("."):
            continue
        shutil.copy(os.path.join(RES, fn), os.path.join(OUT, fn))
        n_res += 1
    total = len(os.listdir(OUT))
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print("dist/luadb: %d 个 lua + %d 个资源 = %d 个文件，%.1f KB"
          % (n_lua, n_res, total, size / 1024.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
