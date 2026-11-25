# -*- coding: utf-8 -*-
r"""儿童房控制面板 · 贴图流水线（拆格 + 降采样 + Twemoji 本地化）

为什么要在构建期拆图（真机踩坑，必须遵守）：
  1. 参考效果稿给的套图是 960×640（3×2 六格）与 1600×320（1×5 角色条），
     整张解码要 1.2MB 以上，直接超真机 1MB 图片缓存；
  2. AirUI 的 image 没有"按 CSS background-position 裁格"的能力，只能一图一格；
  3. PNG 只能有一个 IDAT（多 IDAT 硬件解码器不认），所以本脚本自己写 PNG 容器；
  4. 按最终显示尺寸出图，Lua 侧 w/h 直接等于原图尺寸，避免真机缩放发糊；
  5. 缩放走"预乘 alpha"，避免透明边缘在浅色卡上出现黑边。

产物（全部平铺进 code/，对应 /luadb/）：
  st_<theme>_<0..5>.png        装饰贴纸 96×96（六格套图）
  ch_<theme>_<0..4>_big.png    角色大图 170×170（房间大角色 / 预览圆 / 封面）
  ch_<theme>_<0..4>_sm.png     角色小图 56×56（弧上小人 / 头像 / 磁贴）
  ic_<name>.png                功能图标 72×72（Twemoji，CC-BY 4.0）

用法：
  python gen_assets.py                 # 生成到 ../code/
  python gen_assets.py --sd E:\        # 额外导出到 E:\\kidsroom\\（TF 卡覆盖用）
  python gen_assets.py --check         # 只体检已有产物（尺寸/IDAT/总量）
"""

import os
import struct
import sys
import urllib.request
import zlib

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CODE_DIR = os.path.join(os.path.dirname(HERE), "code")
SRC_DIR = os.path.join(HERE, "assets")            # 参考效果稿给的 webp 原件
CACHE_DIR = os.path.join(HERE, ".cache", "twemoji")

THEMES = ("toy", "bear", "hero", "pocket", "sheep")

SHEET_COLS, SHEET_ROWS = 3, 2                     # 960×640 → 6 格
CAST_COLS = 5                                     # 1600×320 → 5 格
ST_SIZE = 96
CH_BIG = 170
CH_SM = 56
ICO_SIZE = 72

# 与效果稿 ICON 表完全一致（key → Twemoji 码位）
ICONS = {
    "sun": "2600", "drop": "1f4a7", "star": "2b50", "sparkle": "2728",
    "lamp": "1f4a1", "note": "1f3b5", "flower": "1f338", "book": "1f4d6",
    "rocket": "1f680", "moon": "1f319", "cloud": "2601", "projector": "1f4fa",
    "curtain": "1fa9f", "humid": "1f4a7", "speaker": "1f50a",
}
TWEMOJI_URL = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@15.1.0/assets/72x72/%s.png"


# ---------------------------------------------------------------- PNG（单 IDAT）
def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png_single_idat(path, img):
    img = img.convert("RGBA")
    w, h = img.size
    px = img.tobytes()                      # RGBA 连续排列
    stride = w * 4
    raw = bytearray()
    for y in range(h):
        raw.append(0)                       # filter type 0（真机解码器只认简单 filter）
        raw += px[y * stride:(y + 1) * stride]
    out = bytearray(b"\x89PNG\r\n\x1a\n")
    out += _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    out += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(bytes(out))
    return len(out)


def idat_count(path):
    with open(path, "rb") as f:
        return f.read().count(b"IDAT")


# ---------------------------------------------------------------- 图像处理
def scale(img, size):
    """预乘 alpha 缩放，避免透明边缘发黑（浅色卡上尤其明显）。"""
    return img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")


def open_src(name):
    path = os.path.join(SRC_DIR, name)
    if not os.path.isfile(path):
        raise SystemExit("缺少源图：%s（从参考效果稿的 assets 目录复制进 docs/assets/）" % path)
    return Image.open(path).convert("RGBA")


def split_cells(img, cols, rows):
    cw, ch = img.size[0] // cols, img.size[1] // rows
    for r in range(rows):
        for c in range(cols):
            yield img.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))


