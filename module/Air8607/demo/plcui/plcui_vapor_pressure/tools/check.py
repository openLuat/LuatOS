#!/usr/bin/env python3
"""plcui_vapor_pressure 静态自检（上机前必须全绿）。

按 components/plcui/src/core/luat_plcui_xml.c 的解析规则逐条校验：
属性白名单、颜色写法、整型取值域与必填、布尔字面量、
fit/变换/裁片互斥、font 与 font_size 成对、字号下限、文本字节数、
已知无字形符号、ID 唯一性、组件/页/资源/体积上限、事件处理函数交叉检查、
chart / table / slider 的专属约束、素材命名与像素预算，外加 Lua 语法与代码规范。

用法（工程根目录）：
    python tools/check.py

退出码：0 全绿可上机；1 有阻断项。
"""

import io
import os
import re
import sys
import xml.etree.ElementTree as ET

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CODE = os.path.join(ROOT, "code")
XML = os.path.join(CODE, "main.xml")

MAX_WIDGETS = 512
MAX_PAGES = 16
MAX_RESOURCES = 256
MAX_XML = 256 * 1024
MAX_DEPTH = 16
MAX_TABLE_ROWS = 128
MAX_TABLE_COLS = 16
MAX_TABLE_CELLS = 1024
MAX_CHART_POINTS = 1024
MAX_CHART_SERIES = 8
MAX_ANIM_FRAMES = 64
TEXT_MAX = 512
NAME_MAX = 23
IMG_CACHE = 6 * 1024 * 1024

COMMON = {"id", "x", "y", "w", "h", "hidden", "disabled"}
WIDGETS = {
    "image": {"src", "src-pressed", "src-checked", "src-disabled", "clickable", "on-click",
              "hit-x", "hit-y", "hit-w", "hit-h", "src-x", "src-y", "fit", "zoom",
              "rotation", "pivot-x", "pivot-y", "opacity", "antialias"},
    "label": {"text", "font", "font_size", "color", "align", "long-mode",
              "scroll-duration-ms", "scroll-delay-ms"},
    "textarea": {"text", "font", "font_size", "color", "align", "max-length",
                 "accepted-chars", "keyboard", "one-line", "on-change", "on-submit",
                 "on-cancel"},
    "keyboard": {"layout", "font", "font_size", "ime"},
    "slider": {"min", "max", "value", "step", "orientation", "track-color",
               "indicator-color", "knob-color", "knob-src", "on-change", "on-submit",
               "on-cancel"},
    "table": {"rows", "columns", "col-widths", "col-aligns", "align", "header-align",
              "grid", "row-height", "header", "cell-padding", "header-color",
              "alternate-color", "font", "font_size", "color", "background",
              "border-color", "border-width"},
    "chart": {"type", "point-count", "y-min", "y-max", "hdiv", "vdiv", "line-width",
              "grid-color", "background", "bg-opacity", "border-color", "border-width"},
    "animimg": {"interval-ms", "repeat-count", "auto-start", "on-finished", "on-error"},
    "container": {"background", "bg-opacity", "border-color", "border-width", "radius",
                  "padding"},
}
CHILDREN = {
    "ui": {"resources", "pages"},
    "resources": {"image": {"id", "src"}, "font": {"id", "builtin"}},
    "pages": {"page": {"id", "background"}},
    "chart": {"series": {"id", "color", "values", "hidden"}},
    "table": {"cell": {"row", "column", "text"}},
    "animimg": {"frame": {"src"}},
}
INT = {"x": (-4096, 4096, False), "y": (-4096, 4096, False),
       "w": (1, 4096, True), "h": (1, 4096, True),
       "font_size": (1, 255, False), "opacity": (0, 255, False), "zoom": (1, 4096, False),
       "rotation": (-2 ** 31, 2 ** 31 - 1, False),
       "pivot-x": (-4096, 4096, False), "pivot-y": (-4096, 4096, False),
       "src-x": (0, 4096, False), "src-y": (0, 4096, False),
       "rows": (1, 128, True), "columns": (1, 16, True), "point-count": (2, 1024, True),
       "row": (1, 128, True), "column": (1, 16, True),
       "interval-ms": (20, 60000, False), "repeat-count": (-1, 65535, False),
       "hit-x": (-4096, 4096, False), "hit-y": (-4096, 4096, False),
       "hit-w": (1, 4096, False), "hit-h": (1, 4096, False)}
