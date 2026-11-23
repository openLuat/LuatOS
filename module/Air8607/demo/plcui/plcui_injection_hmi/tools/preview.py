# -*- coding: utf-8 -*-
"""环节⑤ 的 PC 侧等效渲染：只读 main.xml + code/res/，把四个页面画成 PNG。

用途：不启动模拟器也能核对「真机会长成什么样」——底图、贴图位置、字号、
图表点线、表格行高、滑块位置。字体用本机 MiSans（近似 hzfont 的中文字形，
不代表设备最终字形，只用于判断版面是否会溢出）。

用法
----
    python tools/preview.py            # 全部页面 -> preview/
    python tools/preview.py settings   # 单页
"""

import os
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RES = os.path.join(ROOT, "code", "res")
OUT = os.path.join(ROOT, "preview")
FONT_CANDIDATES = [
    "C:/Users/luat/Desktop/MiSans_gb2312.ttf",
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/simhei.ttf",
]

# 表格初值（与 data_app.lua 的报警表一致，仅用于预览）
TABLE_SEED = [
    ["级别", "发生时间", "设备 / 回路", "报警描述", "状态", "处理"],
    ["严重", "14:12:30", "注塑机 C / 液压回路", "液压系统压力低于安全阈值 62 MPa", "未确认", "—"],
    ["警告", "13:58:02", "模温单元 2#", "模温偏差 +4.5 ℃，接近上限", "未确认", "—"],
    ["警告", "13:40:11", "注塑机 B / 润滑", "润滑油脂位偏低，建议补充", "已确认", "—"],
    ["提示", "12:05:44", "安全回路", "安全门联锁信号抖动，已记录", "已确认", "—"],
    ["提示", "11:22:18", "注塑机 A", "合模压力波动超出 ±3%，已自恢复", "已确认", "—"],
    ["提示", "10:48:03", "全线", "班次交接完成，参数已归档", "已确认", "—"],
]

_font_cache = {}


def font(size):
    if size in _font_cache:
        return _font_cache[size]
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            f = ImageFont.truetype(p, size)
            _font_cache[size] = f
            return f
    f = ImageFont.load_default()
    _font_cache[size] = f
    return f


def hex_rgb(s, alpha=255):
    s = (s or "#ffffff").strip()
    if s.startswith("#") and len(s) == 7:
        return (int(s[1:3], 16), int(s[3:5], 16), int(s[5:7], 16), alpha)
    return (255, 255, 255, alpha)


def draw_text(dr, box, text, fs, color, align):
    if not text:
        return
    x, y, w, h = box
    f = font(fs)
    tw = dr.textlength(text, font=f)
    if align == "center":
        tx = x + (w - tw) / 2
    elif align == "right":
        tx = x + w - tw
    else:
        tx = x
    dr.text((tx, y + (h - fs) / 2 - fs * 0.12), text, font=f, fill=color)


def render_page(page, tag):
    w = int(page.get("width", 1024))
    h = int(page.get("height", 600))
    canvas = Image.new("RGBA", (w, h), hex_rgb(page.get("background", "#101418")))

    for el in page:
        t = el.tag
        x, y = int(el.get("x", 0)), int(el.get("y", 0))
        ew, eh = int(el.get("w", 0)), int(el.get("h", 0))
        if el.get("hidden") == "true":
            continue

        if t == "image":
            src = el.get("src")
            path = os.path.join(RES, src + ".png")
            if not os.path.exists(path):
                path = os.path.join(RES, src + ".jpg")
            if os.path.exists(path):
                im = Image.open(path).convert("RGBA")
                if im.size != (ew, eh):
                    im = im.resize((ew, eh), Image.LANCZOS)
                canvas.alpha_composite(im, (x, y))
        elif t == "label" or t == "textarea":
            draw_text(ImageDraw.Draw(canvas), (x, y, ew, eh), el.get("text", ""),
                      int(float(el.get("font_size", 12))),
                      hex_rgb(el.get("color", "#ffffff")), el.get("align", "left"))
        elif t == "chart":
            draw_chart(canvas, el, x, y, ew, eh)
        elif t == "table":
            draw_table(canvas, el, x, y, ew, eh)
        elif t == "slider":
            draw_slider(canvas, el, x, y, ew, eh)
        # keyboard 默认 hidden，跳过

    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "device_%s.png" % tag)
    canvas.convert("RGB").save(out)
    print("预览 ->", out)
    return canvas


