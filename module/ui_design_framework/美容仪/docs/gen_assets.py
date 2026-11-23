# -*- coding: utf-8 -*-
"""
美容仪 UI 资源生成器（设计稿用）

产物全部落在 docs/img/：
  mode_clean.png   深层清洁   —— 水滴 + 波纹
  mode_import.png  精华导入   —— 下行箭头穿过皮表线
  mode_ems.png     微电流提拉 —— 闪电 + 电流刻度
  mode_rf.png      射频紧致   —— 同心射频弧 + 热核
  mode_led.png     光子嫩肤   —— 中心光核 + 放射光线
  mode_cool.png    冰感舒缓   —— 六角雪花

风格统一：深色底 + 居中线描符号 + 同形光晕（先模糊层再实线层），
符号本身是"可读的图标"而不是抽象光效。

三条硬约束（对应 AGENTS.md F7）：
  1) 每张 PNG 只写 **一个 IDAT 块**（PIL 默认切片，硬件解码器直接拒绝）；
  2) 单张 w*h <= 262144（本脚本 400x240 = 96000）；
  3) RGB 8bit、无交错，真机解码路径最短。

用法： python gen_assets.py
"""
import os
import zlib
import math
import struct
from PIL import Image, ImageDraw, ImageFilter

W, H = 400, 240
CX, CY = 200, 122


# ---------------------------------------------------------------- PNG 单 IDAT
def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def save_png(img, path):
    img = img.convert("RGB")
    w, h = img.size
    raw = b"".join(b"\x00" + img.crop((0, y, w, y + 1)).tobytes() for y in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(_chunk(b"IHDR", ihdr))
        f.write(_chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(_chunk(b"IEND", b""))
    return os.path.getsize(path)


def count_idat(path):
    d = open(path, "rb").read()
    i, n = 8, 0
    while i + 8 <= len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        n += d[i + 4:i + 8] == b"IDAT"
        i += 12 + ln
    return n


# ---------------------------------------------------------------- 基础绘制
def vgrad(w, h, c0, c1):
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1.0)
        col.putpixel((0, y), tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)))
    return col.resize((w, h))


def glow(base, color, center, radius, strength, power=2.0):
    w, h = base.size
    mask = Image.new("L", (w, h), 0)
    px = mask.load()
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - center[0], y - center[1]) / radius
            if d < 1.0:
                px[x, y] = int(255 * strength * (1.0 - d) ** power)
    return Image.composite(Image.new("RGB", (w, h), color), base, mask)


def vignette(img, strength=0.5, start=0.34):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    px = mask.load()
    for y in range(h):
        for x in range(w):
            dx = (x - w / 2.0) / (w / 2.0)
            dy = (y - h / 2.0) / (h / 2.0)
            d = math.hypot(dx, dy) / 1.4142
            if d > start:
                px[x, y] = int(255 * strength * ((d - start) / (1.0 - start)) ** 1.6)
    return Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), img, mask)


def layer_draw(img, fn, blur=0.0):
    """在透明层上画，可选模糊，再叠到 img 上。"""
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    fn(d)
    if blur:
        ov = ov.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(img.convert("RGBA"), ov).convert("RGB")


def glyph(img, fn, color, blur=4.0, halo=120):
    """同一个符号画两遍：先模糊大光晕，再锐利实线，得到"发光线条"观感。"""
    img = layer_draw(img, lambda d: fn(d, color + (halo,)), blur=blur)
    img = layer_draw(img, lambda d: fn(d, color + (255,)))
    return img


# ---- 通用符号零件（供六个模式复用）
def wave(d, y, c, x0, x1, amp=6, step=4, wk=0.28, width=3):
    pts = [(x, y + math.sin((x - x0) * wk) * amp)
           for x in range(x0, x1 + 1, step)]
    d.line(pts, fill=c, width=width, joint="curve")


def sparkle_ring(d, cx, cy, r, c, n=12, seg=14, width=2):
    """虚线圆环：n 段短圆弧。"""
    for i in range(n):
        a0 = i * (360.0 / n)
        d.arc([cx - r, cy - r, cx + r, cy + r], a0, a0 + seg, fill=c, width=width)


# ---------------------------------------------------------------- 六个模式图标
def m_clean():
    """水滴 + 水波：洁面/清洁。顶点与圆用切线相连，避免出现折角像气球。"""
    img = vgrad(W, H, (11, 28, 36), (4, 9, 12))
    img = glow(img, (56, 158, 178), (CX, CY + 8), 190, 0.38)

    def g(d, c):
        # 圆 r=40 心(200,122)，顶点(200,46)：切线切点 = (166,101)/(234,101)
        d.ellipse([160, 82, 240, 162], outline=c, width=3)
        d.line([(166, 101), (200, 46)], fill=c, width=3)
        d.line([(234, 101), (200, 46)], fill=c, width=3)
        wave(d, 190, c, 148, 252, amp=6, width=3)

    return vignette(glyph(img, g, (152, 226, 241)))


