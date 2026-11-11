"""把 code/ 打成一个烧录目录：脚本 + main.xml + 图片全部进 /luadb。

plcui 只接受**相对于 XML 目录**的图片路径（src 不支持 / 开头或 ..），
所以 main.xml 必须和全部图片放在同一个目录。源码里它们组织在 code/res/，
烧录时把 code/ 下所有文件**平铺**进 dist/luadb（luadb 打包不保留子目录），
main.lua 与图片同层，按 /luadb/main.xml 加载。

    python tools/make_flash_pack.py

输出：
    dist/luadb/   *.lua + main.xml + 图片   烧到 /luadb   （约 1.2 MB）
"""

import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CODE = os.path.join(ROOT, "code")
DIST = os.path.join(ROOT, "dist")
NAME_MAX = 23


def main():
    if not os.path.isdir(CODE):
        print("缺少 code 目录")
        return 1

    out_dir = os.path.join(DIST, "luadb")
    root_dir = os.path.join(DIST, "root")
    for d in (out_dir, root_dir):
        if os.path.isdir(d):
            shutil.rmtree(d)
    os.makedirs(out_dir)

    total = 0
    long_names = []
    # code/ 递归收集，全部平铺进 dist/luadb：lua 脚本 + main.xml + 图片同层。
    # plcui 的 src 用裸文件名，加载时按 XML 所在目录（/luadb）拼接。
    for sub, _, files in os.walk(CODE):
        for f in sorted(files):
            src_f = os.path.join(sub, f)
            if len(f.encode("utf-8")) > NAME_MAX:
                long_names.append(f)
            shutil.copy2(src_f, os.path.join(out_dir, f))
            total += os.path.getsize(src_f)

    print(f"dist/luadb  : {len(os.listdir(out_dir))} 个文件, {total / 1024:.1f} KB")
    if long_names:
        print("!! 超长文件名:", long_names)
        return 1
    print("把 dist/luadb 的内容烧到 /luadb 即可（脚本 + main.xml + 图片同层平铺）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