BOOLS = {"hidden", "disabled", "clickable", "grid", "header", "auto-start", "antialias",
         "one-line"}
COLORS = {"color", "background", "border-color", "header-color", "alternate-color",
          "grid-color", "track-color", "indicator-color", "knob-color"}
FITS = {"stretch", "contain", "cover", "center"}

# 目标固件是 PLCUI 1.0.1（components/plcui 仓库版本是 1.0.2，机器上刷的是 1.0.1）。
# 下面这些是 1.0.2 才新增的属性与组件：1.0.1 解析到时会让**整份 main.xml 加载失败**，
# 现场表现是屏幕全黑、日志只有一行 `Unknown attribute: xxx`（2026-11-17 实际踩过）。
FW_102_ATTRS = {"fit", "zoom", "rotation", "pivot-x", "pivot-y", "opacity",
                "antialias", "src-x", "src-y", "hit-x", "hit-y", "hit-w", "hit-h",
                "min", "max", "value", "step", "orientation", "track-color",
                "indicator-color", "knob-color", "knob-src",
                "interval-ms", "repeat-count", "auto-start", "on-finished", "on-error"}
FW_102_TAGS = {"animimg", "slider"}
# 实测快照（2026-11）：hzfont 无字形，会渲染成空框
NO_GLYPH = "—▣⚠▶✓"

errors = []
warnings = []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def is_int(value):
    return re.fullmatch(r"-?\d+", value) is not None


def is_bool(value):
    return value in ("true", "false")


def is_color(value):
    return re.fullmatch(r"#[0-9A-Fa-f]{6}", value) is not None


def num(el, key, default=0):
    value = el.get(key)
    return int(value) if value is not None and is_int(value) else default


def fsize(el):
    return num(el, "font_size", 16)


# ==================== Lua 侧信息 ====================

def read_lua():
    """返回 {文件名: 源码} 与全部源码拼接串。"""
    files = {}
    for name in sorted(os.listdir(CODE)):
        if name.endswith(".lua"):
            with open(os.path.join(CODE, name), encoding="utf-8") as f:
                files[name] = f.read()
    return files


def lua_syntax(files):
    try:
        from luaparser import ast
    except ImportError:
        warn("未安装 luaparser，跳过 Lua 语法解析（请另跑 luac -p）")
        return
    for name, src in files.items():
        try:
            ast.parse(src)
        except Exception as exc:  # noqa: BLE001
            err("Lua 语法错误 %s: %s" % (name, str(exc).replace("\n", " ")[:200]))


def lua_handlers(src_all):
    names = set(re.findall(r"\bH\.([A-Za-z_][A-Za-z0-9_]*)\s*=", src_all))
    names |= set(re.findall(r'\bH\[\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*\]\s*=', src_all))
    return names


def lua_widget_ids(src_all):
    ids = set()
    ids |= set(re.findall(r'(?:find|set_text|set_src|set_hidden|set_cell)\(\s*"([A-Za-z0-9_]+)"',
                          src_all))
    ids |= set(re.findall(r'\bid\s*=\s*"([A-Za-z0-9_]+)"', src_all))
    for block in re.findall(r"(?:CHIP_ID|card_lamp|card_text)\s*=\s*\{([^}]*)\}", src_all):
        ids |= set(re.findall(r'"([A-Za-z0-9_]+)"', block))
    ids |= set(re.findall(r'(?:[A-Z][A-Z_]*_ID)\s*=\s*"([A-Za-z0-9_]+)"', src_all))
    return ids