def fetch_twemoji(name, code):
    """构建期下载一次并缓存；已缓存则不联网。"""
    os.makedirs(CACHE_DIR, exist_ok=True)
    cache = os.path.join(CACHE_DIR, "%s.png" % code)
    if not os.path.isfile(cache):
        url = TWEMOJI_URL % code
        print("  下载 %s -> %s" % (url, os.path.basename(cache)))
        with urllib.request.urlopen(url, timeout=30) as r, open(cache, "wb") as f:
            f.write(r.read())
    return Image.open(cache).convert("RGBA")


# ---------------------------------------------------------------- 主流程
def build_jobs():
    """返回 [(输出文件名, PIL.Image, 说明)]，顺序稳定便于 diff。"""
    jobs = []
    for theme in THEMES:
        sheet = open_src("%s.webp" % theme)
        cells = list(split_cells(sheet, SHEET_COLS, SHEET_ROWS))
        for k, cell in enumerate(cells):
            jobs.append(("st_%s_%d.png" % (theme, k), scale(cell, ST_SIZE),
                         "%s 装饰贴纸 k%d" % (theme, k)))

        cast = open_src("%s_cast.webp" % theme)
        chars = list(split_cells(cast, CAST_COLS, 1))
        for i, ch in enumerate(chars):
            jobs.append(("ch_%s_%d_big.png" % (theme, i), scale(ch, CH_BIG),
                         "%s 角色%d 大图" % (theme, i)))
            jobs.append(("ch_%s_%d_sm.png" % (theme, i), scale(ch, CH_SM),
                         "%s 角色%d 小图" % (theme, i)))

    for name, code in ICONS.items():
        jobs.append(("ic_%s.png" % name, fetch_twemoji(name, code),
                     "功能图标 %s（Twemoji %s）" % (name, code)))
    return jobs


def check():
    bad = 0
    total = 0
    for name in sorted(os.listdir(CODE_DIR)):
        if not name.endswith(".png"):
            continue
        path = os.path.join(CODE_DIR, name)
        img = Image.open(path)
        n = idat_count(path)
        total += os.path.getsize(path)
        if n != 1:
            print("  [FAIL] %s 有 %d 个 IDAT" % (name, n))
            bad += 1
    print("体检：%d 个 PNG，%d KB，异常 %d 个" % (
        len([1 for n in os.listdir(CODE_DIR) if n.endswith(".png")]), total // 1024, bad))
    return bad == 0


def main():
    if "--check" in sys.argv:
        check()
        return

    sd_dir = None
    if "--sd" in sys.argv:
        sd_dir = os.path.join(sys.argv[sys.argv.index("--sd") + 1], "kidsroom")
        os.makedirs(sd_dir, exist_ok=True)

    os.makedirs(CODE_DIR, exist_ok=True)
    jobs = build_jobs()

    total = 0
    print("%-22s %5s %5s %7s %5s" % ("file", "w", "h", "bytes", "idat"))
    for name, img, _desc in jobs:
        path = os.path.join(CODE_DIR, name)
        size = write_png_single_idat(path, img)
        total += size
        assert idat_count(path) == 1, "%s 有多个 IDAT" % name
        print("%-22s %5d %5d %7d %5d" % (name, img.size[0], img.size[1], size, 1))
        if sd_dir:
            write_png_single_idat(os.path.join(sd_dir, name), img)

    # 解码峰值：一屏最多同时看到 5 个角色大图 + 8 张装饰 + 8 个图标
    peak = 5 * CH_BIG ** 2 * 2 + 8 * ST_SIZE ** 2 * 2 + 8 * ICO_SIZE ** 2 * 2
    print("---")
    print("共 %d 张，%d 字节（%.1f MB）；单主题同屏解码峰值约 %d KB（真机缓存 1024KB）"
          % (len(jobs), total, total / 1048576.0, peak // 1024))
    if peak > 900 * 1024:
        print("  [WARN] 峰值逼近缓存上限，考虑再次降采样")
    if sd_dir:
        print("已同时导出到", sd_dir)


if __name__ == "__main__":
    main()
