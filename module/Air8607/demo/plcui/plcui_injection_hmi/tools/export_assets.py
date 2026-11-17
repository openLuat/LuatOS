# -*- coding: utf-8 -*-
"""环节② + 环节③：把 design/ 原型导出成 PLCUI 的素材与 main.xml。

做三件事
--------
1. 用 tools/tiles.py 的瓦片表生成 design/sheet.html（各种状态的素材瓦片，
   透明底，与原型共用 theme.css），无头 Chromium 整页截图后逐块裁剪成 PNG；
2. 逐页整页截图（隐藏所有 data-plcui 元素）作为页面底图，转 Baseline JPEG；
3. 逐页读 getBoundingClientRect 的实测包围盒（?json=1 钩子），生成 main.xml。

坐标只认 CSS 显示值（G2），不读 SVG viewBox，也不手写。

用法
----
    python tools/export_assets.py            # 全流程
    python tools/export_assets.py --sheet    # 只重出素材瓦片
    python tools/export_assets.py --pages    # 只重出底图与 main.xml
"""

import base64
import json
import math
import os
import re
import subprocess
import sys
import urllib.parse

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DESIGN = os.path.join(ROOT, "design")
OUT = os.path.join(ROOT, "code", "res")
TMP = os.path.join(ROOT, "build")
CHROME = os.path.join(os.path.expanduser("~"), "AppData", "Local", "ms-playwright",
                      "chromium-1234", "chrome-win64", "chrome.exe")

sys.path.insert(0, HERE)
from tiles import TILES  # noqa: E402

WIDTH, HEIGHT = 1024, 600

# 页 -> (短码, 底图资源名, 底图背景色)
PAGES = [
    ("overview", "ov", "#1c2024"),
    ("trend", "tr", "#1c2024"),
    ("alarm", "al", "#1c2024"),
    ("settings", "st", "#1c2024"),
]
SHORT = {p[0]: p[1] for p in PAGES}


# ---------------------------------------------------------------- chrome 驱动
def url(path, **kw):
    u = "file:///" + urllib.parse.quote(path.replace("\\", "/"))
    if kw:
        u += "?" + urllib.parse.urlencode(kw)
    return u


def shot(page_url, out_png, w, h, alpha=False):
    args = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--force-device-scale-factor=1", "--window-size=%d,%d" % (w, h),
            "--virtual-time-budget=3000", "--screenshot=" + out_png]
    if alpha:
        args.append("--default-background-color=00000000")
    args.append(page_url)
    r = subprocess.run(args, capture_output=True)
    if not os.path.exists(out_png):
        raise SystemExit("截图失败: %s\n%s" % (page_url, r.stderr.decode("utf-8", "ignore")[-800:]))


def dump_json(page_url):
    args = [CHROME, "--headless=new", "--disable-gpu", "--virtual-time-budget=3000",
            "--dump-dom", page_url]
    r = subprocess.run(args, capture_output=True)
    dom = r.stdout.decode("utf-8", "ignore")
    m = re.search(r'<pre id="jsonout">([^<]*)</pre>', dom)
    if not m:
        raise SystemExit("没有拿到 jsonout，页面脚本可能报错：\n" + dom[-1500:])
    return json.loads(base64.b64decode(m.group(1)).decode("utf-8"))


# ---------------------------------------------------------------- 素材瓦片
def build_sheet_html():
    """按瓦片表排版成绝对定位的格子，尺寸与裁剪时完全一致。"""
    cols_w = 1120
    x, y, row_h = 20, 20, 0
    placement = []
    for name, w, h, pad, inner in TILES:
        tw, th = w + 2 * pad, h + 2 * pad
        if x + tw + 20 > cols_w:
            x = 20
            y += row_h + 16
            row_h = 0
        placement.append((name, tw, th, x, y))
        x += tw + 20
        row_h = max(row_h, th)
    page_h = y + row_h + 20

    tiles = []
    for (name, w, h, pad, inner), (n2, tw, th, tx, ty) in zip(TILES, placement):
        tiles.append('<div class="tile" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx">%s</div>'
                     % (tx, ty, tw, th, inner))

    html = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8"><title>PLCUI 素材瓦片</title>
<link rel="stylesheet" href="theme.css">
<style>
  html,body{background:transparent!important;width:%(w)dpx;height:%(h)dpx;overflow:hidden;}
  .tile{position:absolute;}
  /* 瓦片内部件一律铺满自身格位，阴影/辉光靠 pad 留白保住 */
