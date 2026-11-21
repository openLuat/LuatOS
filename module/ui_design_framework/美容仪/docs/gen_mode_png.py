# -*- coding: utf-8 -*-
"""
把 docs/img 的 480x320 单 IDAT 图缩到真机尺寸，输出到 code/ 供 luadb 打包。

真机两道硬门槛（F7）：
  格式  硬件解码只认「单个 IDAT 块」。PIL 默认按 zlib 缓冲切片，一张 420x280
        能切出几十个 IDAT，硬件探测直接失败，表现为日志干净但图片不显示。
  缓存  单张解码 = w*h*4 字节。420x280 = 470400B，同屏 3 张约 1.41MB，
        Air1603 出厂缓存实测 4MB。

主题只用一套图：暗色主题不做染色版，改为「深蓝相框 + 暖白展示窗」——
图片内容一个像素都不改，由 ui_carousel 的垫层与遮边条表达主题差异。
所以这里永远只输出 6 张，不要再加 _dark 分支。

比例：源图 480x320 = 1.5，输出 420x280 = 1.5，等比 0.875，不变形。
焦点卡 420x264 与侧卡 234x208 都用同一张裁切，不需要出两套尺寸。
"""
import os
import struct
import zlib

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "img")
DST = os.path.join(HERE, "..", "code")

W, H = 420, 280
KEYS = ["clean", "import", "ems", "rf", "led", "cool"]


def write_png_single_idat(path, im):
    """整幅像素 → 一个 zlib 流 → 一个 IDAT"""
    im = im.convert("RGB")
    w, h = im.size
    px = im.load()
    raw = bytearray()
    for y in range(h):
        raw.append(0)                      # filter type 0
        for x in range(w):
            raw.extend(px[x, y])
    comp = zlib.compress(bytes(raw), 9)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    out = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
           chunk(b"IDAT", comp) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(out)
    return len(out)


def idat_count(path):
    with open(path, "rb") as f:
        d = f.read()
    n, i = 0, 8
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        if d[i + 4:i + 8] == b"IDAT":
            n += 1
        i += 12 + ln
    return n


def main():
    if not os.path.isdir(SRC):
        raise SystemExit("找不到源图目录 %s" % SRC)
    total = 0
    for k in KEYS:
        s = os.path.join(SRC, "mode_%s.png" % k)
        if not os.path.exists(s):
            print("!! 缺失 %s" % s)
            continue
        im = Image.open(s).convert("RGB")
        if im.size != (W, H):
            im = im.resize((W, H), Image.LANCZOS)
        p = os.path.join(DST, "mode_%s.png" % k)
        size = write_png_single_idat(p, im)
        total += size
        print("%-18s %dx%d %6.1fKB IDAT=%d" %
              (os.path.basename(p), im.size[0], im.size[1], size / 1024.0,
               idat_count(p)))
    per = W * H * 4
    print("解压单张 %.0fKB，同屏 3 张 %.2fMB / 缓存 4MB"
          % (per / 1024.0, per * 3 / 1048576.0))
    print("打包体积合计 %.1fKB" % (total / 1024.0))


if __name__ == "__main__":
    main()
