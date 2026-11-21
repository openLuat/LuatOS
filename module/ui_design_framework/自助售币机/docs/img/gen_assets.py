# -*- coding: utf-8 -*-
"""
自助售币机 · 图片素材生成器（真机 PNG 约束：单 IDAT 块）

输出：
  coin_hero.png   240x240  金币主视觉（透明底 RGBA，圆形安全区）

背景不再使用图片：页面背景由「纯色 + 矢量图元（circle / 1px rect）」构成，
真机为静态 shape，一次构建后不再重绘，零贴图、零解码缓存占用。

约束依据 AGENTS.md F7：
  单张显示 w*h <= 1048576；本图 384*384 = 147456，远低于阈值。
"""
import os
import math
import random
import struct
import zlib

from PIL import Image, ImageDraw, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))


def save_single_idat(img, path, keep_alpha=False):
    """整幅像素 -> 一个 zlib 流 -> 一个 IDAT 块。"""
    if keep_alpha:
        img = img.convert("RGBA")
        bpp, ctype = 4, 6
    else:
        img = img.convert("RGB")
        bpp, ctype = 3, 2
    w, h = img.size
    data = img.tobytes()
    stride = w * bpp
    raw = b"".join(b"\x00" + data[y * stride:(y + 1) * stride] for y in range(h))
    comp = zlib.compress(raw, 9)

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload +
                struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", comp))
        f.write(chunk(b"IEND", b""))


def clamp(v, lo=0.0, hi=255.0):
    return lo if v < lo else (hi if v > hi else v)


def make_coin(size=240):
    S = size
    c = S / 2.0
    R = S * 0.395           # 币半径
    img = Image.new("RGBA", (S, S), (13, 14, 17, 0))
    px = img.load()

    lx, ly, lz = -0.50, -0.56, 0.66
    nl = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / nl, ly / nl, lz / nl
    hx, hy, hz = lx, ly, lz + 1.0
    hn = math.sqrt(hx * hx + hy * hy + hz * hz)
    hx, hy, hz = hx / hn, hy / hn, hz / hn

    deep = (66, 44, 16)
    mid = (216, 170, 92)
    light = (255, 240, 210)

    for y in range(S):
        for x in range(S):
            dx = (x + 0.5 - c) / R
            dy = (y + 0.5 - c) / R
            r2 = dx * dx + dy * dy
            if r2 > 1.0:
                px[x, y] = (13, 14, 17, 0)
                continue

            r = math.sqrt(r2)
            z = math.sqrt(max(0.0, 1.0 - r2))

            ndotl = dx * lx + dy * ly + z * lz
            diff = max(0.0, ndotl)
            # 左上大面积柔光：让金属有"漫反射光晕"，不是塑料点光
            soft = math.exp(-(((dx + 0.40) ** 2 + (dy + 0.44) ** 2)) / 0.40)

            k = 0.20 + 0.95 * (diff ** 0.80) + 0.22 * soft

            # 外环带（浮雕台阶）
            if 0.895 <= r <= 0.977:
                k += 0.14
            # 环内缘的暗刻线
            if 0.845 <= r <= 0.870:
                k *= 0.62
            # 币外缘收边
            if r > 0.977:
                k *= 0.70

            k = clamp(k, 0.0, 1.6)
            rr = deep[0] + (mid[0] - deep[0]) * k
            gg = deep[1] + (mid[1] - deep[1]) * k
            bb = deep[2] + (mid[2] - deep[2]) * k

            lw = (soft ** 1.6) * 0.28
            rr += (light[0] - rr) * lw
            gg += (light[1] - gg) * lw
            bb += (light[2] - bb) * lw

            # 币面同心细纹（车花工艺）
            ripple = math.sin(r * 220.0) * 2.6
            rr += ripple
            gg += ripple
            bb += ripple * 0.9

            # 镜面高光（偏锐）+ 边缘菲涅尔
            spec = max(0.0, dx * hx + dy * hy + z * hz) ** 12 * 58
            edge = (1.0 - z) ** 4
            rr += spec * 0.95 + edge * 36 + 12
            gg += spec * 0.84 + edge * 26 + 8
            bb += spec * 0.60 + edge * 12

            px[x, y] = (int(clamp(rr)), int(clamp(gg)), int(clamp(bb)), 255)

    def star_pts(cx, cy, ro, ri, n=5, rot=-math.pi / 2):
        pts = []
        for i in range(n * 2):
            ang = rot + i * math.pi / n
            rad = ro if i % 2 == 0 else ri
            pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
        return pts

    # 压印浮雕：只留边缘的受光/背光线，不做整片压暗（避免"贴片"感）
    ro = R * 0.55
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(star_pts(c, c, ro, ro * 0.42), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.6))

    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(7)))
    edge = edge.filter(ImageFilter.GaussianBlur(1.0))
    hi = ImageChops.offset(edge, -2, -2).point(lambda v: int(v * 0.80))
    hi_dark = ImageChops.offset(edge, 2, 2).point(lambda v: int(v * 0.90))
    r_ch, g_ch, b_ch, a_ch = img.split()
    r_ch = ImageChops.subtract(ImageChops.add(r_ch, hi), hi_dark)
    g_ch = ImageChops.subtract(ImageChops.add(g_ch, hi), hi_dark)
    b_ch = ImageChops.subtract(ImageChops.add(b_ch, hi.point(lambda v: int(v * 0.78))), hi_dark)
    img = Image.merge("RGBA", (r_ch, g_ch, b_ch, a_ch))

    img = img.filter(ImageFilter.GaussianBlur(0.4))
    return img


def main():
    coin = make_coin(240)
    p2 = os.path.join(HERE, "coin_hero.png")
    save_single_idat(coin, p2, keep_alpha=True)
    print("written", p2, os.path.getsize(p2), "bytes")


if __name__ == "__main__":
    main()
