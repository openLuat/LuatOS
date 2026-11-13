"""main.xml 结构自检：按 plcui（components/plcui/src/core/luat_plcui_xml.c）的
解析规则检查标签、属性、取值范围、引用和事件处理函数。

plcui 只要遇到一个未知属性就会整份 XML 加载失败，所以改完界面先跑一遍这个脚本。

    python tools/check_xml.py
"""

import os
import re
import sys
import xml.etree.ElementTree as ET

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CODE = os.path.join(ROOT, "code")
RES = os.path.join(CODE, "res")
XML = os.path.join(RES, "main.xml")
LUA = os.path.join(CODE, "main.lua")

MAX_WIDGETS = 512
MAX_RESOURCES = 256
MAX_TABLE_ROWS = 128
MAX_TABLE_COLS = 16
MAX_TABLE_CELLS = 1024
MAX_CHART_POINTS = 1024
MAX_CHART_SERIES = 8
TEXT_MAX = 512
MAX_XML_BYTES = 256 * 1024
NAME_MAX = 23   # 图片文件名 / 资源 id / 组件 id 的字节上限（luadb + VFS 限制）

COMMON = {"id", "x", "y", "w", "h", "hidden", "disabled"}
IMAGE = COMMON | {"src", "src-pressed", "src-checked", "src-disabled", "clickable",
                  "on-click", "hit-x", "hit-y", "hit-w", "hit-h"}
LABEL = COMMON | {"text", "font", "font_size", "color", "align"}
TEXTAREA = LABEL | {"max-length", "accepted-chars", "keyboard", "one-line",
                    "on-change", "on-submit", "on-cancel"}
KEYBOARD = COMMON | {"layout", "font", "font_size"}
CONTAINER = COMMON | {"background", "bg-opacity", "border-color", "border-width",
                      "radius", "padding"}
TABLE = COMMON | {"rows", "columns", "col-widths", "col-aligns", "align", "header-align",
                  "grid", "row-height", "header", "cell-padding", "header-color",
                  "alternate-color", "font", "font_size", "color", "background",
                  "border-color", "border-width"}
CHART = COMMON | {"type", "point-count", "y-min", "y-max", "hdiv", "vdiv", "line-width",
                  "grid-color", "background", "bg-opacity", "border-color", "border-width"}

ALLOWED = {"image": IMAGE, "label": LABEL, "textarea": TEXTAREA, "keyboard": KEYBOARD,
           "container": CONTAINER, "table": TABLE, "chart": CHART}

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
    return re.fullmatch(r"#[0-9a-fA-F]{6}", value) is not None


def check_common(tag, w, where):
    for key in ("x", "y", "w", "h"):
        if key in w.attrib and not is_int(w.attrib[key]):
            err(f"{where}: {key} 不是整数")
    for key in ("hidden", "disabled", "clickable", "one-line", "grid", "header"):
        if key in w.attrib and not is_bool(w.attrib[key]):
            err(f"{where}: {key} 必须是 true/false")
    for key in ("color", "background", "border-color", "grid-color", "header-color",
                "alternate-color"):
        if key in w.attrib and not is_color(w.attrib[key]):
            err(f"{where}: {key} 必须是 #rrggbb")
    if "align" in w.attrib and w.attrib["align"] not in ("left", "center", "right"):
        err(f"{where}: align 非法")
    if "text" in w.attrib and len(w.attrib["text"].encode()) >= TEXT_MAX:
        err(f"{where}: text 超过 511 字节")


