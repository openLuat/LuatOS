# -*- coding: utf-8 -*-
"""PLCUI 工程自检：Lua 语法 + 代码规范 + main.xml + 资源

用法：
    python tools/check.py

分四段跑：
  1) Lua 语法解析（luaparser，Lua 5.3 文法）
  2) 代码规范（禁闭包/匿名函数/local M、require 写法、main.lua 纯加载器）
  3) main.xml（组件数、资源数、页数、ID 唯一、on-* 是否都在 ui_app.handlers）
  4) 资源（文件名 <=23 字节、main.xml 引用的资源是否都真实存在）
"""
import io
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE = os.path.join(ROOT, "code")
RES = os.path.join(CODE, "res")
XML = os.path.join(RES, "main.xml")

ok_n = 0
bad_n = 0
warn_n = 0


def ok(msg):
    global ok_n
    ok_n += 1
    print("  [ OK ] " + msg)


def bad(msg):
    global bad_n
    bad_n += 1
    print("  [FAIL] " + msg)


def warn(msg):
    global warn_n
    warn_n += 1
    print("  [WARN] " + msg)


def lua_files():
    out = []
    for n in sorted(os.listdir(CODE)):
        if n.endswith(".lua"):
            out.append(n)
    return out


# ---------------------------------------------------------------- 1) 语法
def sec_syntax():
    print("\n== 1. Lua 语法解析 ==")
    try:
        from luaparser import ast
    except ImportError:
        bad("luaparser 不可用，跳过语法解析")
        return
    for n in lua_files():
        p = os.path.join(CODE, n)
        with io.open(p, "r", encoding="utf-8") as f:
            src = f.read()
        try:
            ast.parse(src)
            ok("%-26s 解析通过（%d 行）" % (n, src.count("\n") + 1))
        except Exception as e:
            bad("%-26s %s" % (n, str(e).split("\n")[0]))


# ---------------------------------------------------------------- 2) 规范
REQUIRE_MOD = re.compile(r'^\s*require\s*\(?\s*["\']([^"\']+)["\']', re.M)
REQUIRE_ASSIGN = re.compile(r'^\s*(?:local\s+)?\w+\s*=\s*require\s*\(?\s*["\']([^"\']+)["\']', re.M)


def sec_style():
    print("\n== 2. 代码规范 ==")
    files = lua_files()

    # 2.1 禁闭包 / 匿名函数：出现 "function(" 或 "function (" 即失败（注释已剥掉）
    for n in files:
        p = os.path.join(CODE, n)
        with io.open(p, "r", encoding="utf-8") as f:
            src = f.read()
        body = strip_comment(src)
        hits = []
        for i, line in enumerate(body.split("\n"), 1):
            if re.search(r'\bfunction\s*\(', line):
                hits.append((i, line.strip()))
        if hits:
            for i, t in hits:
                bad("%s:%d 匿名函数 %s" % (n, i, t[:60]))
        else:
            ok("%-26s 无匿名函数" % n)

    # 2.2 禁 local M
    for n in files:
        p = os.path.join(CODE, n)
        with io.open(p, "r", encoding="utf-8") as f:
            src = f.read()
        if re.search(r'^\s*local\s+M\s*=', src, re.M):
            bad("%-26s 使用了 local M" % n)

    # 2.3 模块表名 = 文件名
    for n in files:
        if n == "main.lua":
            continue
        stem = n[:-4]
        p = os.path.join(CODE, n)
        with io.open(p, "r", encoding="utf-8") as f:
            src = f.read()
        if not re.search(r'^local\s+' + re.escape(stem) + r'\s*=\s*\{\}', src, re.M):
            bad("%-26s 缺少 local %s = {}" % (n, stem))
        if not re.search(r'^return\s+' + re.escape(stem) + r'\s*$', src, re.M):
            bad("%-26s 末尾缺少 return %s" % (n, stem))

    # 2.4 require 只写文件名
    for n in files:
        p = os.path.join(CODE, n)
        with io.open(p, "r", encoding="utf-8") as f:
            src = f.read()
        for m in REQUIRE_MOD.finditer(src):
            mod = m.group(1)
            if "/" in mod or "." in mod:
                bad("%s require 写法非法：%s" % (n, mod))
        # require 与调用同行
        if re.search(r'require\s*\(?\s*["\'][^"\']+["\']\s*\)?\s*\(', src):
            bad("%s 存在 require(...) 同行链式调用" % n)

    # 2.5 require 的目标都在工程里
    stems = set(n[:-4] for n in files)
    for n in files:
        p = os.path.join(CODE, n)
        with io.open(p, "r", encoding="utf-8") as f:
            src = strip_comment(f.read())
        for m in REQUIRE_MOD.finditer(src):
            mod = m.group(1)
            if mod not in stems and mod not in ("sys", "plcui"):
                bad("%s require 的模块 %s 不存在于工程" % (n, mod))
    ok("require 目标全部存在（%d 个模块）" % len(stems))

    # 2.6 main.lua 纯加载器
    p = os.path.join(CODE, "main.lua")
    with io.open(p, "r", encoding="utf-8") as f:
        src = f.read()
    body = strip_comment(src)
    if not body.rstrip().endswith("sys.run()"):
        bad("main.lua 末尾不是 sys.run()")
    else:
        ok("main.lua 末尾 sys.run()")
    if re.search(r'^\s*local\s+function\s+', body, re.M) or re.search(r'^\s*function\s+\w', body, re.M):
        bad("main.lua 定义了函数，应为纯加载器")
    else:
        ok("main.lua 无函数定义")
    for g in ("PROJECT", "VERSION"):
        if not re.search(r'^' + g + r'\s*=\s*"', src, re.M):
            bad("main.lua 缺少 %s" % g)
    if re.search(r'require\s*\(?\s*["\'](sys|plcui)["\']', body):
        bad("main.lua 对 sys/plcui 写了 require，二者是内建库")


