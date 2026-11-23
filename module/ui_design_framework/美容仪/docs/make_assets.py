# -*- coding: utf-8 -*-
"""把 img_raw/ 里的 AI 器械图处理成真机可用的模式图。

  · 去掉右下角模型水印：用其左侧同尺寸的纯背景块覆盖（背景是平滑渐变，无痕）；
  · 统一缩放到 480x320（与原图同 1.5:1，不变形）；
  · 输出强制单个 IDAT（真机硬件解码不接受多 IDAT）。

主体大小差异交由页面控制（object-fit / object-position），不在这里裁主体：
自动检测在这批渐变背景图上反复失准，写死窗口更可靠。

用法： python make_assets.py
"""
import os
import zlib

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "img_raw")
OUT = os.path.join(HERE, "img")

W, H = 480, 320

# key -> (中心 x, 中心 y, 放大倍数)，坐标是相对原图的比例
CROP = {
    "clean":  (0.48, 0.52, 1.46),
    "import": (0.52, 0.51, 1.46),
    "ems":    (0.51, 0.50, 1.42),
    "rf":     (0.51, 0.55, 1.46),
    "led":    (0.49, 0.62, 1.26),
    "cool":   (0.50, 0.57, 1.62),
}

SRC = {
    "clean": "Professional_product_photograp_2026-11-19T12-05-01.png",
    "import": "Professional_product_photograp_2026-11-19T12-06-00.png",
    "ems": "Professional_product_photograp_2026-11-19T12-06-14.png",
    "rf": "Professional_product_photograp_2026-11-19T12-06-29.png",
    "led": "Professional_product_photograp_2026-11-19T12-06-45.png",
    "cool": "Professional_product_photograp_2026-11-19T12-05-33.png",
}


def save_single_idat(img, path):
    """整幅像素 -> 一个 zlib 流 -> 一个 IDAT。"""
    arr = np.asarray(img.convert("RGB"), dtype=np.uint8)
    h, w, _ = arr.shape
    raw = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))
    comp = zlib.compress(raw, 9)

    def chunk(tag, data):
        return (len(data).to_bytes(4, "big") + tag + data
                + (zlib.crc32(tag + data) & 0xFFFFFFFF).to_bytes(4, "big"))

    ihdr = w.to_bytes(4, "big") + h.to_bytes(4, "big") + bytes([8, 2, 0, 0, 0])
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", comp) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def drop_watermark(img, wm_w=280, wm_h=200):
    """右下角水印区按「左边缘 + 上边缘 − 角点」的加性结构外推重建。

    背景是平滑渐变，加性外推在边界处与真实像素衔接，不会留下矩形补丁；
    外推面本身过于规整，最后对整块做一次轻模糊抹掉机械纹理。
    """
    w, h = img.size
    arr = np.asarray(img).astype(np.float32)
    x0, y0 = w - wm_w, h - wm_h
    left = arr[y0:h, x0 - 1]
    top = arr[y0 - 1, x0:w]
    corner = arr[y0 - 1, x0 - 1]
    arr[y0:h, x0:w] = left[:, None, :] + top[None, :, :] - corner
    noise = np.random.normal(0, 0.7, (wm_h, wm_w, 1)).astype(np.float32)
    arr[y0:h, x0:w] = np.clip(arr[y0:h, x0:w] + noise, 0, 255)

    out = Image.fromarray(arr.astype(np.uint8))
    patch = out.crop((x0, y0, w, h)).filter(ImageFilter.GaussianBlur(1.8))
    out.paste(patch, (x0, y0))
    return out


def tone(img, target=(249, 248, 245)):
    """平场校正：把渐变米黄背景拉成中性近白，机身保持原色。

    背景是二维渐变，单点白平衡救不回来。改从每一行的左右两条边带取背景色，
    横向线性插值出光照场再逐像素除掉 —— 主体都在画面中央、不碰左右边，
    所以边带里只有背景，这样估计不需要任何主体检测。
    高光做软膝压缩，最后加抖动避免 8bit 色带。
    """
    arr = np.asarray(img).astype(np.float32)
    h, w, _ = arr.shape
    s = max(3, int(w * 0.055))
    left = arr[:, :s].mean(axis=1)          # (h, 3)
    right = arr[:, -s:].mean(axis=1)        # (h, 3)

    # 边带自身有噪点，纵向做一次平滑再插值
    k = np.ones(9, np.float32) / 9.0

    def smooth(v):
        return np.stack([np.convolve(v[:, c], k, "same") for c in range(3)], axis=1)

    left, right = smooth(left), smooth(right)

    t = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :, None]
    field = left[:, None, :] * (1.0 - t) + right[:, None, :] * t
    arr = arr * (np.array(target, np.float32) / np.maximum(field, 1.0))

    # 以中灰为支点轻微提对比
    arr = (arr - 128.0) * 1.06 + 128.0

    # 高光软膝：236 以上逐渐压缩到 255 以内
    over = np.maximum(arr - 236.0, 0.0)
    arr = np.minimum(arr, 236.0) + over / (1.0 + over / 24.0)

    # 抖动，避免平滑渐变在 8bit 上出现色带
    arr += np.random.normal(0, 0.5, arr.shape[:2])[:, :, None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def crop(key, img):
    """按写死的窗口裁切，把器械放大到画面的 7 成左右。

    窗口中心与缩放是逐张读出来的（六张主体都在中央，x≈0.50），
    比自动检测可靠：背景是渐变，阈值法与投影法在这批图上都反复失准。
    """
    ox, oy, z = CROP[key]
    w, h = img.size
    bw, bh = w / z, h / z
    x0 = min(max(0, w * ox - bw / 2), w - bw)
    y0 = min(max(0, h * oy - bh / 2), h - bh)
    return img.crop((int(x0), int(y0), int(x0 + bw), int(y0 + bh)))


def process(key, name):
    src = Image.open(os.path.join(RAW, name)).convert("RGB")
    src = tone(crop(key, drop_watermark(src)))
    out = src.resize((W, H), Image.LANCZOS)
    path = os.path.join(OUT, "mode_%s.png" % key)
    save_single_idat(out, path)
    print("  %-7s %dx%d -> %dx%d  %s"
          % (key, src.size[0], src.size[1], W, H, os.path.basename(path)))


def main():
    os.makedirs(OUT, exist_ok=True)
    print("处理 %d 张：" % len(SRC))
    for key, name in SRC.items():
        p = os.path.join(RAW, name)
        if not os.path.exists(p):
            print("  %-7s 缺源图 %s" % (key, name))
            continue
        process(key, name)


if __name__ == "__main__":
    main()
