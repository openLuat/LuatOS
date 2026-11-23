"""生成两类无法从 HTML 截图得到的素材。

1. 电源开关按钮图（ov_btn_power_n / ov_btn_power_c）
   CSS radial-gradient 渲染出的红色圆相对外环偏左上 2-3px（截图实测），
   这里用几何作图保证外环、红圆、电源符号全部同心。
2. 传送带光点动画帧（anim_belt_0 ... anim_belt_7）
   plcui 没有移动组件的 API，产线动态靠 8 帧透明 PNG + set_src 轮播实现。

同时把 bg_ov.jpg 里旧的 CSS 开关抹掉，避免与新组件叠加出"双开关"。

用法（export_assets.py 导出时会自动调用，也可单独跑）：
    python tools/make_extra_assets.py
"""

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "code", "res")

# 开关几何（全部以圆心 center 为基准，保证同心）
SW_SIZE = 74
SW_C = SW_SIZE / 2
BG_FILL = (8, 20, 32)
BG_GRID = (13, 31, 45)

# 传送带动画帧
ANIM_W, ANIM_H = 742, 20
ANIM_FRAMES = 8
ANIM_DOT_GAP = 185.5


def _power_base(size=SW_SIZE):
    """开关图底：与 bg_ov.jpg 左下角一致的暗色网格。"""
    im = Image.new("RGBA", (size, size), BG_FILL + (255,))
    d = ImageDraw.Draw(im)
    for x in range(0, size, 10):
        d.line([(x, 0), (x, size)], fill=BG_GRID + (255,))
    for y in range(0, size, 10):
        d.line([(0, y), (size, y)], fill=BG_GRID + (255,))
    return im


def write_power_switch(out_dir, name, checked=False):
    """画一张完美同心的电源开关图（含背景底，盖回原位无痕）。

    checked=True  -> 暗红"断电"态；False -> 亮红"上电"态。
    """
    im = _power_base()
    d = ImageDraw.Draw(im)
    c = SW_C
    if checked:
        core = (168, 46, 66)
    else:
        core = (255, 77, 104)

    # 外环（2px，淡红近白）
    d.ellipse([c - 36, c - 36, c + 36, c + 36], outline=(214, 116, 132, 255), width=2)
    # 红色光晕：多层同心半透明圆，模拟 radial-gradient 外圈
    for r, a in ((30, 16), (27, 28), (24, 44), (21, 64)):
        d.ellipse([c - r, c - r, c + r, c + r], fill=core + (a,))
    # 实心红圆
    d.ellipse([c - 18, c - 18, c + 18, c + 18], fill=core + (255,))
    # 电源符号：竖条（上）+ 圆弧（下），全部以 c 为水平中心
    d.rounded_rectangle([c - 3, c - 18, c + 3, c + 5], radius=3, fill=(255, 255, 255, 255))
    d.arc([c - 15, c - 9, c + 15, c + 21], start=310, end=230,
          fill=(255, 255, 255, 255), width=4)

    path = os.path.join(out_dir, f"{name}.png")
    im.save(path)
    return name


def write_anim_frame(out_dir, frame):
    """传送带光点帧：透明底，绿色光点沿传送带中心线流动。"""
    im = Image.new("RGBA", (ANIM_W, ANIM_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cy = 9
    phase = frame * ANIM_DOT_GAP / ANIM_FRAMES
    g = (43, 255, 158)
    i = -1
    while i * ANIM_DOT_GAP + phase < ANIM_W + 12:
        x = i * ANIM_DOT_GAP + phase
        if x > -12:
            for r, a in ((8, 26), (5, 70), (3, 235)):
                d.ellipse([x - r, cy - r, x + r, cy + r], fill=g + (a,))
        i += 1
    name = f"anim_belt_{frame}"
    im.save(os.path.join(out_dir, f"{name}.png"))
    return name


def write_anim_frames(out_dir):
    return [write_anim_frame(out_dir, f) for f in range(ANIM_FRAMES)]


def patch_bg(out_dir):
    """把 bg_ov.jpg 里旧的 CSS 开关（偏心）抹成干净网格背景。"""
    path = os.path.join(out_dir, "bg_ov.jpg")
    im = Image.open(path).convert("RGB")
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = 24, 490, 112, 578
    d.rectangle([x0, y0, x1, y1], fill=BG_FILL)
    for x in range(x0, x1, 10):
        d.line([(x, y0), (x, y1)], fill=BG_GRID)
    for y in range(y0, y1, 10):
        d.line([(x0, y), (x1, y)], fill=BG_GRID)
    im.save(path, quality=95)


def generate_all(out_dir=OUT):
    patch_bg(out_dir)
    write_power_switch(out_dir, "ov_btn_power_n", checked=False)
    write_power_switch(out_dir, "ov_btn_power_c", checked=True)
    write_anim_frames(out_dir)
    return ["ov_btn_power_n", "ov_btn_power_c"] + [f"anim_belt_{i}" for i in range(ANIM_FRAMES)]


if __name__ == "__main__":
    names = generate_all()
    for n in names:
        p = os.path.join(OUT, n + ".png")
        print(f"{n}.png  {os.path.getsize(p)} bytes")
    print("bg_ov.jpg patched")