def lua_style(files):
    """Lua 代码规范项：命名、require 写法、禁闭包、main.lua 收尾。"""
    for name, src in files.items():
        for lineno, line in enumerate(src.splitlines(), 1):
            code = line.split("--")[0]
            if re.search(r'require\s*\(\s*"', code) or re.search(r'require\s+"', code):
                m = re.search(r'require\s*\(?\s*"([^"]+)"', code)
                if m and ("/" in m.group(1) or m.group(1).endswith(".lua")):
                    err("%s:%d require 不能带路径或扩展名：%s" % (name, lineno, m.group(1)))
            if re.search(r"\blocal\s+M\s*=", code):
                err("%s:%d 模块表名必须是文件名，不许用 local M" % (name, lineno))
            if re.search(r"--.*require.*\"", line) and not code.strip():
                err("%s:%d 注释里出现 require 加引号，打包器会扫成垃圾模块名"
                    % (name, lineno))
            if re.search(r"\bfunction\s*\(", code):
                err("%s:%d 禁止匿名函数，请显式命名后传函数名" % (name, lineno))
            for m in re.finditer(r":(set_size|set_pos|set_crop|clear_crop|set_zoom|"
                                 r"set_rotation|set_pivot|set_opacity|play|pause)\s*\(",
                                 code):
                err("%s:%d `:%s()` 是 PLCUI 1.0.2 的接口，目标固件 1.0.1 没有，"
                    "真机会 attempts to call a nil value" % (name, lineno, m.group(1)))
    if "sys.run()" not in files.get("main.lua", ""):
        err("main.lua 末尾缺 sys.run()（缺了只出 Lua VM exit!! 且无报错）")


# ==================== XML 校验 ====================