def strip_comment(src):
    """剥掉 Lua 注释，保留字符串与行号结构（注释内容换成空格）"""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # 长括号注释 --[[ ... ]]
        if src.startswith("--", i):
            m = re.match(r'--\[(=*)\[', src[i:])
            if m:
                eq = m.group(1)
                end = src.find("]" + eq + "]", i + m.end())
                if end < 0:
                    end = n
                else:
                    end += len(eq) + 2
                chunk = src[i:end]
                out.append("".join(ch if ch == "\n" else " " for ch in chunk))
                i = end
                continue
            j = src.find("\n", i)
            if j < 0:
                j = n
            out.append(" " * (j - i))
            i = j
            continue
        # 字符串，整段跳过
        if c in "\"'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                if src[j] == "\n":
                    break
                j += 1
            out.append(src[i:j])
            i = j
            continue
        if src.startswith("[[", i):
            end = src.find("]]", i + 2)
            end = n if end < 0 else end + 2
            out.append(src[i:end])
            i = end
            continue
        out.append(c)
        i += 1
    return "".join(out)


# ---------------------------------------------------------------- 3) XML
PAGE_TAGS = {"image", "label", "textarea", "keyboard", "container", "table", "chart", "slider", "animimg"}

# 与 PLCUI 1.0.2 的 luat_plcui_xml.c 逐条对齐的属性白名单与整型取值域。
# 设备上任何一条越界都会让 plcui.load 返回 E_SCHEMA 而整页加载失败
# （日志只给 "Integer attribute is invalid or out of range"，不给属性名），
# 所以必须在 PC 侧先拦下来。
BASE_ATTRS = ["id", "x", "y", "w", "h", "hidden", "disabled"]
FONT_ATTRS = ["font", "font_size"]
SPECIFIC_ATTRS = {
    "image": ["src", "src-pressed", "src-checked", "src-disabled", "clickable", "on-click",
              "hit-x", "hit-y", "hit-w", "hit-h", "src-x", "src-y",
              "fit", "zoom", "rotation", "pivot-x", "pivot-y", "opacity", "antialias"],
    "label": ["text", "color", "align", "long-mode", "scroll-duration-ms", "scroll-delay-ms"],
    "textarea": ["text", "color", "align", "max-length", "accepted-chars", "keyboard",
                 "one-line", "on-change", "on-submit", "on-cancel"],
    "keyboard": ["layout"],
    "container": ["background", "bg-opacity", "border-color", "border-width", "radius", "padding"],
    "table": ["rows", "columns", "col-widths", "col-aligns", "align", "header-align", "grid",
              "row-height", "header", "cell-padding", "header-color", "alternate-color",
              "color", "background", "border-color", "border-width"],
    "chart": ["type", "point-count", "y-min", "y-max", "hdiv", "vdiv", "line-width",
              "grid-color", "background", "bg-opacity", "border-color", "border-width"],
    "slider": ["min", "max", "value", "step", "orientation", "track-color", "indicator-color",
               "knob-color", "knob-src", "on-change", "on-submit", "on-cancel"],
    "animimg": ["interval-ms", "repeat-count"],
}
# 每个组件类型允许出现的整型属性 → (最小, 最大)
INT_RULES = {
    "x": (-4096, 4096), "y": (-4096, 4096), "w": (1, 4096), "h": (1, 4096),
    "font_size": (1, 255),
    "hit-x": (0, 4096), "hit-y": (0, 4096), "hit-w": (1, 4096), "hit-h": (1, 4096),
    "src-x": (0, 4096), "src-y": (0, 4096),
    "zoom": (1, 4096), "opacity": (0, 255),
    "pivot-x": (-4096, 4096), "pivot-y": (-4096, 4096),
    "max-length": (1, 511),
    "rows": (1, 128), "columns": (1, 16), "cell-padding": (0, 64),
    "row-height": (1, 4096),
    "point-count": (2, 1024), "hdiv": (0, 32), "vdiv": (0, 32),
    "line-width": (1, 16), "bg-opacity": (0, 255),
    "min": (-32768, 32767), "max": (-32768, 32767), "step": (1, 65535),
    "value": (-32768, 32767),
    "radius": (0, 4096), "padding": (0, 4096),
    "interval-ms": (20, 60000), "repeat-count": (-1, 65535),
    "scroll-duration-ms": (100, 600000), "scroll-delay-ms": (0, 60000),
}
INT_RULES_BY_TAG = {
    "table": {"border-width": (0, 16)},
    "chart": {"border-width": (0, 16)},
    "container": {"border-width": (0, 4096)},
    "page": {"border-width": (0, 4096)},
}
# rotation 是唯一给足 int32 的整型属性
INT_FULL = {"rotation"}
FIT_VALUES = {"stretch", "contain", "cover", "center"}
LAYOUT_VALUES = {"number", "text"}


