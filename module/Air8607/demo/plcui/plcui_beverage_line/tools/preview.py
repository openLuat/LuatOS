"""离线预览：把 main.xml + 素材合成为 PNG，方便在没有模拟器时检查排版。

只用于设计校对，不参与真机运行。图表用网格线示意，表格用网格 + 文字示意。

    python tools/preview.py            # 输出全部页面到 preview/
    python tools/preview.py realtime   # 只输出指定页面
"""

import os
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CODE = os.path.join(ROOT, "code", "res")  # main.xml + 图片都在 res/ 下
OUT = os.path.join(ROOT, "preview")
FONT_PATH = r"C:\Windows\Fonts\msyh.ttc"

_fonts = {}


def font(size):
    if size not in _fonts:
        _fonts[size] = ImageFont.truetype(FONT_PATH, size)
    return _fonts[size]


def color(text, default="#ffffff"):
    text = text or default
    text = text.lstrip("#")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


def draw_text(img, box, text, size, fill, align):
    if not text:
        return
    draw = ImageDraw.Draw(img)
    f = font(size)
    x, y, w = box
    tw = draw.textlength(text, font=f)
    if align == "center":
        x = x + (w - tw) / 2
    elif align == "right":
        x = x + w - tw
    draw.text((x, y), text, font=f, fill=fill)


def draw_chart(img, node):
    draw = ImageDraw.Draw(img)
    x, y = int(node.get("x")), int(node.get("y"))
    w, h = int(node.get("w")), int(node.get("h"))
    hdiv = int(node.get("hdiv") or 0)
    vdiv = int(node.get("vdiv") or 0)
    grid = color(node.get("grid-color"), "#1d5871")
    for i in range(hdiv + 1):
        yy = y + h * i / max(hdiv, 1)
        draw.line([(x, yy), (x + w, yy)], fill=grid, width=1)
    for i in range(vdiv + 1):
        xx = x + w * i / max(vdiv, 1)
        draw.line([(xx, y), (xx, y + h)], fill=grid, width=1)

    ymin = float(node.get("y-min"))
    ymax = float(node.get("y-max"))
    points = int(node.get("point-count"))
    bar = node.get("type") == "bar"
    series = node.findall("series")
    groups = len(series)
    for si, s in enumerate(series):
        values = [float(v) for v in s.get("values").split(",")]
        c = color(s.get("color"))
        if bar:
            slot = w / max(points, 1)
            bw = max(2, int(slot / max(groups, 1)) - 2)
            for i, v in enumerate(values):
                bh = (v - ymin) / (ymax - ymin) * h
                bx = x + i * slot + si * (slot / max(groups, 1))
                draw.rectangle([bx, y + h - bh, bx + bw, y + h], fill=c)
        else:
            pts = []
            for i, v in enumerate(values):
                px = x + w * i / max(points - 1, 1)
                py = y + h - (v - ymin) / (ymax - ymin) * h
                pts.append((px, py))
            if len(pts) > 1:
                draw.line(pts, fill=c, width=2)


def draw_table(img, node, cells):
    draw = ImageDraw.Draw(img)
    x, y = int(node.get("x")), int(node.get("y"))
    w, h = int(node.get("w")), int(node.get("h"))
    rows, cols = int(node.get("rows")), int(node.get("columns"))
    draw.rectangle([x, y, x + w, y + h], fill=color(node.get("background"), "#061e2c"),
                   outline=color(node.get("border-color"), "#265a73"))
    widths = [int(v) for v in (node.get("col-widths") or "").split(",") if v.strip()]
    if len(widths) != cols:
        widths = [w // cols] * cols
    rh = h / rows
    header = node.get("header", "true") == "true"
    for r in range(rows):
        if r == 0 and header:
            draw.rectangle([x, y, x + w, y + rh], fill=color(node.get("header-color"), "#0d3d55"))
        cx = x
        for c in range(cols):
            text = cells.get((r + 1, c + 1), "")
            if text:
                f = font(int(node.get("font_size") or 12))
                tw = draw.textlength(text, font=f)
                if c == 0:
                    tx = cx + 4
                else:
                    tx = cx + (widths[c] - tw) / 2
                draw.text((tx, y + r * rh + (rh - (int(node.get("font_size") or 12))) / 2 - 1),
                          text, font=f, fill=color(node.get("color"), "#dff2fb"))
            cx += widths[c]


def render(page, resources, root):
    img = Image.new("RGB", (int(root.get("width")), int(root.get("height"))), (4, 18, 31))
    cells = {}
    for w in page:
        if w.tag == "table":
            for cell in w.findall("cell"):
                cells[(int(cell.get("row")), int(cell.get("column")))] = cell.get("text")
    for w in page:
        tag = w.tag
        if w.get("hidden") == "true":
            continue
        if tag == "image":
            src = resources.get(w.get("src"))
            if not src:
                continue
            pic = Image.open(os.path.join(CODE, src)).convert("RGBA")
            x, y = int(w.get("x")), int(w.get("y"))
            ww, hh = int(w.get("w")), int(w.get("h"))
            if pic.size != (ww, hh):
                pic = pic.resize((ww, hh))
            img.paste(pic, (x, y), pic)
        elif tag == "label":
            draw_text(img, (int(w.get("x")), int(w.get("y")), int(w.get("w"))),
                      w.get("text"), int(w.get("font_size") or 16),
                      color(w.get("color")), w.get("align"))
        elif tag == "textarea":
            draw_text(img, (int(w.get("x")), int(w.get("y")), int(w.get("w"))),
                      w.get("text"), int(w.get("font_size") or 16),
                      color(w.get("color")), w.get("align"))
            draw = ImageDraw.Draw(img)
            draw.rectangle([int(w.get("x")), int(w.get("y")), int(w.get("x")) + int(w.get("w")),
                            int(w.get("y")) + int(w.get("h"))],
                           outline=(40, 90, 110), width=1)
        elif tag == "chart":
            draw_chart(img, w)
        elif tag == "table":
            draw_table(img, w, cells)
        elif tag == "keyboard":
            draw = ImageDraw.Draw(img)
            draw.rectangle([int(w.get("x")), int(w.get("y")),
                            int(w.get("x")) + int(w.get("w")), int(w.get("y")) + int(w.get("h"))],
                           fill=(8, 26, 38), outline=(40, 120, 145))
            draw_text(img, (int(w.get("x")), int(w.get("y")) + 4, int(w.get("w"))),
                      "数字键盘（运行时弹出）", 16, (120, 200, 220), "center")
    return img


def main():
    only = set(sys.argv[1:])
    root = ET.parse(os.path.join(CODE, "main.xml")).getroot()
    resources = {r.get("id"): r.get("src") for r in root.find("resources")}
    os.makedirs(OUT, exist_ok=True)
    for page in root.find("pages"):
        pid = page.get("id")
        if only and pid not in only:
            continue
        img = render(page, resources, root)
        path = os.path.join(OUT, f"{pid}.png")
        img.save(path)
        print("写出", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