def check_widget(el, page_id, seen_ids, res_ids, res_files, handlers):
    tag = el.tag
    wid = el.get("id") or "?"
    where = "[%s/%s]" % (page_id, wid)
    if tag in FW_102_TAGS:
        err("%s 组件 <%s> 是 PLCUI 1.0.2 才有的，目标固件 1.0.1 会让整份 XML 加载失败（黑屏）"
            % (where, tag))
    for key in el.attrib:
        if key in FW_102_ATTRS:
            err("%s 属性 `%s` 是 PLCUI 1.0.2 才有的，1.0.1 报 Unknown attribute 并黑屏"
                % (where, key))
    if tag not in WIDGETS:
        err("%s 不是九种组件：<%s>" % (where, tag))
        return 0
    allow = COMMON | WIDGETS[tag]
    for key in el.attrib:
        if key not in allow:
            err("%s < %s > 未知属性 `%s`（白名单见 SKILL.md 2.2.1）" % (where, tag, key))
    if not el.get("id"):
        err("[%s] <%s> 缺 id" % (page_id, tag))
    elif wid in seen_ids:
        err("%s 组件 id 重复" % where)
    else:
        seen_ids.add(wid)
    if len(wid.encode("utf-8")) > NAME_MAX:
        err("%s 组件 id 超过 %d 字节" % (where, NAME_MAX))

    for key, (lo, hi, required) in INT.items():
        value = el.get(key)
        if value is None:
            if required and key in allow:
                err("%s 缺必填整型属性 `%s`" % (where, key))
            continue
        if key not in allow:
            continue
        if not is_int(value):
            err("%s `%s` 不是整数：%s" % (where, key, value))
        elif not (lo <= int(value) <= hi):
            err("%s `%s=%s` 越界（%d~%d）" % (where, key, value, lo, hi))

    for key in BOOLS:
        if el.get(key) is not None and not is_bool(el.get(key)):
            err("%s `%s` 只能写 true/false" % (where, key))
    for key in COLORS:
        value = el.get(key)
        if value is not None and key in allow and not is_color(value):
            err("%s `%s` 必须写 #RRGGBB（7 字符）：%s" % (where, key, value))

    manual = [k for k in ("zoom", "rotation", "pivot-x", "pivot-y") if el.get(k) is not None]
    if manual and el.get("fit") != "center":
        err("%s 用了 %s 必须 fit=\"center\"" % (where, manual))
    if (el.get("pivot-x") is None) != (el.get("pivot-y") is None):
        err("%s pivot-x / pivot-y 必须成对写" % where)
    if (el.get("src-x") is None) != (el.get("src-y") is None):
        err("%s src-x / src-y 必须成对写" % where)
    if el.get("src-x") is not None and (manual or el.get("fit")):
        err("%s 裁片 src-x/y 不能与 fit/变换同时用" % where)
    if el.get("fit") is not None and el.get("fit") not in FITS:
        err("%s fit 只有 %s" % (where, sorted(FITS)))
    if el.get("font_size") is not None and el.get("font") is None:
        err("%s font_size 必须与 font=\"hzfont\" 成对写" % where)
    if el.get("font_size") is not None and num(el, "font_size") < 16:
        err("%s 字号 %s < 16（本技能下限）" % (where, el.get("font_size")))
    if tag == "label" and el.get("text") is not None:
        if len(el.get("text").encode()) >= TEXT_MAX:
            err("%s text 超过 511 字节" % where)
    if tag == "image":
        if not el.get("src"):
            err("%s image 缺 src" % where)
        for key in ("src", "src-pressed", "src-checked", "src-disabled"):
            ref = el.get(key)
            if ref and ref not in res_ids:
                err("%s %s=`%s` 未在 <resources> 声明" % (where, key, ref))
        if el.get("on-click") and el.get("clickable") != "true":
            err("%s 有 on-click 必须 clickable=\"true\"" % where)
        if el.get("on-click") and (num(el, "w") < 48 or num(el, "h") < 48):
            warn("%s 可点按钮 %dx%d < 48x48，手指易误触" % (where, num(el, "w"), num(el, "h")))
    for key in ("on-click", "on-change", "on-submit", "on-cancel", "on-finished",
                "on-error"):
        name = el.get(key)
        if not name:
            continue
        if not name.isidentifier():
            err("%s 事件名 `%s` 不是合法 Lua 函数名" % (where, name))
        elif name not in handlers:
            err("%s 事件 `%s` 在 Lua 里找不到同名处理函数（会 E_HANDLER）" % (where, name))

    if tag == "table":
        rows, cols = num(el, "rows"), num(el, "columns")
        if rows * cols > MAX_TABLE_CELLS:
            err("%s rows×columns=%d > %d" % (where, rows * cols, MAX_TABLE_CELLS))
        rh = num(el, "row-height")
        if rh and rh * rows > num(el, "h"):
            err("%s rows×row-height=%d > h=%d（会截掉下面几行）"
                % (where, rh * rows, num(el, "h")))
        widths = el.get("col-widths")
        if widths and len(widths.split(",")) != cols:
            err("%s col-widths 段数 %d ≠ columns=%d"
                % (where, len(widths.split(",")), cols))
        aligns = el.get("col-aligns")
        if aligns and len(aligns.split(",")) != cols:
            err("%s col-aligns 段数 %d ≠ columns=%d"
                % (where, len(aligns.split(",")), cols))
        if widths and sum(int(v) for v in widths.split(",")) > num(el, "w"):
            warn("%s col-widths 合计超过组件宽度 w=%d" % (where, num(el, "w")))
    if tag == "chart":
        if el.get("type") not in (None, "line", "bar"):
            err("%s chart type 只有 line/bar" % where)
        lo, hi = el.get("y-min"), el.get("y-max")
        if lo is not None and hi is not None and int(lo) >= int(hi):
            err("%s y-min ≥ y-max" % where)
        if lo is not None and not (-1000 <= int(lo) <= 1000):
            err("%s y-min 超出 -1000~1000" % where)
        if hi is not None and not (-1000 <= int(hi) <= 1000):
            err("%s y-max 超出 -1000~1000" % where)
        points = num(el, "point-count")
        series = [c for c in el if c.tag == "series"]
        if not series:
            err("%s chart 至少要一条 series" % where)
        if len(series) > MAX_CHART_SERIES:
            err("%s series %d > %d" % (where, len(series), MAX_CHART_SERIES))
        seen = set()
        for s in series:
            sid = s.get("id")
            if not sid:
                err("%s series 缺 id" % where)
            elif sid in seen:
                err("%s series id 重复：%s" % (where, sid))
            seen.add(sid)
            values = (s.get("values") or "").strip()
            if values:
                parts = values.split(",")
                if len(parts) != points:
                    err("%s series `%s` 点数 %d ≠ point-count=%d"
                        % (where, sid, len(parts), points))
                for v in parts:
                    try:
                        fv = float(v)
                    except ValueError:
                        err("%s series `%s` 值非法：%s" % (where, sid, v))
                        break
                    if not -1000 <= fv <= 1000:
                        err("%s series `%s` 值 %s 超出 -1000~1000" % (where, sid, v))
                        break
    if tag == "slider":
        lo, hi = el.get("min"), el.get("max")
        if lo is not None and hi is not None and int(lo) >= int(hi):
            err("%s slider min ≥ max" % where)
        knob = el.get("knob-src")
        if knob:
            path = os.path.join(CODE, res_files.get(knob, ""))
            if os.path.exists(path):
                iw, ih = Image.open(path).size
                if iw != ih:
                    err("%s knob-src 必须正方形，实测 %dx%d" % (where, iw, ih))
                elif num(el, "h") and iw != num(el, "h"):
                    err("%s knob 边长 %d 应等于滑块短边 h=%d" % (where, iw, num(el, "h")))
    if tag == "animimg":
        frames = [c for c in el if c.tag == "frame"]
        if not 2 <= len(frames) <= MAX_ANIM_FRAMES:
            err("%s animimg 需要 2~%d 帧，实际 %d 帧"
                % (where, MAX_ANIM_FRAMES, len(frames)))
        for c in frames:
            src = c.get("src")
            if not src:
                err("%s <frame> 缺 src" % where)
            elif src not in res_ids:
                err("%s <frame src=%s> 未在 <resources> 声明" % (where, src))
    if tag == "keyboard" and (num(el, "w") == 0 or num(el, "h") == 0):
        err("%s keyboard 必须给真实像素尺寸" % where)
    if el.get("hit-w") is not None:
        hx, hy = num(el, "hit-x"), num(el, "hit-y")
        hw, hh = num(el, "hit-w"), num(el, "hit-h")
        if hx < 0 or hy < 0 or hx + hw > num(el, "w") or hy + hh > num(el, "h"):
            err("%s 热区 (%d,%d,%d,%d) 超出组件 %dx%d"
                % (where, hx, hy, hw, hh, num(el, "w"), num(el, "h")))
    for key in ("text",):
        value = el.get(key) or ""
        bad = sorted({c for c in value if c in NO_GLYPH})
        if bad:
            err("%s `%s` 含 hzfont 无字形符号 %s（会渲染成空框）" % (where, key, bad))

    count = 1
    for child in el:
        if tag == "container":
            count += check_widget(child, page_id, seen_ids, res_ids, res_files, handlers)
        elif tag in CHILDREN and child.tag in CHILDREN[tag]:
            for ck in child.attrib:
                if ck not in CHILDREN[tag][child.tag]:
                    err("%s <%s> 未知属性 `%s`" % (where, child.tag, ck))
            bad = sorted({c for c in (child.get("text") or "") if c in NO_GLYPH})
            if bad:
                err("%s <%s> text 含无字形符号 %s" % (where, child.tag, bad))
            color = child.get("color")
            if color is not None and not is_color(color):
                err("%s <%s> color 必须写 #RRGGBB：%s" % (where, child.tag, color))
        else:
            err("%s <%s> 不允许子节点 <%s>" % (where, tag, child.tag))
    return count