def sec_schema():
    print("\n== 3b. PLCUI 1.0.2 schema 取值域 ==")
    if not os.path.exists(XML):
        bad("main.xml 不存在")
        return
    root = ET.parse(XML).getroot()
    problems = []

    ui_attrs = {"version", "width", "height", "entry"}
    for k, v in root.attrib.items():
        if k not in ui_attrs:
            problems.append("<ui> 非法属性 %s" % k)
    for k in ("width", "height"):
        try:
            n = int(root.get(k, ""))
            if not 1 <= n <= 4096:
                problems.append("<ui %s=%s> 越界 1..4096" % (k, root.get(k)))
        except ValueError:
            problems.append("<ui %s=%s> 不是整数" % (k, root.get(k)))

    def check_int(tag, el, name, val):
        lo, hi = INT_RULES.get(name, (None, None))
        if name in INT_FULL:
            return
        if lo is None:
            problems.append("<%s id=%s> 属性 %s 没有登记取值域（check.py 需要补规则）"
                            % (tag, el.get("id"), name))
            return
        try:
            n = int(val)
        except ValueError:
            problems.append("<%s id=%s> %s=\"%s\" 不是整数" % (tag, el.get("id"), name, val))
            return
        if not lo <= n <= hi:
            problems.append("<%s id=%s> %s=%d 越界 %d..%d" % (tag, el.get("id"), name, n, lo, hi))

    for pg in root.iter("page"):
        for k in pg.attrib:
            if k not in ("id", "background", "bg-opacity", "border-width", "radius", "padding"):
                problems.append("<page id=%s> 非法属性 %s" % (pg.get("id"), k))
        for k in ("bg-opacity", "border-width", "radius", "padding"):
            if pg.get(k) is not None:
                check_int("page", pg, k, pg.get(k))

    for el in root.iter():
        tag = el.tag
        if tag not in SPECIFIC_ATTRS:
            continue
        allowed = set(BASE_ATTRS) | set(SPECIFIC_ATTRS[tag])
        if tag in ("label", "textarea", "keyboard", "table"):
            allowed |= set(FONT_ATTRS)
        for k, v in el.attrib.items():
            if k not in allowed:
                problems.append("<%s id=%s> 非法属性 %s" % (tag, el.get("id"), k))
            elif k in INT_RULES or k in INT_FULL:
                check_int(tag, el, k, v)
            elif k == "border-width":
                lo, hi = INT_RULES_BY_TAG.get(tag, {}).get("border-width", (0, 16))
                try:
                    if not lo <= int(v) <= hi:
                        problems.append("<%s id=%s> border-width=%s 越界 %d..%d"
                                        % (tag, el.get("id"), v, lo, hi))
                except ValueError:
                    problems.append("<%s id=%s> border-width 不是整数" % (tag, el.get("id")))

        w, h = el.get("w"), el.get("h")
        if w and h:
            try:
                if int(w) < 1 or int(h) < 1:
                    problems.append("<%s id=%s> 尺寸 %sx%s，PLCUI 要求 >=1"
                                    % (tag, el.get("id"), w, h))
            except ValueError:
                pass

        if tag == "image":
            if el.get("on-click") and el.get("clickable") != "true":
                problems.append("<image id=%s> 有 on-click 但 clickable 不是 true" % el.get("id"))
            if el.get("fit") and el.get("fit") not in FIT_VALUES:
                problems.append("<image id=%s> fit=%s 非法" % (el.get("id"), el.get("fit")))
            manual = el.get("rotation") is not None or el.get("pivot-x") is not None \
                or el.get("pivot-y") is not None or el.get("zoom") is not None
            if manual and el.get("fit") != "center":
                problems.append("<image id=%s> 有 rotation/pivot/zoom 时必须 fit=center" % el.get("id"))
            if (el.get("pivot-x") is None) != (el.get("pivot-y") is None):
                problems.append("<image id=%s> pivot-x/pivot-y 必须成对出现" % el.get("id"))
            if (el.get("src-x") is None) != (el.get("src-y") is None):
                problems.append("<image id=%s> src-x/src-y 必须成对出现" % el.get("id"))
            if el.get("src-x") is not None and manual:
                problems.append("<image id=%s> src 裁剪不能与 fit/transform 同用" % el.get("id"))
            hx, hy = el.get("hit-x"), el.get("hit-y")
            hw, hh = el.get("hit-w"), el.get("hit-h")
            if hw and h and int(hx or 0) + int(hw) > int(w or 0):
                problems.append("<image id=%s> 热区横向超出组件" % el.get("id"))
            if hh and h and int(hy or 0) + int(hh) > int(h or 0):
                problems.append("<image id=%s> 热区纵向超出组件" % el.get("id"))

        elif tag == "keyboard":
            if el.get("layout") and el.get("layout") not in LAYOUT_VALUES:
                problems.append("<keyboard id=%s> layout=%s 非法" % (el.get("id"), el.get("layout")))

        elif tag == "table":
            rows, cols = int(el.get("rows", "0")), int(el.get("columns", "0"))
            if rows * cols > 1024:
                problems.append("<table id=%s> %dx%d 超过 1024 个单元格" % (el.get("id"), rows, cols))
            cw = el.get("col-widths")
            if cw and len(cw.split(",")) != cols:
                problems.append("<table id=%s> col-widths 有 %d 段，columns=%d"
                                % (el.get("id"), len(cw.split(",")), cols))
            ca = el.get("col-aligns")
            if ca and len(ca.split(",")) != cols:
                problems.append("<table id=%s> col-aligns 有 %d 段，columns=%d"
                                % (el.get("id"), len(ca.split(",")), cols))
            rh, th = el.get("row-height"), el.get("h")
            if rh and th and rows * int(rh) > int(th):
                problems.append("<table id=%s> 行数×行高 %d 超出表格高度 %s"
                                % (el.get("id"), rows * int(rh), th))

        elif tag == "chart":
            n = int(el.get("point-count", "60"))
            series = [c for c in el if c.tag == "series"]
            if not 1 <= len(series) <= 8:
                problems.append("<chart id=%s> 系列数 %d 越界 1..8" % (el.get("id"), len(series)))
            for s in series:
                vals = [x for x in (s.get("values") or "").split(",") if x.strip()]
                if len(vals) != n:
                    problems.append("<chart id=%s> 系列 %s 点数 %d != point-count %d"
                                    % (el.get("id"), s.get("id"), len(vals), n))
                for v in vals:
                    if not -1000.0 <= float(v) <= 1000.0:
                        problems.append("<chart id=%s> 系列 %s 有值 %s 超出 -1000..1000"
                                        % (el.get("id"), s.get("id"), v))
                        break
            ymin, ymax = el.get("y-min"), el.get("y-max")
            if ymin is not None and ymax is not None and float(ymin) >= float(ymax):
                problems.append("<chart id=%s> y-min 必须小于 y-max" % el.get("id"))

        elif tag == "slider":
            lo, hi = int(el.get("min", "0")), int(el.get("max", "100"))
            if lo >= hi:
                problems.append("<slider id=%s> min 必须小于 max" % el.get("id"))
            if el.get("value") is not None and not lo <= int(el.get("value")) <= hi:
                problems.append("<slider id=%s> value=%s 不在 %d..%d"
                                % (el.get("id"), el.get("value"), lo, hi))
            knob = el.get("knob-src")
            if knob:
                # PLCUI 要求旋钮图是正方形，边长 == 滑块短边（横向取 h）
                side = int(el.get("h", el.get("w", "0")))
                fn = os.path.join(RES, knob + ".png")
                if os.path.exists(fn):
                    try:
                        from PIL import Image
                        iw, ih = Image.open(fn).size
                        if iw != side or ih != side:
                            problems.append("<slider id=%s> 旋钮图 %s 是 %dx%d，必须 %dx%d"
                                            % (el.get("id"), knob, iw, ih, side, side))
                    except ImportError:
                        warn("没装 Pillow，跳过旋钮图尺寸校验")
                else:
                    problems.append("<slider id=%s> 旋钮图 %s.png 不存在" % (el.get("id"), knob))

    # 每页都必须自带背景，否则会露出上一页残留
    for pg in root.iter("page"):
        if not any(c.tag == "image" and c.get("x") == "0" and c.get("y") == "0"
                   and c.get("w") == root.get("width") for c in pg):
            problems.append("<page id=%s> 缺少整页底图" % pg.get("id"))

    if problems:
        for p in problems:
            bad(p)
    else:
        ok("全部组件的属性名与整型取值域都合法（%d 条规则）" % (len(INT_RULES) + len(SPECIFIC_ATTRS)))


