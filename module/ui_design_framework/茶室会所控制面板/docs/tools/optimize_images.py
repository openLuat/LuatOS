# -*- coding: utf-8 -*-
"""
图片后处理：裁掉 AI 生成图右下角水印，按用途裁切到目标比例并压缩尺寸。

用法（在本目录执行）：
    python tools/optimize_images.py

输入：docs/img/ 下的原图
输出：同名 PNG（原地覆盖），尺寸与体积都收敛到界面需要的量级。
"""

import os
from PIL import Image

IMG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "img")

# 水印固定在右下角，统一先切掉底部 96px
WATERMARK_H = 96


def crop_ratio(im, ratio_w, ratio_h):
    """按目标比例居中裁切，尽量保留画面主体（主体在中下部，向上取偏移）。"""
    w, h = im.size
    target = ratio_w / float(ratio_h)
    if w / float(h) > target:
        new_w = int(round(h * target))
        left = (w - new_w) // 2
        box = (left, 0, left + new_w, h)
    else:
        new_h = int(round(w / target))
        top = max(0, int((h - new_h) * 0.55))
        box = (0, top, w, top + new_h)
    return im.crop(box)


def process(name, ratio, out_size):
    path = os.path.join(IMG_DIR, name)
    if not os.path.exists(path):
        print("skip (missing):", name)
        return
    im = Image.open(path).convert("RGB")
    im = im.crop((0, 0, im.width, im.height - WATERMARK_H))
    im = crop_ratio(im, ratio[0], ratio[1])
    im = im.resize(out_size, Image.LANCZOS)
    im.save(path, "PNG", optimize=True)
    print("%-16s -> %sx%s  %d KB" % (name, out_size[0], out_size[1],
                                     os.path.getsize(path) // 1024))


if __name__ == "__main__":
    # 整屏背景：16:9，够 1024x600 用
    process("bg_night.png", (16, 9), (1280, 720))
    # 场景卡：4:3
    for card in ("dev_light.png", "dev_incense.png", "dev_music.png",
                 "dev_humid.png", "dev_ambient.png"):
        process(card, (4, 3), (720, 540))