def draw_chart(canvas, el, x, y, w, h):
    dr = ImageDraw.Draw(canvas)
    lo, hi = float(el.get("y-min", 0)), float(el.get("y-max", 100))
    for s in el.findall("series"):
        vals = [float(v) for v in (s.get("values") or "").split(",") if v != ""]
        if len(vals) < 2:
            continue
        pts = []
        for i, v in enumerate(vals):
            px = x + i * (w / (len(vals) - 1))
            py = y + h - (v - lo) / (hi - lo) * h
            pts.append((px, py))
        dr.line(pts, fill=hex_rgb(s.get("color", "#ffffff")), width=2, joint="curve")


def draw_table(canvas, el, x, y, w, h):
    dr = ImageDraw.Draw(canvas)
    rows = int(el.get("rows", 7))
    cols = int(el.get("columns", 6))
    rh = int(float(el.get("row-height", 22)))
    widths = [int(v) for v in (el.get("col-widths") or "").split(",") if v.strip()]
    if len(widths) != cols:
        widths = [w // cols] * cols
    bg = hex_rgb(el.get("background", "#0a1013"))
    hdr = hex_rgb(el.get("header-color", "#1b2327"))
    alt = hex_rgb(el.get("alternate-color", "#121b1f"))
    border = hex_rgb(el.get("border-color", "#1d272c"))
    fs = int(float(el.get("font_size", 11)))
    aligns = (el.get("col-aligns") or "").split(",")

    top = y
    for r in range(rows):
        fill = hdr if r == 0 else (alt if r % 2 == 1 else bg)
        dr.rectangle([x, top, x + w - 1, top + rh - 1], fill=fill)
        for c in range(cols):
            cx = x + sum(widths[:c])
            txt = ""
            if r < len(TABLE_SEED) and c < len(TABLE_SEED[r]):
                txt = TABLE_SEED[r][c]
            color = (139, 150, 155, 255) if r == 0 else (214, 220, 222, 255)
            if r > 0 and txt == "严重":
                color = (255, 139, 128, 255)
            elif r > 0 and txt == "警告":
                color = (240, 205, 126, 255)
            al = aligns[c].strip() if c < len(aligns) else "left"
            draw_text(dr, (cx + 8, top, widths[c] - 16, rh), txt, fs, color, al)
        dr.line([x, top, x + w, top], fill=border)
        top += rh
    dr.rectangle([x, y, x + w - 1, min(top, y + h) - 1], outline=border)


def draw_slider(canvas, el, x, y, w, h):
    dr = ImageDraw.Draw(canvas)
    lo, hi = float(el.get("min", 0)), float(el.get("max", 100))
    val = float(el.get("value", lo))
    frac = 0 if hi <= lo else (val - lo) / (hi - lo)
    cy = y + h // 2
    dr.rounded_rectangle([x, cy - 5, x + w, cy + 5], radius=5, fill=(13, 17, 19, 255))
    tw = int(w * frac)
    if tw > 4:
        dr.rounded_rectangle([x + 1, cy - 4, x + tw, cy + 4], radius=4, fill=(40, 120, 190, 255))
    sx = x + tw - 8
    thumb = os.path.join(RES, (el.get("knob-src") or "thumb") + ".png")
    if os.path.exists(thumb):
        im = Image.open(thumb).convert("RGBA")
        canvas.alpha_composite(im, (max(x, min(x + w - im.width, sx)), cy - im.height // 2))


def main():
    tree = ET.parse(os.path.join(RES, "main.xml"))
    root = tree.getroot()
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    for page in root.find("pages"):
        pid = page.get("id")
        if only and pid != only:
            continue
        render_page(page, pid)


if __name__ == "__main__":
    main()