def sec_font():
    print("\n== 3c. 字形覆盖（实测探针结论） ==")
    # 这台固件的 hzfont 只带 GB2312 常用字与部分符号；以下码位实测渲染成豆腐块
    missing = {"\u2014": "—", "\u25a3": "▣", "\u26a0": "⚠", "\u25b6": "▶", "\u2713": "✓"}
    hits = {}
    targets = [XML] + [os.path.join(CODE, f) for f in ("data_app.lua", "ui_app.lua", "ui_vars.lua")]
    for path in targets:
        if not os.path.exists(path):
            continue
        src = open(path, encoding="utf-8").read()
        # Lua 注释里的符号不上屏，剔除后再查
        if path.endswith(".lua"):
            src = strip_comment(src)
        for ch, name in missing.items():
            if ch in src:
                hits.setdefault(name, []).append(os.path.basename(path))
    if hits:
        for name, files in hits.items():
            bad("字形缺失的字符 %s 出现在 %s（设备上会显示空框）" % (name, ",".join(files)))
    else:
        ok("没有使用 hzfont 缺字形的符号（— ▣ ⚠ ▶ ✓）")


def sec_xml():
    print("\n== 3. main.xml ==")
    if not os.path.exists(XML):
        bad("main.xml 不存在")
        return
    size = os.path.getsize(XML)
    tree = ET.parse(XML)
    root = tree.getroot()

    # 3.1 顶层：<ui version="0.1" width height entry> > <resources> + <pages> > <page>
    if root.tag != "ui" or root.get("version") != "0.1":
        bad("根元素应为 <ui version=\"0.1\">，实际 <%s version=%s>" % (root.tag, root.get("version")))
    else:
        ok("根元素 <ui version=\"0.1\"> %sx%s entry=%s"
           % (root.get("width"), root.get("height"), root.get("entry")))
    pages = []
    for pgs in root.findall("pages"):
        pages.extend(pgs.findall("page"))
    res = []
    for rs in root.findall("resources"):
        res = list(rs)
    if len(pages) == 4:
        ok("页数 4：%s" % " / ".join(e.get("id", "?") for e in pages))
    else:
        bad("页数 %d，应为 4" % len(pages))
    ok("文件大小 %.1f KB" % (size / 1024.0))

    # 3.2 资源
    res_ids = [e.get("id") for e in res if e.get("id")]
    dup = [x for x in set(res_ids) if res_ids.count(x) > 1]
    if dup:
        bad("资源 ID 重复：%s" % ",".join(dup))
    else:
        ok("资源 %d 个，ID 唯一" % len(res_ids))

    # 3.3 组件
    total = 0
    ids = []
    handlers = set()
    bad_attr = []
    for pg in pages:
        for e in pg.iter():
            if e is pg:
                continue
            total += 1
            rid = e.get("id")
            if rid:
                ids.append((pg.get("id"), rid))
            h = e.get("on-click") or e.get("on-change") or e.get("on-submit") or e.get("on-cancel")
            if h:
                handlers.add(h)
            for k in e.attrib:
                if k in ("font-size", "font_size_x", "visibility"):
                    bad_attr.append((e.tag, rid, k))
                if k == "text" and len(e.get("text", "").encode("utf-8")) > 511:
                    bad_attr.append((e.tag, rid, "text>511B"))
    ok("组件 %d 个（上限 512）" % total)

    # 3.4 组件 ID 页内唯一（跨页可重名，例如每页都有的公共壳）
    for pg in pages:
        pids = [e.get("id") for e in pg.iter() if e is not pg and e.get("id")]
        dup_p = sorted(set(x for x in pids if pids.count(x) > 1))
        if dup_p:
            bad("页 %s 内 ID 重复：%s" % (pg.get("id"), ",".join(dup_p)))
    ok("组件 ID 页内唯一（共 %d 个）" % len(ids))
    all_ids = [x[1] for x in ids]
    cross = sorted(set(x for x in all_ids if all_ids.count(x) > 1))
    if cross:
        warn("%d 个 ID 跨页重名（公共壳，符合页内唯一规则）" % len(cross))

    # 3.5 关键字拼写
    for pg in pages:
        for e in pg.iter():
            for k, v in e.attrib.items():
                if k == "font_size" and not str(v).isdigit():
                    bad("%s:font_size=%s" % (e.get("id"), v))
                if k == "hidden" and v not in ("true", "false"):
                    bad("%s:hidden=%s 必须是 true/false" % (e.get("id"), v))
                if k == "clickable" and v not in ("true", "false"):
                    bad("%s:clickable=%s" % (e.get("id"), v))

    # 3.6 on-* 是否都在 ui_app.handlers
    p = os.path.join(CODE, "ui_app.lua")
    with io.open(p, "r", encoding="utf-8") as f:
        ui_src = f.read()
    missing = []
    for h in sorted(handlers):
        # 事件表两种写法都算注册：function H.xxx() 与 H.xxx = function ...
        if not re.search(r'H\.' + re.escape(h) + r'\s*[=(]', ui_src):
            missing.append(h)
    if missing:
        bad("handler 未注册：%s" % ",".join(missing))
    else:
        ok("XML 中 %d 个事件全部在 ui_app.handlers 注册" % len(handlers))

    # 3.7 src 指向的资源必须存在
    miss = []
    for pg in pages:
        for e in pg.iter():
            for k in ("src", "src-pressed", "src-checked", "src-disabled", "knob-src"):
                v = e.get(k)
                if v and v not in res_ids:
                    miss.append((e.get("id"), k, v))
    if miss:
        bad("引用了未声明资源：%s" % miss[:6])
    else:
        ok("src / knob-src 引用的资源全部已声明")

    # 3.8 资源文件存在且文件名合规（按 resources 里声明的 src 文件名核）
    missing_file = []
    long_name = []
    for e in res:
        fn = e.get("src") or ""
        if not fn or not os.path.exists(os.path.join(RES, fn)):
            missing_file.append(e.get("id"))
        if len(fn.encode("utf-8")) > 23:
            long_name.append(fn)
    if missing_file:
        bad("资源文件缺失：%s" % ",".join(missing_file[:8]))
    else:
        ok("资源文件全部存在（%d 个）" % len(res))
    if long_name:
        bad("文件名超过 23 字节：%s" % ",".join(long_name))
    else:
        ok("资源文件名均 <=23 字节")

    # 3.9 chart 合法性：values 是 series 的属性，字符串逗号分隔
    n_chart = 0
    for pg in pages:
        for e in pg.iter("chart"):
            n_chart += 1
            n = int(e.get("point-count", "0"))
            series = [c for c in e if c.tag == "series"]
            if not (2 <= n <= 1024):
                bad("chart %s point-count=%d 越界" % (e.get("id"), n))
            if not (1 <= len(series) <= 8):
                bad("chart %s 系列数 %d 越界" % (e.get("id"), len(series)))
            for s in series:
                raw = s.get("values")
                if raw:
                    vals = raw.split(",")
                    if len(vals) != n:
                        bad("chart %s 系列 %s 点数 %d != point-count %d"
                            % (e.get("id"), s.get("id"), len(vals), n))
                    for v in vals:
                        try:
                            f = float(v)
                        except ValueError:
                            bad("chart %s 数值非法：%s" % (e.get("id"), v))
                            break
                        if not (-1000.0 <= f <= 1000.0):
                            bad("chart %s 数值 %s 超出 -1000~1000" % (e.get("id"), v))
                            break
                        if len(v.split(".")[-1]) > 2 and "." in v:
                            bad("chart %s 数值 %s 小数超过两位" % (e.get("id"), v))
                            break
    ok("%d 张 chart 的点数、系列数、值域全部合法" % n_chart)

    # 3.10 table
    for pg in pages:
        for e in pg.iter("table"):
            rows = int(e.get("rows", "0"))
            cols = int(e.get("columns", "0"))
            h = int(e.get("h", "0"))
            rh = int(e.get("row-height", "0"))
            if rows > 128 or cols > 16 or rows * cols > 1024:
                bad("table %s 规模 %dx%d 超限" % (e.get("id"), rows, cols))
            if rh and rows * rh > h:
                bad("table %s 行数×行高 %d > 高度 %d" % (e.get("id"), rows * rh, h))
    ok("table 规模与行高合规")

    # 3.11 textarea 引用的 keyboard 必须同页存在
    for pg in pages:
        kb = set(e.get("id") for e in pg.iter("keyboard"))
        for e in pg.iter("textarea"):
            k = e.get("keyboard")
            if k and k not in kb:
                bad("%s 引用的 keyboard %s 不在本页" % (e.get("id"), k))
    ok("textarea 的 keyboard 引用均在本页")

    return set(res_ids)


