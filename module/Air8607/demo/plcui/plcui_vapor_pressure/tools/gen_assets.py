"""按 ui_spec.py 的清单烘焙全部素材，并输出 1:1 排版预览。

用法（工程根目录）：
    python tools/gen_assets.py

产物：
    code/bg_*.jpg          五页 1024x600 背景（静态外观全部烘在图里）
    code/*.png             动态件：按钮两态 / 步骤条三态 / 指示灯 / 滑块 / 液位 / 波纹 / 告警胶囊
    design/preview_*.png   排版预览（PIL 合成，仅供人眼核对版面，不是验证）

风格：浅蓝工业风（对齐 plcui_water_supply）。所有文字都烘进图里，
所以字体用系统微软雅黑，字号与 XML 里的 hzfont 字号一一对应。
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CODE = os.path.join(ROOT, "code")
DESIGN = os.path.join(ROOT, "design")
sys.path.insert(0, HERE)

import ui_spec as S  # noqa: E402

FONT_R = "C:/Windows/Fonts/msyh.ttc"
FONT_B = "C:/Windows/Fonts/msyhbd.ttc"
_FONTS = {}


def font(size, bold=True):
    key = (size, bold)
    if key not in _FONTS:
        _FONTS[key] = ImageFont.truetype(FONT_B if bold else FONT_R, size)
    return _FONTS[key]


def rgba(value, alpha=255):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def mix(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def norm_stops(stops):
    """兼容两种写法：["#A","#B"] 均匀分布，或 [(0,"#A"),(1,"#B")] 带位置。"""
    if isinstance(stops[0], str):
        n = len(stops)
        return [((i / (n - 1) if n > 1 else 0.0), c) for i, c in enumerate(stops)]
    return list(stops)


def stop_color(stops, t):
    stops = norm_stops(stops)
    t = min(1.0, max(0.0, t))
    prev = stops[0]
    for pos, col in stops:
        if t <= pos:
            span = pos - prev[0]
            k = 0 if span <= 0 else (t - prev[0]) / span
            return mix(rgba(prev[1]), rgba(col), k)
        prev = (pos, col)
    return rgba(stops[-1][1])


def vgrad(size, stops):
    w, h = size
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=stop_color(stops, y / max(1, h - 1)))
    return img


def mask_round(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1),
                                           radius=radius, fill=255)
    return mask


def fill_box(img, box, radius, stops, border=None, border_w=2):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    layer = vgrad((w, h), stops) if isinstance(stops, list) else Image.new("RGBA", (w, h), rgba(stops))
    mask = mask_round((w, h), radius)
    img.paste(layer, (x0, y0), mask)
    if border:
        ImageDraw.Draw(img).rounded_rectangle(box, radius=radius,
                                              outline=rgba(border), width=border_w)


def hfill_box(img, box, radius, stops, border=None, border_w=2):
    """横向渐变（圆柱体 / 金属条用）。"""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    layer = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(layer)
    for x in range(w):
        d.line([(x, 0), (x, h)], fill=stop_color(stops, x / max(1, w - 1)))
    img.paste(layer, (x0, y0), mask_round((w, h), radius))
    if border:
        ImageDraw.Draw(img).rounded_rectangle(box, radius=radius,
                                              outline=rgba(border), width=border_w)


def shadow(img, box, radius, blur=10, alpha=46, dy=4):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    layer = Image.new("RGBA", (w + blur * 2, h + blur * 2), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((blur, blur, blur + w, blur + h),
                                            radius=radius, fill=(12, 40, 66, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(blur // 2))
    px, py = max(0, x0 - blur), max(0, y0 - blur + dy)
    img.alpha_composite(layer, (px, py))


def txt(draw, xy, s, size, color, bold=True, anchor="la"):
    draw.text(xy, s, font=font(size, bold), fill=rgba(color), anchor=anchor)


# ==================== 版面零件 ====================

def panel(img, box, radius=10, fill=("#FFFFFF", "#F4FAFE"), border=S.BOX_BORDER):
    shadow(img, box, radius)
    fill_box(img, box, radius, [fill[0], fill[1]] if isinstance(fill, tuple) else fill,
             border=border, border_w=2)
    d = ImageDraw.Draw(img)
    d.line([(box[0] + radius, box[1] + 1), (box[2] - radius, box[1] + 1)],
           fill=(255, 255, 255, 210), width=1)


def inner_box(img, box, radius=5, border=S.BOX_BORDER, fill=("#FFFFFF", "#FBFDFF")):
    fill_box(img, box, radius, [fill[0], fill[1]], border=border, border_w=2)


def green_bar(img, box, text, size=18, ink=S.GREEN_INK, radius=6):
    fill_box(img, box, radius,
             [(0, S.GREEN_TOP), (0.55, S.GREEN_BOT), (1, S.GREEN_TOP)],
             border=S.GREEN_LINE, border_w=2)
    d = ImageDraw.Draw(img)
    d.line([(box[0] + 6, box[1] + 2), (box[2] - 6, box[1] + 2)],
           fill=(255, 255, 255, 170), width=1)
    txt(d, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2 + 1), text, size, ink, True, "mm")


def caption(img, xy, text, size=15, color=S.INK3):
    txt(ImageDraw.Draw(img), xy, text, size, color, True)


# ==================== 3D 拟物零件 ====================

STEEL_H = [(0, "#7F94A8"), (0.14, "#C6D6E4"), (0.32, "#F6FBFF"),
           (0.52, "#DCE8F2"), (0.78, "#9FB3C4"), (1, "#6F8497")]
GLASS_H = [(0, "#A6CDE2"), (0.18, "#D9F0FB"), (0.34, "#F4FCFF"),
           (0.52, "#E3F5FD"), (0.76, "#B3D7EA"), (1, "#8FBDD6")]
DARK_H = [(0, "#3C4A57"), (0.2, "#6C7C8B"), (0.4, "#94A5B3"),
          (0.62, "#66757F"), (1, "#39454F")]


def pipe(img, pts, width=12):
    d = ImageDraw.Draw(img)
    d.line(pts, fill=rgba("#7C93A6"), width=width + 4, joint="curve")
    d.line(pts, fill=rgba("#DCE9F3"), width=width, joint="curve")
    d.line([(p[0], p[1] - width // 4) for p in pts], fill=rgba("#FFFFFF", 200),
           width=max(2, width // 4), joint="curve")


def cylinder(img, box, top_h=10, bottom_h=10, hstops=None, label=None, size=15,
             ink=S.INK):
    hstops = hstops or STEEL_H
    x0, y0, x1, y1 = box
    cx = (x0 + x1) / 2
    # 端盖与底盖
    hfill_box(img, (x0, y0 + top_h, x1, y1 - bottom_h), 0, hstops)
    d = ImageDraw.Draw(img)
    d.ellipse((x0, y0, x1, y0 + top_h * 2), fill=rgba("#E9F3FA"),
              outline=rgba("#93AABD"), width=2)
    d.ellipse((x0, y0 + 2, x1, y0 + top_h * 2 - 2), fill=rgba("#F8FCFF"))
    d.ellipse((x0, y1 - bottom_h * 2, x1, y1), fill=rgba("#C4D3DF"))
    d.ellipse((x0 + 2, y1 - bottom_h * 2 + 2, x1 - 2, y1 - 2), fill=rgba("#AEC0CF"))
    d.line([(x0, y0 + top_h), (x0, y1 - bottom_h)], fill=rgba("#8497A8"), width=2)
    d.line([(x1, y0 + top_h), (x1, y1 - bottom_h)], fill=rgba("#6F8497"), width=2)
    if label:
        txt(d, (cx, (y0 + y1) / 2), label, size, ink, True, "mm")


def glass_chamber(img, box, top_h=12, bottom_h=12, label=None, size=15):
    x0, y0, x1, y1 = box
    hfill_box(img, (x0, y0 + top_h, x1, y1 - bottom_h), 0, GLASS_H,
              border="#8FBBD3", border_w=2)
    d = ImageDraw.Draw(img)
    # 玻璃高光
    for fx, fw, alpha in ((0.22, 6, 120), (0.30, 3, 200), (0.70, 4, 90)):
        gx = x0 + (x1 - x0) * fx
        d.rectangle((gx, y0 + top_h + 6, gx + fw, y1 - bottom_h - 6),
                    fill=(255, 255, 255, alpha))
    # 上下金属盖
    fill_box(img, (x0 - 6, y0, x1 + 6, y0 + top_h), 6,
             [(0, "#7F94A8"), (0.3, "#E4EFF8"), (0.62, "#B9CBD9"), (1, "#6F8497")],
             border="#7F94A8", border_w=1)
    d.ellipse((x0 - 6, y0 - 6, x1 + 6, y0 + top_h + 2), fill=rgba("#E9F3FA"),
              outline=rgba("#93AABD"), width=2)
    d.ellipse((x0 - 6, y1 - bottom_h - 2, x1 + 6, y1 + 6), fill=rgba("#BFD0DE"),
              outline=rgba("#8DA3B6"), width=2)
    # 腔底残液
    d.rectangle((x0 + 3, y1 - bottom_h - 12, x1 - 3, y1 - bottom_h - 2),
                fill=(140, 205, 235, 150))
    for bx in (x0 + 10, x1 - 10):
        d.ellipse((bx - 3, y0 + 4, bx + 3, y0 + 10), fill=rgba("#8FA6B8"))
    if label:
        txt(d, ((x0 + x1) / 2, y0 + top_h + 18), label, size, S.INK2, True, "mm")


def motor(img, box, label="步进电机", size=14):
    x0, y0, x1, y1 = box
    fill_box(img, box, 6, [(0, "#5C6B78"), (0.35, "#93A4B2"), (0.7, "#6B7A87"),
                           (1, "#414C57")], border="#2F3942", border_w=2)
    d = ImageDraw.Draw(img)
    for gy in range(y0 + 8, y1 - 4, 7):
        d.line([(x0 + 6, gy), (x1 - 6, gy)], fill=(0, 0, 0, 46), width=2)
    d.line([(x0 + 6, y0 + 3), (x1 - 6, y0 + 3)], fill=(255, 255, 255, 90), width=1)
    txt(d, ((x0 + x1) / 2, (y0 + y1) / 2), label, size, "#FFFFFF", True, "mm")


def valve_body(img, center, label=None, size=15):
    cx, cy = center
    d = ImageDraw.Draw(img)
    d.ellipse((cx - 20, cy - 20, cx + 20, cy + 20), fill=rgba("#D3E0EA"),
              outline=rgba("#7F94A8"), width=2)
    d.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=rgba("#F2F8FD"),
              outline=rgba("#A9BFD1"), width=1)
    d.polygon([(cx - 11, cy - 9), (cx - 11, cy + 9), (cx, cy)], fill=rgba("#7F94A8"))
    d.polygon([(cx + 11, cy - 9), (cx + 11, cy + 9), (cx, cy)], fill=rgba("#7F94A8"))
    d.line([(cx, cy - 20), (cx, cy - 30)], fill=rgba("#7F94A8"), width=4)
    d.rectangle((cx - 10, cy - 34, cx + 10, cy - 28), fill=rgba("#63B8EE"),
                outline=rgba("#155691"))
    if label:
        txt(d, (cx, cy - 46), label, size, S.INK2, True, "mm")


# ==================== 页面背景 ====================

def sky(img):
    img.alpha_composite(vgrad((S.W, S.H), [(0, S.SKY_TOP), (0.45, "#A9DEF6"),
                                           (0.72, S.SKY_BOT), (1, "#E4F2FA")]))
    d = ImageDraw.Draw(img)
    # 左上柔光
    glow = Image.new("RGBA", (S.W, S.H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-260, -320, 620, 320), fill=(255, 255, 255, 70))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))
    # 地面
    d.rectangle((0, 404, S.W, S.H), fill=rgba("#E1ECF4", 190))
    d.line([(0, 404), (S.W, 404)], fill=rgba("#BCD5E6"), width=2)
    for i in range(-6, 20):
        d.line([(i * 80, 404), (i * 80 - 120, S.H)], fill=(176, 203, 222, 46), width=1)
    for y in range(424, S.H, 28):
        d.line([(0, y), (S.W, y)], fill=(176, 203, 222, 34), width=1)
    return img


def chrome(img, title, subtitle):
    """页名用 label（hzfont）画，这里只烘副标题与底板。"""
    d = ImageDraw.Draw(img)
    txt(d, (24, 54), subtitle, 17, S.INK3, True, "la")
    # 时钟底板
    fill_box(img, (752, 6, 1010, 64), 8, [("#FFFFFF"), ("#E7F2FA")],
             border=S.BOX_BORDER, border_w=2)
    d.line([(760, 40), (1002, 40)], fill=(200, 220, 234, 180), width=1)
    # 底部操作带
    band = Image.new("RGBA", (S.W, 84), (255, 255, 255, 0))
    bd = ImageDraw.Draw(band)
    bd.rectangle((0, 4, S.W, 84), fill=(255, 255, 255, 216))
    bd.line([(0, 4), (S.W, 4)], fill=(150, 190, 215, 220), width=2)
    img.alpha_composite(band, (0, S.BTN_BAND_Y - 4))
    return img


def plant_art(img):
    """工艺流程 3D 拟物图（画进 bg_run 的面板区域）。

    机械布局（自上而下）：
    1、步进电机在腔体正上方，活塞杆从电机底部穿过腔体顶盖接到软塞；
    2、软塞横向填满腔体内壁，上拉时在腔体底部形成负压；
    3、两个电磁阀都装在腔体底部（横向也在腔体范围内）：
       阀1 接储液罐，阀1 开 + 电机上拉 -> 液体从腔底被吸进腔体；
       阀2 接排液管，清洗与复位时打开放空。
    """
    ox, oy = S.PLANT_X, S.PLANT_Y
    # 面板与内部浅色衬底
    panel(img, (ox, oy, ox + S.PLANT_W, oy + S.PLANT_H), radius=10,
          fill=("#FFFFFF", "#EAF4FB"))
    d = ImageDraw.Draw(img)
    for gx in range(ox + 24, ox + S.PLANT_W - 8, 24):
        d.line([(gx, oy + 8), (gx, oy + S.PLANT_H - 8)], fill=(206, 226, 240, 60))
    for gy in range(oy + 24, oy + S.PLANT_H - 8, 24):
        d.line([(ox + 8, gy), (ox + S.PLANT_W - 8, gy)], fill=(206, 226, 240, 60))

    # 储液罐
    cylinder(img, (46, 292, 156, 400), 12, 10, label="储液罐", size=14)
    d.rectangle((50, 352, 152, 392), fill=(120, 200, 235, 120))

    # 管路：罐底 -> 阀1 底；腔底 -> 阀1 顶；腔底 -> 阀2 顶；阀2 -> 排液；清洗气 -> 腔体上部
    v1x, v2x = S.V1_XY[0], S.V2_XY[0]
    pipe(img, [(101, 396), (101, 412), (v1x, 412)], 10)
    pipe(img, [(v1x, S.CH_Y1), (v1x, S.V1_XY[1] - 20)], 10)
    pipe(img, [(v2x, S.CH_Y1), (v2x, S.V2_XY[1] - 20)], 10)
    pipe(img, [(v2x, S.V2_XY[1] + 18), (v2x, 418), (570, 418), (570, 424)], 10)
    pipe(img, [(590, oy - 2), (590, 140), (452, 140), (452, 168)], 9)

    # 密闭腔体（内壁就是 178mm 量筒）
    glass_chamber(img, (S.CH_X0, S.CH_Y0, S.CH_X1, S.CH_Y1), label=None)
    txt(d, (S.CH_LEFT + 12, S.CH_TOP + 16), "密闭腔体", 14, S.INK2, True)
    # 顶盖上的活塞杆导向座
    d.rectangle((S.ROD_X - 7, S.CH_Y0 - 2, S.ROD_X + S.ROD_W + 7, S.CH_Y0 + 12),
                fill=rgba("#A9BFD1"), outline=rgba("#6F8497"))

    # 步进电机（腔体正上方）
    motor(img, (266, 122, 366, 154))

    # 两个电磁阀（腔体底部）；阀位指示灯运行时盖在同一位置
    valve_body(img, S.V1_XY, None)
    valve_body(img, S.V2_XY, None)
    txt(d, (202, 372), "阀1", 14, S.INK2, True)
    txt(d, (404, 372), "阀2", 14, S.INK2, True)
    txt(d, (496, 122), "清洗气", 14, S.INK3, True)
    txt(d, (470, 396), "排液", 14, S.INK3, True)
    caption(img, (30, 128), "工艺流程示意", 13, "#8FA6B8")
    # 左侧读数卡片：腔体实时压力与温度（运行时数值 label 叠在这张白底上）
    inner_box(img, (22, 146, 172, 282), 8)
    caption(img, (30, 152), "腔体压力", 14, S.INK3)
    caption(img, (30, 216), "腔体温度", 14, S.INK3)
    return img


def bg_run():
    img = Image.new("RGBA", (S.W, S.H))
    sky(img)
    chrome(img, "蒸气压测定仪", S.SUBTITLE["bg_run"])
    plant_art(img)

    # 右列设备操作三块面板（标题条高度与 ui_spec 里按钮的起点对齐）
    for box, name, bar_h in (((612, 120, 1008, 262), "电磁阀", 30),
                             ((612, 268, 1008, 424), "步进电机", 30),
                             ((612, 430, 1008, 512), "加热", 28)):
        panel(img, box, radius=8)
        green_bar(img, (box[0], box[1], box[2], box[1] + bar_h), name,
                  16 if bar_h < 30 else 18)

    # 实时状态面板（六个动态 label 叠在面板里）
    panel(img, (16, 428, 596, 512), radius=8)
    green_bar(img, (16, 428, 596, 452), "实时状态", 16)
    return img


def bg_man():
    img = Image.new("RGBA", (S.W, S.H))
    sky(img)
    chrome(img, "环节手动", S.SUBTITLE["bg_man"])
    for i in range(6):
        x = 16 + (i % 3) * 332
        y = 120 + (i // 3) * 148
        panel(img, (x, y, x + 328, y + 140))
        green_bar(img, (x, y, x + 328, y + 30), S.STAGE_TITLE[i], 17)
        ImageDraw.Draw(img).line([(x + 14, y + 80), (x + 314, y + 80)],
                                 fill=(206, 226, 240, 170), width=1)
    panel(img, (16, 420, 1008, 512), radius=8)
    green_bar(img, (16, 420, 1008, 446), "实时状态", 16)
    return img


def bg_test():
    img = Image.new("RGBA", (S.W, S.H))
    sky(img)
    chrome(img, "膨胀参数", S.SUBTITLE["bg_test"])
    panel(img, (16, 368, 616, 508))
    caption(img, (30, 372), "三次膨胀压力拟合 (kPa)", 16, S.INK3)
    inner_box(img, (26, 392, 606, 500), 5)

    boxes = (((612, 120, 1008, 238), "拟合截距（实测蒸气压）"),
             ((612, 246, 1008, 354), "拟合斜率（空气分压）"),
             ((612, 362, 1008, 460), "标准温度值 (37.8 ℃)"))
    for box, name in boxes:
        panel(img, box)
        green_bar(img, (box[0], box[1], box[2], box[1] + 30), name, 17)
    inner_box(img, (620, 156, 1000, 232), 6)
    inner_box(img, (620, 282, 1000, 348), 6)
    inner_box(img, (620, 398, 1000, 454), 6)
    panel(img, (612, 468, 1008, 512), radius=8)
    caption(img, (632, 478), "重复性", 15, S.INK3)
    return img


# ==================== 动态件 ====================

BTN_PALETTE = {
    "green": ("#BCE76A", "#7FBE2C", "#4F8A16", "#FFFFFF", "#2F5C08"),
    "blue": ("#63B8EE", "#1F6DB4", "#134F85", "#FFFFFF", "#0B3A63"),
    "red": ("#F0716C", "#C42F2B", "#8C130F", "#FFFFFF", "#5C0B08"),
    "gray": ("#FBFDFF", "#CFDCE7", "#94AEC4", "#274156", "#FFFFFF"),
}


def gen_button(wid, size, text, style):
    w, h = size
    top, bot, border, ink, shadow_col = BTN_PALETTE[style]
    radius = max(8, min(14, h // 4))

    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fill_box(img, (1, 1, w - 1, h - 1), radius, [top, bot, bot], border=border, border_w=2)
    d = ImageDraw.Draw(img)
    # 上半高光（凸起感）
    gloss = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.rounded_rectangle((3, 2, w - 4, h // 2), radius=radius - 2,
                         fill=(255, 255, 255, 96 if style != "gray" else 210))
    gloss = gloss.filter(ImageFilter.GaussianBlur(2))
    img.alpha_composite(gloss)
    d.line([(radius, h - 2), (w - radius, h - 2)], fill=(0, 0, 0, 60), width=2)

    fs = 24 if h >= 56 else 21
    txt(d, (w / 2, h / 2 + 1), text, fs, ink, True, "mm")
    if style != "gray":
        txt(d, (w / 2, h / 2 + 2), text, fs, shadow_col, True, "mm")
        txt(d, (w / 2, h / 2), text, fs, ink, True, "mm")

    pressed = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fill_box(pressed, (1, 1, w - 1, h - 1), radius, [bot, top, bot], border=border,
             border_w=2)
    dp = ImageDraw.Draw(pressed)
    dp.rounded_rectangle((3, 2, w - 4, h // 2), radius=radius - 2, fill=(0, 0, 0, 40))
    txt(dp, (w / 2, h / 2 + 2), text, fs, ink, True, "mm")
    return img, pressed


CHIP_STATE = {
    "g": (["#E9F1F8", "#C3D3E0"], "#94AEC4", "#41637F"),
    "a": (["#6FC0F2", "#1F6DB4"], "#134F85", "#FFFFFF"),
    "d": (["#C6EC7C", "#7FBE2C"], "#4F8A16", "#FFFFFF"),
}


def gen_chip(idx, state, size):
    w, h = size
    grad, border, ink = CHIP_STATE[state]
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fill_box(img, (0, 0, w - 1, h - 1), 6, grad, border=border, border_w=2)
    d = ImageDraw.Draw(img)
    d.line([(8, 2), (w - 9, 2)], fill=(255, 255, 255, 170), width=1)
    if state == "a":
        d.rounded_rectangle((4, 6, 8, h - 7), radius=2, fill=rgba("#FFFFFF"))
    if state == "d":
        d.ellipse((w - 22, h / 2 - 5, w - 12, h / 2 + 5), fill=rgba("#FFFFFF", 230))
    txt(d, (w / 2, h / 2 + 1), S.CHIP_TEXT[idx], 17, ink, True, "mm")
    return img


LAMP_COLOR = {
    "idle": ("#AFC2D2", "#DCE7F0"),
    "run": ("#3FBF57", "#BDEBC6"),
    "done": ("#2F86D6", "#BBDDF6"),
    "alarm": ("#E2423C", "#F8C9C7"),
    "open": ("#3FBF57", "#C9F0D2"),
    "closed": ("#9FB0BF", "#E2EAF1"),
}


def gen_lamp(size, kind):
    w, h = size
    core, halo = LAMP_COLOR[kind]
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((1, 1, w - 2, h - 2), fill=rgba("#F2F8FD"), outline=rgba("#93AABD"),
              width=2)
    if kind in ("run", "alarm", "open", "done"):
        glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse((w * 0.18, h * 0.18, w * 0.82, h * 0.82), fill=rgba(halo, 220))
        glow = glow.filter(ImageFilter.GaussianBlur(3))
        img.alpha_composite(glow)
    d.ellipse((w * 0.22, h * 0.22, w * 0.78, h * 0.78), fill=rgba(core),
              outline=rgba("#5E7C99"), width=1)
    d.ellipse((w * 0.30, h * 0.26, w * 0.48, h * 0.42), fill=(255, 255, 255, 210))
    return img


def gen_car(size):
    """活塞软塞：横向填满腔体内壁，上下是贴壁密封唇，正中是活塞杆孔。"""
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fill_box(img, (0, 0, w - 1, h - 1), 6,
             ["#5E7488", "#C9D8E5", "#EFF6FC", "#C9D8E5", "#5E7488"],
             border="#4E6478", border_w=2)
    d = ImageDraw.Draw(img)
    # 上下密封唇（贴玻璃内壁的深色胶条）
    d.rounded_rectangle((2, 2, w - 3, 6), radius=2, fill=rgba("#3E5265"))
    d.rounded_rectangle((2, h - 7, w - 3, h - 3), radius=2, fill=rgba("#3E5265"))
    d.line([(5, 8), (w - 6, 8)], fill=(255, 255, 255, 150), width=1)
    # 活塞杆孔（杆从这里穿进来，杆的下端被软塞本体盖住）
    cx = w // 2
    d.ellipse((cx - 11, 3, cx + 11, h - 4), fill=rgba("#7F94A8"), outline=rgba("#3E5265"),
              width=2)
    d.ellipse((cx - 6, 7, cx + 6, h - 8), fill=rgba("#44515D"))
    return img


def gen_rod(index, size):
    """活塞杆：金属圆杆，长度随软塞档位变（顶部接电机，底部插进软塞）。

    为什么杆也做 11 张：杆必须始终从电机连到软塞、又不能越过软塞露在下面，
    固定长度的杆做不到（软塞越往上，露在下面的杆越长），只能按档变长。
    单张 12x168 RGBA 只有 8 KiB，11 张总量可以忽略。
    """
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hfill_box(img, (0, 0, w - 1, h - 1), 0,
              ["#5E7488", "#C6D6E4", "#F6FBFF", "#DCE8F2", "#8DA3B6"],
              border=None)
    d = ImageDraw.Draw(img)
    d.line([(3, 0), (3, h - 1)], fill=(255, 255, 255, 200), width=2)
    d.line([(w - 4, 0), (w - 4, h - 1)], fill=(56, 72, 88, 170), width=1)
    return img


def gen_liq_level(index, size):
    """腔体液位素材：整块 248x172 画布，液面以下填液体，以上全透明。

    为什么不做一张图 + set_size：`image:set_size` 是 PLCUI 1.0.2 才有的接口，
    目标固件 1.0.1 没有；1.0.1 只认 `src` / `hidden` 与 `set_src`，
    所以液位按档烘 11 张，运行时按级切图。

    档位按活塞行程分：第 i 张代表液面 i*11 mm，像素高度按腔高 178mm 换算，
    最高一张（110mm）只到画布的 62%，与滑块下沿逐档对齐。
    """
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    if index <= 0:
        return img
    mm = index * S.LIQ_STEP
    hh = int(round(h * mm / float(S.LIQ_MM)))
    if hh < 3:
        hh = 3
    y0 = h - hh
    fill_box(img, (0, y0, w - 1, h - 1), 3, ["#8ED8F5", "#4FB4E4", "#2E8FC8"],
             border="#2A7FAE", border_w=2)
    d = ImageDraw.Draw(img)
    # 液面做成小波纹（连续的半圆拱），静态图里也能读出"这是液面"
    for wx in range(4, w - 12, 14):
        d.arc((wx, y0 - 1, wx + 14, y0 + 7), 180, 360, fill=(255, 255, 255, 175), width=2)
    d.rectangle((3, y0 + 6, w - 4, y0 + 9), fill=(255, 255, 255, 120))
    for gx in range(10, w - 8, 26):
        d.line([(gx, y0 + 14), (gx, h - 6)], fill=(255, 255, 255, 36), width=2)
    return img


def gen_alarm(size):
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fill_box(img, (1, 1, w - 2, h - 2), h // 2 - 1, ["#F5837E", "#C42F2B", "#A31A16"],
             border="#8C130F", border_w=2)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((6, 4, w - 8, h // 2), radius=h // 3, fill=(255, 255, 255, 70))
    txt(d, (w / 2, h / 2 + 1), "急停已触发", 20, "#FFFFFF", True, "mm")
    d.polygon([(24, h / 2 - 8), (38, h / 2), (24, h / 2 + 8)], fill=rgba("#FFFFFF"))
    return img


# ==================== 预览 ====================

def render_preview(page, path):
    img = Image.new("RGBA", (S.W, S.H), rgba(page["background"]))
    d = ImageDraw.Draw(img)
    for w in page["widgets"]:
        x, y, ww, hh = w["x"], w["y"], w["w"], w["h"]
        tag = w["tag"]
        if tag == "image":
            if w.get("hidden") == "true":
                continue
            f = os.path.join(CODE, S.filename(w["src"]))
            if os.path.exists(f):
                img.alpha_composite(Image.open(f).convert("RGBA").resize((ww, hh)), (x, y))
        elif tag == "label":
            if w.get("hidden") == "true":
                continue
            size = w.get("font_size", 16)
            fnt = font(size)

            def _pos():
                return x, y + (hh - size) // 2 - 1
            if w.get("align") == "right":
                d.text((x + ww, _pos()[1]), w["text"], font=fnt, fill=rgba(w["color"]),
                       anchor="ra")
            elif w.get("align") == "center":
                d.text((x + ww // 2, _pos()[1]), w["text"], font=fnt, fill=rgba(w["color"]),
                       anchor="ma")
            else:
                d.text(_pos(), w["text"], font=fnt, fill=rgba(w["color"]))
        elif tag == "chart":
            ImageDraw.Draw(img).rectangle((x, y, x + ww, y + hh),
                                          outline=rgba("#B7D6E8"))
            for i in range(1, w.get("hdiv", 4)):
                yy = y + hh * i // w.get("hdiv", 4)
                ImageDraw.Draw(img).line([(x, yy), (x + ww, yy)], fill=rgba("#DCEBF5"))
            txt(ImageDraw.Draw(img), (x + 8, y + 4), "chart " + w["id"], 13, "#8FA6B8")
        elif tag == "table":
            rows, cols = w["rows"], w["columns"]
            rh = w.get("row-height", hh // rows)
            widths = [int(v) for v in w["col-widths"].split(",")]
            ImageDraw.Draw(img).rectangle((x, y, x + ww, y + rh), fill=rgba("#A8D84B"))
            ImageDraw.Draw(img).rectangle((x, y, x + ww, y + hh), outline=rgba("#8CC2E2"),
                                          width=2)
            for r in range(rows + 1):
                ImageDraw.Draw(img).line([(x, y + r * rh), (x + ww, y + r * rh)],
                                         fill=rgba("#CFE3F0"))
            for (r, c, text) in w.get("cells", []):
                cx = x + sum(widths[:c - 1])
                ImageDraw.Draw(img).line([(cx, y), (cx, y + hh)], fill=rgba("#CFE3F0"))
                txt(ImageDraw.Draw(img), (cx + widths[c - 1] / 2, y + (r - 0.5) * rh),
                    text, 19, S.INK, True, "mm")
    img.convert("RGB").save(path)


def render_state_preview(page, path):
    """运行 + 急停态的排版预览：给静态图看不出状态的件填上运行值。"""
    patch_text = {"pv_pv": "72.5", "pv_tv": "37.4",
                  "ds_v1": "阀1:开", "ds_v2": "阀2:关",
                  "ds_step": "步长 10", "hs_temp": "设定 37.5℃",
                  "rs_1": "环节 5 三次膨胀", "rs_2": "阀1:关 阀2:开",
                  "rs_3": "步进 33.0 mm", "rs_4": "液位 19%",
                  "rs_5": "加热 开", "rs_6": "蒸气压 46.2 kPa"}
    patch_src = {"tb_lamp": "im_lamp_alarm", "pv_v1": "im_valve_o",
                 "pv_v2": "im_valve_c", "stp1": "st1_d", "stp2": "st2_d",
                 "stp3": "st3_d", "stp4": "st4_d", "stp5": "st5_a",
                 "stp6": "st6_g"}
    widgets = []
    for w in page["widgets"]:
        w = dict(w)
        if w["id"] == "tb_alarm":
            w.pop("hidden", None)
        elif w["id"] == "tb_badge":
            w["hidden"] = "true"
        elif w["id"] == "pv_liq":
            # 液面与滑块同档：液面 33mm（第 3 档），预览里正好验证"液面顶边贴活塞下沿"
            w.pop("hidden", None)
            w["src"] = "im_liq03"
        elif w["id"].startswith("pv_rod"):
            # 活塞杆与软塞同档，预览里一起摆到第 3 档
            w["hidden"] = "false" if w["id"] == "pv_rod3" else "true"
        elif w["id"].startswith("pv_car"):
            # 预览里把软塞摆到行程 1/3 处，只显示对应档位那一件
            w["hidden"] = "false" if w["id"] == "pv_car3" else "true"
        elif w["id"] in patch_text:
            w["text"] = patch_text[w["id"]]
        elif w["id"] in patch_src:
            w["src"] = patch_src[w["id"]]
        widgets.append(w)
    tmp = dict(page)
    tmp["widgets"] = widgets
    render_preview(tmp, path)


def main():
    os.makedirs(CODE, exist_ok=True)
    os.makedirs(DESIGN, exist_ok=True)
    for name in os.listdir(CODE):
        if name.endswith(".png") or name.endswith(".jpg"):
            os.remove(os.path.join(CODE, name))

    pages = {"bg_run": bg_run, "bg_man": bg_man, "bg_test": bg_test}
    count = 0
    for rid, size, _note in S.ASSETS:
        path = os.path.join(CODE, S.filename(rid))
        if rid in pages:
            pages[rid]().convert("RGB").save(path, quality=90, subsampling=1)
        elif rid.endswith("_p"):
            continue
        elif rid in S.BTN_TEXT:
            normal, pressed = gen_button(rid, size, S.BTN_TEXT[rid], S.BTN_STYLE[rid])
            normal.save(path)
            pressed.save(os.path.join(CODE, rid + "_p.png"))
            count += 1
        elif rid.startswith("st") and rid[2:3].isdigit():
            gen_chip(int(rid[2]) - 1, rid[4], size).save(path)
        elif rid.startswith("im_lamp_"):
            gen_lamp(size, rid[len("im_lamp_"):]).save(path)
        elif rid.startswith("im_liq"):
            gen_liq_level(int(rid[len("im_liq"):]), size).save(path)
        elif rid.startswith("im_rod"):
            gen_rod(int(rid[len("im_rod"):]), size).save(path)
        elif rid == "im_valve_o":
            gen_lamp(size, "open").save(path)
        elif rid == "im_valve_c":
            gen_lamp(size, "closed").save(path)
        elif rid == "im_car":
            gen_car(size).save(path)
        elif rid == "im_alarm":
            gen_alarm(size).save(path)
        else:
            raise SystemExit("未实现的素材：%s" % rid)
        count += 1

    for page in S.PAGES:
        render_preview(page, os.path.join(DESIGN, "preview_%s.png" % page["id"]))
    render_state_preview(S.PAGES[0], os.path.join(DESIGN, "preview_run_state.png"))
    print("素材 %d 个已写入 %s" % (count, CODE))
    print("排版预览已写入 %s" % DESIGN)


if __name__ == "__main__":
    main()