def m_import():
    """皮表线 + 三滴精华 + 下行箭头：精华导入。"""
    img = vgrad(W, H, (29, 24, 17), (8, 7, 6))
    img = glow(img, (201, 169, 106), (CX, CY), 190, 0.36)

    def g(d, c):
        d.line([(148, 78), (252, 78)], fill=c, width=3)
        d.ellipse([166, 92, 173, 99], fill=c)
        d.ellipse([199, 92, 206, 99], fill=c)
        d.ellipse([232, 92, 239, 99], fill=c)
        d.line([(200, 112), (200, 168)], fill=c, width=3)
        d.line([(200, 168), (181, 149)], fill=c, width=3)
        d.line([(200, 168), (219, 149)], fill=c, width=3)

    return vignette(glyph(img, g, (250, 228, 180)))


def m_ems():
    """闪电 + 两侧电流刻度：微电流。"""
    img = vgrad(W, H, (21, 18, 37), (7, 6, 12))
    img = glow(img, (124, 107, 200), (CX, CY), 190, 0.36)

    def g(d, c):
        bolt = [(212, 58), (176, 122), (202, 122), (184, 178), (224, 110), (198, 110)]
        d.line(bolt + [bolt[0]], fill=c, width=3, joint="curve")
        for y in (78, 116, 154):
            d.line([(140, y), (161, y)], fill=c, width=2)
            d.line([(239, y), (260, y)], fill=c, width=2)

    return vignette(glyph(img, g, (196, 184, 255)))


def m_rf():
    """热核 + 左右对称脉冲波：射频。用左右开口弧，避免读成 WiFi。"""
    img = vgrad(W, H, (39, 20, 16), (10, 6, 6))
    img = glow(img, (196, 90, 62), (CX, CY), 190, 0.38)

    def g(d, c):
        d.ellipse([CX - 10, CY - 10, CX + 10, CY + 10], fill=c)
        for i, r in enumerate((26, 44, 62)):
            box = [CX - r, CY - r, CX + r, CY + r]
            d.arc(box, 128, 232, fill=c, width=3)
            d.arc(box, -52, 52, fill=c, width=3)

    return vignette(glyph(img, g, (255, 180, 138)))


def m_led():
    """光核 + 放射光线：光疗。"""
    img = vgrad(W, H, (35, 16, 29), (10, 6, 10))
    img = glow(img, (214, 108, 150), (CX, CY), 190, 0.36)

    def g(d, c):
        d.ellipse([CX - 20, CY - 20, CX + 20, CY + 20], outline=c, width=3)
        for i in range(8):
            a = math.radians(i * 45)
            dx, dy = math.cos(a), math.sin(a)
            d.line([(CX + dx * 32, CY + dy * 32), (CX + dx * 54, CY + dy * 54)],
                   fill=c, width=3)
        sparkle_ring(d, CX, CY, 70, c, n=12, seg=12, width=2)

    return vignette(glyph(img, g, (255, 205, 228)))


def m_cool():
    """六角雪花：冰感。"""
    img = vgrad(W, H, (15, 27, 39), (5, 8, 12))
    img = glow(img, (120, 178, 214), (CX, CY), 190, 0.36)

    def g(d, c):
        for ang in (0, 60, 120):
            a = math.radians(ang)
            dx, dy = math.cos(a), math.sin(a)
            p1 = (CX - dx * 68, CY - dy * 68)
            p2 = (CX + dx * 68, CY + dy * 68)
            d.line([p1, p2], fill=c, width=3)
            for p, s in ((p1, -1), (p2, 1)):
                for da in (38, -38):
                    b = math.radians(ang + da)
                    d.line([p, (p[0] + s * math.cos(b) * 24,
                                p[1] + s * math.sin(b) * 24)], fill=c, width=3)

    return vignette(glyph(img, g, (188, 226, 245)))


MODES = [("clean", m_clean), ("import", m_import), ("ems", m_ems),
         ("rf", m_rf), ("led", m_led), ("cool", m_cool)]


def main():
    root = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(root, "img")
    if not os.path.isdir(out):
        os.makedirs(out)

    rows = []
    for name, fn in MODES:
        p = os.path.join(out, "mode_%s.png" % name)
        img = fn()
        size = save_png(img, p)
        rows.append(("mode_%s.png" % name, img.size, size, count_idat(p)))

    print("%-18s %-10s %8s %6s" % ("file", "wxh", "bytes", "IDAT"))
    for n, sz, b, c in rows:
        flag = "OK" if (c == 1 and sz[0] * sz[1] <= 262144) else "FAIL"
        print("%-18s %-10s %8d %6d  %s" % (n, "%dx%d" % sz, b, c, flag))


if __name__ == "__main__":
    main()