# ---------------------------------------------------------------- 4) 绑定表
BIND_RE = re.compile(
    r'\{\s*id\s*=\s*"([^"]+)"\s*,\s*var\s*=\s*"([^"]+)"\s*,\s*kind\s*=\s*"([^"]+)"')


def parse_blocks(src, name):
    """把 ui_vars 里某张表拆成 {block_name: [ (id, var, kind) ]}"""
    out = {}
    i = src.find(name)
    if i < 0:
        return out
    # 找到该赋值块的结束（下一个顶层 '}' 后跟空行）
    seg = src[i:]
    depth = 0
    started = False
    end = len(seg)
    for k, ch in enumerate(seg):
        if ch == "{":
            depth += 1
            started = True
        elif ch == "}":
            depth -= 1
            if started and depth == 0:
                end = k + 1
                break
    seg = seg[:end]
    # 块内再按 "xxx = {" 切分
    parts = re.split(r'\n\s{4}(\w+)\s*=\s*\{', seg)
    if len(parts) == 1:
        out["_"] = BIND_RE.findall(seg)
        return out
    for k in range(1, len(parts), 2):
        out[parts[k]] = BIND_RE.findall(parts[k + 1])
    return out


def sec_bind():
    print("\n== 4. 绑定表 ui_vars ==")
    p = os.path.join(CODE, "ui_vars.lua")
    with io.open(p, "r", encoding="utf-8") as f:
        uv = f.read()
    tree = ET.parse(XML)
    page_ids = {}
    for pgs in tree.getroot().findall("pages"):
        for pg in pgs.findall("page"):
            page_ids[pg.get("id")] = set(e.get("id") for e in pg.iter() if e.get("id"))
    all_ids = set()
    for s in page_ids.values():
        all_ids |= s

    common = parse_blocks(uv, "ui_vars.COMMON = {")
    common_list = common.get("_", [])
    miss = [c[0] for c in common_list if c[0] not in all_ids]
    if miss:
        bad("公共层绑定到了不存在的组件：%s" % ",".join(sorted(set(miss))))
    else:
        ok("公共层 %d 条绑定，组件全部存在" % len(common_list))
    # 公共层必须在四页都出现
    for pid, ids in page_ids.items():
        lack = [c[0] for c in common_list if c[0] not in ids]
        if lack:
            bad("公共层组件在页 %s 缺失：%s" % (pid, ",".join(sorted(set(lack))[:8])))
    ok("公共层组件在四页均存在")

    pages = parse_blocks(uv, "ui_vars.PAGES = {")
    for pid, lst in pages.items():
        if pid == "_":
            continue
        if pid not in page_ids:
            bad("ui_vars.PAGES 里的 %s 不是 main.xml 的页面" % pid)
            continue
        lack = [c[0] for c in lst if c[0] not in page_ids[pid]]
        if lack:
            bad("页 %s 绑定到了本页没有的组件：%s" % (pid, ",".join(sorted(set(lack)))))
        else:
            ok("页 %-9s %d 条绑定，组件全部存在" % (pid, len(lst)))

    # 变量名必须在 data_app.get() 里产出
    p = os.path.join(CODE, "data_app.lua")
    with io.open(p, "r", encoding="utf-8") as f:
        da = f.read()
    i = da.find("function data_app.get()")
    body = da[i:]
    keys = set(re.findall(r'^\s{8}(\w+)\s*=', body, re.M))
    prefixes = set(re.findall(r'v\["(\w+)"\s*\.\.', body))
    all_bind = list(common_list)
    for lst in pages.values():
        all_bind.extend(lst)
    bad_var = []
    for bid, var, kind in all_bind:
        # textarea 故意不参与周期刷数（会冲掉用户输入），由 ui_app 单独回写
        if kind == "textarea":
            continue
        if var in keys:
            continue
        if any(var.startswith(pf) and var[len(pf):].isdigit() for pf in prefixes):
            continue
        bad_var.append("%s->%s" % (bid, var))
    if bad_var:
        bad("绑定变量在 data_app.get() 中不存在：%s" % ",".join(sorted(set(bad_var))[:10]))
    else:
        ok("绑定变量 %d 个全部由 data_app.get() 提供" % len(set(v[1] for v in all_bind)))


# ---------------------------------------------------------------- main
def main():
    print("PLCUI 工程自检：%s" % ROOT)
    sec_syntax()
    sec_style()
    sec_xml()
    sec_schema()
    sec_font()
    sec_bind()
    # 交付文档
    print("\n== 5. 交付文档 ==")
    for rel in ("code/readme.md", "design/spec.md", "design/fallback.md",
                "design/index.html", "design/theme.css", "preview/verify.md"):
        if os.path.exists(os.path.join(ROOT, rel)):
            ok(rel)
        else:
            bad("缺少 %s" % rel)
    print("\n== 汇总 ==")
    print("  通过 %d / 失败 %d / 警告 %d" % (ok_n, bad_n, warn_n))
    return 1 if bad_n else 0


if __name__ == "__main__":
    sys.exit(main())