def main():
    data = open(XML, "rb").read()
    if len(data) > MAX_XML_BYTES:
        err(f"XML 体积 {len(data)} 超过 {MAX_XML_BYTES}")

    root = ET.fromstring(data)
    if root.tag != "ui":
        err("根节点必须是 ui")
    if root.get("version") != "0.1":
        err("ui.version 必须是 0.1")
    width, height = int(root.get("width")), int(root.get("height"))
    entry = root.get("entry")

    resources = {}
    res_node = root.find("resources")
    if res_node is None:
        err("缺少 resources")
        res_node = ET.Element("resources")
    for r in res_node:
        if r.tag not in ("image", "font"):
            err(f"resources 只允许 image/font: {r.tag}")
        rid = r.get("id")
        if r.tag == "image":
            src = r.get("src")
            if not src:
                err(f"资源 {rid} 缺少 src")
                continue
            path = os.path.join(RES, src)
            if not os.path.exists(path):
                err(f"资源 {rid} 文件不存在: {src}")
            if len(rid.encode("utf-8")) > NAME_MAX:
                err(f"资源 id 超过 {NAME_MAX} 字节: {rid}")
            if len(os.path.basename(src).encode("utf-8")) > NAME_MAX:
                err(f"素材文件名超过 {NAME_MAX} 字节: {src}")
            resources[rid] = src
    for name in os.listdir(RES):
        if len(name.encode("utf-8")) > NAME_MAX:
            err(f"code 目录下文件名超过 {NAME_MAX} 字节: {name}")
    if len(resources) > MAX_RESOURCES:
        err(f"资源数 {len(resources)} 超过 {MAX_RESOURCES}")

    # main.lua 里提供的事件函数
    lua = open(LUA, encoding="utf-8").read()
    defined = set(re.findall(r'H\.([A-Za-z0-9_]+)\s*=', lua))
    defined |= set(re.findall(r'H\["([A-Za-z0-9_]+)"\]\s*=', lua))
    dynamic = {"tree_", "cat_", "rp_", "flt_"}
    used_handlers = set()

    pages = root.find("pages")
    if pages is None:
        err("缺少 pages")
        pages = ET.Element("pages")

    total = 0
    page_ids = set()
    for page in pages:
        if page.tag != "page":
            err(f"pages 下只允许 page: {page.tag}")
            continue
        pid = page.get("id")
        if pid in page_ids:
            err(f"页面 ID 重复: {pid}")
        page_ids.add(pid)
        if "background" in page.attrib and not is_color(page.get("background")):
            err(f"page {pid}: background 必须是 #rrggbb")

        ids = set()
        keyboards = {w.get("id") for w in page if w.tag == "keyboard"}
        widgets = list(page)
        total += len(widgets)
        image_refs = {}

        for w in widgets:
            tag = w.tag
            where = f"page {pid} / {tag} {w.get('id')}"
            if tag not in ALLOWED:
                err(f"{where}: 不支持的标签")
                continue
            for key in w.attrib:
                if key not in ALLOWED[tag]:
                    err(f"{where}: 不支持的属性 {key}")
            wid = w.get("id")
            if not wid:
                err(f"{where}: 缺少 id")
            elif wid in ids:
                err(f"{where}: id 重复")
            elif len(wid.encode("utf-8")) > NAME_MAX:
                err(f"{where}: 组件 id 超过 {NAME_MAX} 字节")
            ids.add(wid)
            if "w" not in w.attrib or "h" not in w.attrib:
                err(f"{where}: 缺少 w/h")
            check_common(tag, w, where)

            if tag == "image":
                for key in ("src", "src-pressed", "src-checked", "src-disabled"):
                    ref = w.get(key)
                    if ref and ref not in resources:
                        err(f"{where}: {key} 引用了不存在的资源 {ref}")
                if w.get("on-click") and w.get("clickable") != "true":
                    err(f"{where}: on-click 需要 clickable=true")
                image_refs[(int(w.get("w")), int(w.get("h")))] = wid

            if tag in ("label", "textarea", "table", "keyboard"):
                if "font" in w.attrib and w.get("font") != "hzfont":
                    warn(f"{where}: font={w.get('font')}，固件通常只有 hzfont")
                if "font_size" in w.attrib:
                    size = int(w.get("font_size"))
                    if not 1 <= size <= 255:
                        err(f"{where}: font_size 超范围")

            if tag == "textarea":
                kb = w.get("keyboard")
                if kb and kb not in keyboards:
                    err(f"{where}: keyboard {kb} 不在同一页面")

            if tag == "table":
                rows = int(w.get("rows"))
                cols = int(w.get("columns"))
                if not 1 <= rows <= MAX_TABLE_ROWS or not 1 <= cols <= MAX_TABLE_COLS:
                    err(f"{where}: 行列超范围")
                if rows * cols > MAX_TABLE_CELLS:
                    err(f"{where}: 单元格 {rows * cols} 超过 {MAX_TABLE_CELLS}")
                seen = set()
                for cell in w:
                    if cell.tag != "cell":
                        err(f"{where}: table 子节点只能是 cell")
                        continue
                    r_, c_ = int(cell.get("row")), int(cell.get("column"))
                    if not (1 <= r_ <= rows and 1 <= c_ <= cols):
                        err(f"{where}: cell {r_},{c_} 越界")
                    if (r_, c_) in seen:
                        err(f"{where}: cell {r_},{c_} 重复")
                    seen.add((r_, c_))
                    if len((cell.get("text") or "").encode()) >= TEXT_MAX:
                        err(f"{where}: cell 文本过长")
                widths = w.get("col-widths")
                if widths and len(widths.split(",")) != cols:
                    err(f"{where}: col-widths 数量与 columns 不一致")

            if tag == "chart":
                points = int(w.get("point-count") or 60)
                if not 2 <= points <= MAX_CHART_POINTS:
                    err(f"{where}: point-count 超范围")
                ymin, ymax = float(w.get("y-min")), float(w.get("y-max"))
                if not (-1000 <= ymin < ymax <= 1000):
                    err(f"{where}: y-min/y-max 必须满足 -1000<=min<max<=1000")
                series = [s for s in w if s.tag == "series"]
                if not series:
                    err(f"{where}: 至少一个 series")
                if len(series) > MAX_CHART_SERIES:
                    err(f"{where}: series 超过 {MAX_CHART_SERIES}")
                sids = set()
                for s in series:
                    if s.get("id") in sids:
                        err(f"{where}: series id 重复")
                    sids.add(s.get("id"))
                    values = s.get("values")
                    if values:
                        parts = values.split(",")
                        if len(parts) != points:
                            err(f"{where}: series {s.get('id')} 点数 {len(parts)} != {points}")
                        for v in parts:
                            try:
                                fv = float(v)
                            except ValueError:
                                err(f"{where}: series 值非法 {v}")
                                break
                            if not -1000 <= fv <= 1000:
                                err(f"{where}: series 值 {v} 超出 -1000~1000")
                    if "color" in s.attrib and not is_color(s.get("color")):
                        err(f"{where}: series color 必须是 #rrggbb")

            for key in ("on-click", "on-change", "on-submit", "on-cancel"):
                name = w.get(key)
                if not name:
                    continue
                used_handlers.add(name)
                if name in defined:
                    continue
                if any(name.startswith(p) and name[len(p):].isdigit() for p in dynamic):
                    continue
                err(f"{where}: main.lua 未定义事件函数 {name}")

        # 图片尺寸与组件尺寸对照（仅提示，plcui 会拉伸）
        for w in widgets:
            if w.tag != "image" or w.get("src") not in resources:
                continue
            src = resources[w.get("src")]
            path = os.path.join(RES, src)
            if not os.path.exists(path):
                continue
            iw, ih = Image.open(path).size
            if (iw, ih) != (int(w.get("w")), int(w.get("h"))):
                warn(f"page {pid} / {w.get('id')}: 图片 {iw}x{ih} 与组件 "
                     f"{w.get('w')}x{w.get('h')} 不一致（会被拉伸）")

    if total > MAX_WIDGETS:
        err(f"组件总数 {total} 超过 {MAX_WIDGETS}")
    if entry not in page_ids:
        err(f"entry {entry} 不是有效页面 id")

    # main.lua 里按字面量引用的组件 ID 必须真实存在（动态拼接的 ID 跳过）
    all_ids = set()
    for page in pages:
        for w in page:
            if w.get("id"):
                all_ids.add(w.get("id"))
    for name in set(re.findall(r'(?:set_text|set_checked|find)\(\s*"([A-Za-z0-9_]+)"\s*[,)]', lua)):
        if name not in all_ids:
            err(f"main.lua 引用了不存在的组件 ID: {name}")
    for page in pages:
        for w in page:
            if w.tag != "chart" or w.get("type") == "bar":
                continue
            for s in w:
                if s.tag == "series" and s.get("id") not in lua:
                    warn(f"chart {w.get('id')} 的 series {s.get('id')} 未被 main.lua 使用")

    print(f"页面 {len(page_ids)} 个，组件 {total} 个，资源 {len(resources)} 个，"
          f"事件 {len(used_handlers)} 个，XML {len(data)} 字节")
    for w in warnings:
        print("警告:", w)
    for e in errors:
        print("错误:", e)
    if errors:
        print(f"检查失败：{len(errors)} 个错误")
        return 1
    print("检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