def main():
    if not os.path.exists(XML):
        print("找不到 %s，先跑 python tools/gen_xml.py" % XML)
        return 1
    data = open(XML, "rb").read()
    if len(data) > MAX_XML:
        err("XML 体积 %d > %d 字节" % (len(data), MAX_XML))
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        print("XML 解析失败：", exc)
        return 1

    files = read_lua()
    src_all = "\n".join(files.values())
    handlers = lua_handlers(src_all)

    if root.tag != "ui":
        err("根元素是 <%s>，必须是 <ui>" % root.tag)
    if root.get("version") != "0.1":
        err("version 必须是 0.1")
    for key in ("width", "height", "entry"):
        if not root.get(key):
            err("<ui> 缺 %s" % key)
    page_w, page_h = num(root, "width", 1024), num(root, "height", 600)

    order = [c.tag for c in root]
    if "resources" in order and "pages" in order and order.index("resources") > order.index("pages"):
        err("<resources> 必须写在 <pages> 之前")

    res_ids, res_files, res_bytes = set(), {}, {}
    total_res = 0
    for res in list(root.findall("./resources/image")) + list(root.findall("./resources/font")):
        total_res += 1
        rid = res.get("id")
        if not rid:
            err("<resources> 子节点缺 id")
            continue
        if rid in res_ids:
            err("资源 id 重复：%s" % rid)
        res_ids.add(rid)
        if res.tag == "image":
            name = res.get("src")
            if not name:
                err("资源 %s 缺 src" % rid)
                continue
            res_files[rid] = name
            if "/" in name or "\\" in name:
                err("资源 %s 的 src 带目录：%s" % (rid, name))
            if ".." in name:
                err("资源 %s 的 src 含 .." % (rid, name))
            if len(name.encode()) > NAME_MAX:
                err("资源文件名超 %d 字节：%s" % (NAME_MAX, name))
            path = os.path.join(CODE, name)
            if not os.path.exists(path):
                err("资源 %s 的文件不存在：%s" % (rid, name))
                continue
            w, h = Image.open(path).size
            if w < 1 or h < 1:
                err("资源 %s 尺寸非法：%dx%d" % (rid, w, h))
            res_bytes[rid] = w * h * 4
    if total_res > MAX_RESOURCES:
        err("资源 %d > %d" % (total_res, MAX_RESOURCES))

    for name in os.listdir(CODE):
        path = os.path.join(CODE, name)
        if os.path.isdir(path):
            err("code 目录不许有子目录（luadb 会抹平）：%s/" % name)
        elif len(name.encode()) > NAME_MAX:
            err("code 目录下文件名超 %d 字节：%s" % (NAME_MAX, name))
    lower = {}
    for name in os.listdir(CODE):
        lower.setdefault(name.lower(), []).append(name)
    for group in lower.values():
        if len(group) > 1:
            err("文件名大小写重名（luadb 抹平后会撞）：%s" % sorted(group))

    pages = root.findall("./pages/page")
    if len(pages) > MAX_PAGES:
        err("页数 %d > %d" % (len(pages), MAX_PAGES))
    if root.get("entry") and not any(p.get("id") == root.get("entry") for p in pages):
        err("entry=%s 没有对应 page" % root.get("entry"))

    total_widgets = 0
    all_ids = set()
    used_handlers = set()
    for page in pages:
        pid = page.get("id") or "?"
        if not page.get("id"):
            err("<page> 缺 id")
        bg = page.get("background")
        if bg is not None and not is_color(bg):
            err("[%s] page 的 background 必须是 #RRGGBB 颜色，不是资源 ID：%s" % (pid, bg))
        seen = set()
        for widget in page:
            total_widgets += check_widget(widget, pid, seen, res_ids, res_files, handlers)
            for key, value in widget.attrib.items():
                if key.startswith("on-"):
                    used_handlers.add(value)
        all_ids |= seen
        if len(page) > 120:
            warn("[%s] 单页 %d 个组件，超出 100~120 的单页预算" % (pid, len(page)))
        labels = list(page.iter("label"))
        mx = max([fsize(e) for e in labels], default=0)
        if mx and not any(num(e, "x") < page_w // 6 and num(e, "y") < page_h // 6
                          and fsize(e) >= 24 for e in labels):
            warn("[%s] 缺页身份标签：上 1/6 高内应有字号 ≥ 24 的页名 label" % pid)
        if mx and len([e for e in labels if fsize(e) == mx]) > 2:
            warn("[%s] 并列最大字号 label 超过 2 个，重点不突出" % pid)

    if total_widgets > MAX_WIDGETS:
        err("组件累计 %d > %d（整份文档跨页相加）" % (total_widgets, MAX_WIDGETS))
    if total_widgets > MAX_WIDGETS * 0.8:
        warn("组件累计 %d，已到上限 80%%" % total_widgets)

    # 解码像素：PLCUI 的 6MiB 缓存按需换入换出，真机同时只驻留当前页，
    # 因此按「单页可见像素」卡红线；整份文档总量只提示（同 plcui_water_supply）。
    page_bytes = {}
    for page in pages:
        ids = set()
        for el in page.iter():
            for key in ("src", "src-pressed", "src-checked", "src-disabled", "knob-src"):
                rid = el.get(key)
                if rid in res_bytes:
                    ids.add(rid)
        page_bytes[page.get("id") or "?"] = sum(res_bytes[r] for r in ids)
    for pid, value in sorted(page_bytes.items()):
        if value > IMG_CACHE:
            err("[%s] 单页解码像素 %.2f MiB > 6MiB 图片缓存" % (pid, value / 1048576.0))
        elif value > IMG_CACHE * 0.8:
            warn("[%s] 单页解码像素 %.2f MiB，已接近 6MiB" % (pid, value / 1048576.0))
    used_bytes = sum(res_bytes.values())
    if used_bytes > IMG_CACHE:
        warn("全文解码像素 %.2f MiB，靠分页换入换出（与 plcui_water_supply 同策略）"
             % (used_bytes / 1048576.0))

    # 素材引用完整性：声明了没用到 / 目录里有没用上的图
    referenced = set()
    for el in root.iter():
        for key in ("src", "src-pressed", "src-checked", "src-disabled", "knob-src"):
            if el.get(key):
                referenced.add(el.get(key))
    # 运行时 set_src 切换的素材只出现在 Lua 表里，也要算作已引用
    lua_literals = set(re.findall(r'"([A-Za-z0-9_]+)"', src_all))
    for lit in lua_literals:
        if lit in res_files:
            referenced.add(lit)
    for lit in sorted(lua_literals):
        if re.fullmatch(r"(im|st\d|bt)_[A-Za-z0-9_]+", lit) and lit not in res_files \
                and lit not in all_ids:
            err("Lua 引用了未声明的资源 %s（set_src 会 E_RESOURCE）" % lit)
        if re.fullmatch(r"(mv|pv|ts|rk|stp|tb)_[A-Za-z0-9_]+", lit) and lit not in all_ids:
            if not any(wid.startswith(lit) for wid in all_ids):
                err("Lua 引用了不存在的组件 ID：%s" % lit)
    # 事件分派表里的键（STAGE_OF / DEV / LOCK 等）也是组件 ID
    for key in sorted(set(re.findall(r"\b(mv_[a-z0-9_]+)\s*=", src_all))):
        if key not in all_ids:
            err("Lua 分派表里的组件 ID 不存在：%s" % key)
    for rid in sorted(res_files):
        if rid not in referenced:
            warn("资源 %s 已声明但没有任何组件引用（G3 只导出用到的）" % rid)
    for name in sorted(os.listdir(CODE)):
        if name.endswith((".png", ".jpg")) and name.rsplit(".", 1)[0] not in res_files:
            warn("素材 %s 未被 main.xml 引用（应删掉或补上引用）" % name)

    # Lua 交叉检查
    lua_syntax(files)
    lua_style(files)
    for name in sorted(used_handlers):
        if name not in handlers:
            err("事件 `%s` 在 ui_app.lua 的 handlers 表里没有同名函数" % name)
    for wid in sorted(lua_widget_ids(src_all)):
        if wid not in all_ids and not wid.startswith(("im_", "st", "bt_")):
            err("Lua 引用了不存在的组件 ID：%s" % wid)
    for fname in ("main.lua", "boot_app.lua", "ui_app.lua", "ui_vars.lua", "vp_app.lua",
                  "tp_app.lua", "exd_air8607_rgb.lua"):
        if fname not in files:
            err("缺少源文件 code/%s" % fname)

    # 字形报告：把用到的非 ASCII 字符列出来，便于人工核对字形表
    chars = set()
    for el in root.iter():
        for key in ("text",):
            for ch in el.get(key) or "":
                if ord(ch) > 127:
                    chars.add(ch)
    syms = sorted(c for c in chars if not ("\u4e00" <= c <= "\u9fff"))

    print("--- 页面 %d  组件 %d/%d  资源 %d/%d  XML %dB  事件 %d  解码像素 %.2f MiB ---"
          % (len(pages), total_widgets, MAX_WIDGETS, total_res, MAX_RESOURCES,
             len(data), len(used_handlers), used_bytes / 1048576.0))
    print("--- 单页解码：%s ---" % "  ".join(
        "%s %.2f" % (k, v / 1048576.0) for k, v in sorted(page_bytes.items())))
    print("--- 界面非中文字符：%s ---" % ("".join(syms) if syms else "无"))
    for msg in warnings:
        print("WARN ", msg)
    for msg in errors:
        print("ERROR", msg)
    print("结果：", "全绿，可以上机" if not errors else "%d 条阻断，不许上机" % len(errors))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
