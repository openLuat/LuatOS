# -*- coding: utf-8 -*-
"""AirUI 应用层铁律静态扫描（改完代码先跑这个，再进模拟器）。

检查项（都是本项目真机/模拟器踩过的坑）：
  R1  禁用 airui.button 做热区（自带 2px 描边，且历史版本有只 hide 不 open 的问题）
  R2  禁用 hide() / open() / show() 做显隐（真机上恢复不回来）
  R3  容器禁传 border_color（描边不吃 opacity，会留幽灵框）
  R4  定时器延迟必须 >= 5ms（timerStart(fn, 0) 会静默失败）
  R5  禁用 timerLoopStart 做帧循环（只允许 wdt.feed）
  R6  字号 >= 16（hzfont 小字号中文会糊）
  R7  禁用 obj:is_destroyed()（本固件对活着的 container 也返回 true，会吃掉全部点击）
  R8  require 必须是字面量（打包工具按静态依赖裁剪，动态 require 会漏文件）
  R9  贴图名必须符合构建期契约（ch_<theme>_<i>_big|sm / st_<theme>_<k> / ic_<name>）且文件真实存在
  R10 文字字号只能是 40/26/22/20/16 五级（hzfont 最小 16，层级多了界面会散）
  R11 一行只能写一个 require（烧录工具按行抓 require，写一行会被拼成一个模块名）
  R12 文案里禁用 hzfont 没有的数学符号（U+2212 减号等，真机上是豆腐块）

用法： python check_rules.py [--strict]
"""
import glob
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
CODE = os.path.join(os.path.dirname(HERE), "code")
PNG_DIR = CODE

RULES = [
    ("R1", re.compile(r"airui\.button\s*[({]"), "热区只能用透明 container + 闭包，禁 airui.button"),
    ("R2", re.compile(r":\s*(hide|open|show)\s*\("), "显隐只改 alpha + 关命中，禁 hide/open/show"),
    ("R3", re.compile(r"border_color"), "容器禁传 border_color（会留幽灵描边）"),
    ("R4", re.compile(r"timerStart\s*\([^,]*,\s*([0-4])\s*\)"), "定时器延迟必须 >= 5ms"),
    ("R5", re.compile(r"timerLoopStart"), "禁用 timerLoopStart 做帧循环（wdt.feed 除外）"),
    ("R6", re.compile(r"font_size\s*=\s*(?:[1-9]|1[0-5])\b"), "字号必须 >= 16"),
    ("R7", re.compile(r"is_destroyed"), "本固件 is_destroyed 对活控件也返回 true，改用代次(epoch)"),
    ("R8", re.compile(r"require\s*\(\s*[^\"'\s]"), "require 必须写字面量模块名"),
]

ALLOW = {
    "R5": ["main.lua"],       # wdt.feed 的 timerLoopStart 是允许的
}

# R2 的唯一例外：airui.keyboard 是固件弹层，只能用 show()/hide() 唤出与收起
# （它不是普通 container，没有可切的 alpha 通道）。
R2_ALLOW = re.compile(r"\bkb\s*:\s*(show|hide|open)\s*\(")

# R9：贴图命名契约（与 docs/gen_assets.py 的产物一一对应）
ASSET_RX = re.compile(r"^((ch_(toy|bear|hero|pocket|sheep)_[0-4]_(big|sm))"
                      r"|(st_(toy|bear|hero|pocket|sheep)_[0-5])"
                      r"|(ic_[a-z]+))$")
ASSET_LITERAL = re.compile(r"\"((?:ch|st|ic)_[A-Za-z0-9_]+)\"")

# R10：文字字号白名单（符号/图标字号走 M.icon 的 size 参数，不在此列）
TEXT_SIZE = re.compile(r"W\.(?:text|text_mid)\([^\n]*?\bsize\s*=\s*(\d+)")
FONT_OK = {40, 26, 22, 20, 16}

# R11：烧录工具的依赖扫描是按行抓 `require "xxx"` 的，同一行写多个会被拼成一个模块名，
# 报错形如「缺少 page_room", require "page_light", require "page_story", require "page_star.lua」。
REQUIRE_CALL = re.compile(r"\brequire\s*[\(\"']")

# R12：hzfont 是中文矢量字库，数学符号（− U+2212 / × ÷ ≤ ≥ ≈ ≠）没有字形，真机渲染成方框。
# 减号一律用 ASCII "-"，乘号用 "x" 或图标。
BAD_GLYPH = re.compile("[\u2212\u00d7\u00f7\u2264\u2265\u2248\u2260]")

TARGETS = sorted(glob.glob(os.path.join(CODE, "*.lua")))


def strip_comments(lines):
    """去掉行注释与 --[[ ]] 块注释，避免注释里的示例文字被当成代码命中"""
    out, in_block = [], False
    for line in lines:
        buf = ""
        i = 0
        while i < len(line):
            if in_block:
                if line.startswith("]]", i):
                    in_block = False
                    i += 2
                else:
                    i += 1
            else:
                if line.startswith("--[[", i):
                    in_block = True
                    i += 4
                elif line.startswith("--", i):
                    break
                else:
                    buf += line[i]
                    i += 1
        out.append(buf)
    return out


def main():
    strict = "--strict" in sys.argv
    bad = 0
    for path in TARGETS:
        name = os.path.basename(path)
        lines = open(path, encoding="utf-8").read().splitlines()
        for no, line in enumerate(strip_comments(lines), 1):
            code = line
            for rid, rx, desc in RULES:
                if rid in ALLOW and name in ALLOW[rid]:
                    continue
                if rid == "R2" and R2_ALLOW.search(code):
                    continue
                if rx.search(code):
                    bad += 1
                    print("%s:%d  [%s] %s\n    %s" % (name, no, rid, desc, line.strip()))

            # R9：贴图名字面量必须符合契约，且构建期真的产出过这张图
            for m in ASSET_LITERAL.finditer(code):
                asset = m.group(1)
                if not ASSET_RX.match(asset):
                    bad += 1
                    print("%s:%d  [R9] 贴图名不符合契约（ch_<theme>_<i>_big|sm / st_<theme>_<k> / ic_<name>）\n    %s"
                          % (name, no, asset))
                elif not os.path.isfile(os.path.join(PNG_DIR, asset + ".png")):
                    bad += 1
                    print("%s:%d  [R9] 贴图文件不存在（先跑 gen_assets.py）\n    %s"
                          % (name, no, asset + ".png"))

            # R10：文字字号只能是五级
            for m in TEXT_SIZE.finditer(code):
                if int(m.group(1)) not in FONT_OK:
                    bad += 1
                    print("%s:%d  [R10] 文字字号只能取 40/26/22/20/16\n    %s" % (name, no, line.strip()))

            # R11：一行只能有一个 require（烧录工具按行抓依赖，多个会被拼坏）
            if len(REQUIRE_CALL.findall(code)) > 1:
                bad += 1
                print("%s:%d  [R11] 一行只能写一个 require，否则烧录时报「缺少 xxx\", require ...」\n    %s"
                      % (name, no, line.strip()))

            # R12：hzfont 没有的数学符号
            for m in BAD_GLYPH.finditer(code):
                bad += 1
                print("%s:%d  [R12] 符号 U+%04X 在 hzfont 里没有字形（真机是方框），减号请用 ASCII \"-\"\n    %s"
                      % (name, no, ord(m.group(0)), line.strip()))

    print("\n扫描文件 %d 个，命中 %d 处" % (len(TARGETS), bad))
    if strict and bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