</style></head><body>
%(tiles)s
</body></html>
""" % {"w": cols_w, "h": page_h, "tiles": "\n".join(tiles)}

    path = os.path.join(DESIGN, "sheet.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    return path, cols_w, page_h, placement


def export_sheet():
    path, w, h, placement = build_sheet_html()
    os.makedirs(TMP, exist_ok=True)
    png = os.path.join(TMP, "sheet.png")
    shot(url(path), png, w, h, alpha=True)

    im = Image.open(png).convert("RGBA")
    # 透明底截图偶尔带全透明像素的 RGB 垃圾值，统一清理边缘噪点
    for name, tw, th, x, y in placement:
        tile = im.crop((x, y, x + tw, y + th))
        out = os.path.join(OUT, name + ".png")
        tile.save(out, "PNG", optimize=True)
    print("素材瓦片 %d 张 -> code/res/" % len(placement))
    return placement


# ---------------------------------------------------------------- 底图
def export_pages():
    os.makedirs(OUT, exist_ok=True)
    for pid, short, bg in PAGES:
        png = os.path.join(TMP, "bg_%s.png" % pid)
        shot(url(os.path.join(DESIGN, "index.html"), page=pid, **{"export": "1", "state": "hide"}),
             png, WIDTH, HEIGHT)
        im = Image.open(png).convert("RGB")
        if im.size != (WIDTH, HEIGHT):
            raise SystemExit("底图尺寸不对 %s: %s" % (pid, im.size))
        im.save(os.path.join(OUT, "bg_%s.jpg" % short), "JPEG",
                quality=88, optimize=True, progressive=False)
        print("底图 bg_%s.jpg" % short)


# ---------------------------------------------------------------- XML
def states_of(d):
    s = d.get("states", "")
    return [x for x in s.split(",") if x]


def res_ids(asset, states):
    if not states:
        return [asset]
    return ["%s_%s" % (asset, s) for s in states]


def seed_series(n, i):
    out = []
    for k in range(n):
        v = 52 + 9 * math.sin(k / (6.0 + i) + i * 1.1) + 3 * math.cos(k / 3.7 + i)
        out.append(round(max(-100, min(100, v)), 2))
    return out


def xml_attr(name, value):
    v = str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
    return ' %s="%s"' % (name, v)


def build_xml():
    resources = []          # 有序去重
    pages_xml = []

    def reg(rid):
        if rid not in resources:
            resources.append(rid)

    for pid, short, bg in PAGES:
        items = dump_json(url(os.path.join(DESIGN, "index.html"),
                              page=pid, **{"export": "1", "json": "1"}))
        body = []
        body.append('      <image id="bg" x="0" y="0" w="%d" h="%d" src="bg_%s"/>' % (WIDTH, HEIGHT, short))
        reg("bg_%s" % short)

        for d in items:
            tag = d.get("tag")
            did = d.get("id") or "x"
            x, y, w, h = d["x"], d["y"], d["w"], d["h"]
            # PLCUI 的 w/h 是 1..4096 的必填整数，0 会让整份 XML 报
            # E_SCHEMA "Integer attribute is invalid or out of range" 而整页加载失败
            if w < 1 or h < 1:
                raise SystemExit("组件 %s (%s) 的宽高为 %dx%d，PLCUI 要求 >=1："
                                 "检查原型里该节点是否 display:none 或未设尺寸" % (did, tag, w, h))

            if tag == "image":
                asset = d.get("asset-name")
                if not asset:
                    raise SystemExit("图片缺 data-asset-name: " + did)
                states = states_of(d)
                if states == ["n"]:
                    states = []
                frames = d.get("frames")
                if frames:                       # 逐帧动画：flow_0..flow_n，Lua 定时 set_src
                    ids = ["%s_%d" % (asset, i) for i in range(int(frames))]
                    states = []
                else:
                    ids = res_ids(asset, states)
                for r in ids:
                    reg(r)
                    if not os.path.exists(os.path.join(OUT, r + ".png")):
                        raise SystemExit("素材缺失: %s（先跑 --sheet）" % r)

                pad = 0
                for t in TILES:
                    if t[0] == ids[0]:
                        pad = t[3]
                        break
                x, y, w, h = x - pad, y - pad, w + 2 * pad, h + 2 * pad

                src = ids[0]
                extra = ""
                if states == ["n", "p"]:
                    extra += ' src-pressed="%s"' % ids[1]
                elif states == ["n", "c"]:
                    extra += ' src-checked="%s"' % ids[1]
                elif states == ["n", "p", "d"]:
                    extra += ' src-pressed="%s" src-disabled="%s"' % (ids[1], ids[2])
                elif states == ["on", "off"]:
                    src = "%s_off" % asset
                    extra += ' src-checked="%s_on"' % asset
                if d.get("fit"):
                    extra += xml_attr("fit", d["fit"])
                if d.get("pivot"):
                    px, py = d["pivot"].split(",")
                    px, py = int(px) + pad, int(py) + pad
                    extra += ' fit="center"%s%s rotation="0" antialias="true"' % (
                        xml_attr("pivot-x", px), xml_attr("pivot-y", py))
                if d.get("on"):
                    extra += ' clickable="true"%s' % xml_attr("on-click", d["on"])
                if d.get("hidden"):
                    extra += ' hidden="true"'
                body.append('      <image id="%s" x="%d" y="%d" w="%d" h="%d" src="%s"%s/>'
                            % (did, x, y, w, h, src, extra))

            elif tag == "label":
                text = d.get("text", "")
                if not text:
                    continue
                body.append('      <label id="%s" x="%d" y="%d" w="%d" h="%d" font="hzfont" font_size="%s"%s%s%s text="%s"/>'
                            % (did, x, y, w, h, d.get("fs", 12),
                               xml_attr("color", d.get("color", "#e9edee")),
                               xml_attr("align", d.get("align", "left")),
                               "", text.replace('"', "&quot;")))

            elif tag == "textarea":
                body.append('      <textarea id="%s" x="%d" y="%d" w="%d" h="%d" font="hzfont" font_size="%s"%s%s'
                            ' one-line="true" max-length="%s" accepted-chars="%s" keyboard="%s"'
                            ' on-submit="%s" on-cancel="%s" text="%s"/>'
                            % (did, x, y, w, h, d.get("fs", 12),
                               xml_attr("color", d.get("color", "#48d8d0")),
                               xml_attr("align", d.get("align", "left")),
                               d.get("max", 6), d.get("chars", "0123456789."),
                               d.get("keyboard", "kb_num"),
                               d.get("on-submit", "param_submit"),
                               d.get("on-cancel", "param_cancel"),
                               d.get("text", "")))

            elif tag == "chart":
                n = int(d.get("points", 60))
                sers = []
                for i, spec in enumerate(d.get("series", "t:#ffb43a").split(",")):
                    sid, color = spec.split(":")
                    vals = seed_series(n, i)
                    sers.append('        <series id="%s" color="%s" values="%s"/>'
                                % (sid, color, ",".join("%g" % v for v in vals)))
                body.append('      <chart id="%s" x="%d" y="%d" w="%d" h="%d" type="%s" point-count="%d"'
                            ' y-min="%s" y-max="%s" hdiv="%s" vdiv="%s" bg-opacity="0" line-width="2"'
                            ' grid-color="#1a2429">'
                            % (did, x, y, w, h, d.get("type", "line"), n,
                               d.get("ymin", 0), d.get("ymax", 100), d.get("hdiv", 0), d.get("vdiv", 0)))
                body.extend(sers)
                body.append('      </chart>')

            elif tag == "table":
                body.append('      <table id="%s" x="%d" y="%d" w="%d" h="%d" rows="%s" columns="%s"'
                            ' font="hzfont" font_size="11" color="#d6dcde" background="#0a1013"'
                            ' border-color="#1d272c" header-color="#1b2327" alternate-color="#121b1f"'
                            ' border-width="1" cell-padding="6" row-height="%s" header="true"'
                            ' grid="false" header-align="left" col-widths="%s" col-aligns="left,left,left,left,center,center"/>'
                            % (did, x, y, w, h, d.get("rows", 7), d.get("cols", 6),
                               d.get("row-height", 42), d.get("col-widths", "")))

            elif tag == "slider":
                reg("thumb")
                body.append('      <slider id="%s" x="%d" y="%d" w="%d" h="%d" min="%s" max="%s" value="%s"'
                            ' step="1" knob-src="thumb" track-color="#0d1113"%s/>'
                            % (did, x, y, w, h, d.get("min", 0), d.get("max", 100),
                               d.get("value", 0),
                               xml_attr("on-change", d.get("on-change", "")) if d.get("on-change") else ""))

            elif tag == "keyboard":
                body.append('      <keyboard id="%s" x="%d" y="%d" w="%d" h="%d" layout="%s"'
                            ' font="hzfont" font_size="18" hidden="true"/>'
                            % (did, x, y, w, h, d.get("layout", "number")))

            else:
                raise SystemExit("未知组件类型: %s (%s)" % (tag, did))

        pages_xml.append('    <page id="%s" background="%s">\n%s\n    </page>'
                         % (pid, bg, "\n".join(body)))

    head = ['<?xml version="1.0" encoding="UTF-8"?>',
            '<ui version="0.1" width="%d" height="%d" entry="%s">' % (WIDTH, HEIGHT, PAGES[0][0]),
            '  <resources>']
    for rid in resources:
        head.append('    <image id="%s" src="%s.png"/>' % (rid, rid)
                    if not rid.startswith("bg_") else
                    '    <image id="%s" src="%s.jpg"/>' % (rid, rid))
    head.append('  </resources>')
    head.append('  <pages>')
    tail = ['  </pages>', '</ui>', '']

    xml = "\n".join(head + pages_xml + tail)
    path = os.path.join(OUT, "main.xml")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(xml)
    print("main.xml: %d 资源 / %d 页 / %.1f KB" % (len(resources), len(PAGES),
                                                  os.path.getsize(path) / 1024.0))
    return path


if __name__ == "__main__":
    os.makedirs(TMP, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    if only in ("", "--sheet"):
        export_sheet()
    if only in ("", "--pages"):
        export_pages()
        build_xml()
