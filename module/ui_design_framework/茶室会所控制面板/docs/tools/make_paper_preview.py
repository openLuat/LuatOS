"""宣纸主题整屏预览：真实素材按 Lua 坐标合成（1024x600）"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE = os.path.join(ROOT, "code")
W, H = 1024, 600
SX, SY = 88, 58

PAPER = (0xEF, 0xE6, 0xD6)
CARD_LINE = (0xC9, 0xB9, 0x9B)
CARD_IN = (0xFF, 0xFD, 0xF7)
GOLD = (0x8A, 0x61, 0x34)
GOLD_DIM = (0x6E, 0x4E, 0x28)
TEXT = (0x2C, 0x24, 0x1B)
DIM = (0x6B, 0x5C, 0x49)
TRACK = (0xD8, 0xCC, 0xB8)
CHIP = (0xF0, 0xE6, 0xD2)
RAIL = (0xFB, 0xF6, 0xEC)
BTN = (0xF3, 0xE9, 0xD6)
VEIL = (0xFA, 0xF6, 0xEC)

im = Image.open(os.path.join(CODE, "bg_paper.jpg")).convert("RGB").resize((W, H), Image.LANCZOS)
d = ImageDraw.Draw(im, "RGBA")


def font(sz):
    for p in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


F27, F16, F18, F20 = font(27), font(16), font(18), font(20)


def round_card(x, y, w, h, r, img_path):
    """卡：1px 边线 + 圆角图片 + 柔纱（参数与 Lua 一致）"""
    d.rounded_rectangle([x, y, x + w - 1, y + h - 1], r, fill=CARD_LINE)
    inner = Image.open(img_path).convert("RGB").resize((w - 2, h - 2), Image.LANCZOS)
    mask = Image.new("L", (w - 2, h - 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 3, h - 3], r - 1, fill=255)
    im.paste(inner, (x + 1, y + 1), mask)


def slip(x, y, w, h, r, top):
    """实心纸签：顶部直角接图片，底部两角跟随卡片圆角"""
    mw, mh = w, h
    mask = Image.new("L", (mw, mh), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, mw - 1, mh - 1], r, fill=255)
    md.rectangle([0, 0, mw - 1, r], fill=255)
    im.paste(Image.new("RGB", (mw, mh), CARD_IN), (x, y), mask)
    d.line([x, y, x + w - 1, y], fill=CARD_LINE, width=1)


def text_c(cx, y, s, f, col):
    bb = d.textbbox((0, 0), s, font=f)
    d.text((cx - (bb[2] - bb[0]) // 2, y), s, font=f, fill=col)


def text_l(x, y, s, f, col):
    d.text((x, y), s, font=f, fill=col)


def capsule(x, y, w, h, label, f, dot=True, tw=None):
    d.rounded_rectangle([x, y, x + w - 1, y + h - 1], h // 2, fill=CHIP)
    cy = y + h // 2
    tx = x + 12
    if dot:
        d.ellipse([x + 9, cy - 3, x + 15, cy + 3], fill=(0x4E, 0x6B, 0x57))
        tx = x + 22
    text_l(tx, cy - 9, label, f, DIM)


# ---- 左轴 ----
d.rectangle([0, 0, 87, H], fill=RAIL)
for k, label in enumerate(("灯", "香", "乐", "湿")):
    y = SY + 18 + k * 74
    if k == 0:
        d.rounded_rectangle([12, y, 75, y + 58], 10, fill=BTN)
        d.rectangle([12, y + 22, 16, y + 36], fill=GOLD)
    text_l(34, y + 18, label, F18, GOLD_DIM if k == 0 else DIM)

# ---- 顶栏 ----
text_l(110, 14, "茶室 · 云栖", F20, TEXT)
text_l(110, 40, "霜降 · 戌时 · 客至", F16, DIM)
d.rounded_rectangle([760, 14, 902, 46], 8, outline=CARD_LINE, width=1)
text_c(831, 20, "宣纸 · 切换", F16, GOLD)
text_l(922, 12, "19:42", F20, TEXT)
text_l(930, 40, "24.6℃", F16, DIM)

# ---- 大卡 ----
BX, BY, BW, BH = SX + 16, SY + 18, 420, 376
round_card(BX, BY, BW, BH, 12, os.path.join(CODE, "p_light.jpg"))
slip(BX + 1, BY + 1 + 262, BW - 2, 112, 11, BY + 1 + 262)
CX = BX + 1 + 209
text_c(CX, BY + 1 + 272, "茶台灯光", F27, TEXT)
text_c(CX, BY + 1 + 306, "TEA TABLE LIGHT", F16, GOLD_DIM)
capsule(BX + 1 + 27, BY + 1 + 16, 66, 24, "主位", F16, dot=False)
capsule(BX + 1 + 313, BY + 1 + 16, 84, 24, "7 档", F16)
for i in range(10):
    x = BX + 1 + 15 + i * 39
    d.rounded_rectangle([x, BY + 1 + 344, x + 36, BY + 1 + 348], 2,
                        fill=GOLD if i < 7 else TRACK)

# ---- 4 张小卡 ----
INFO = (("incense", "香薰", "INCENSE"), ("music", "背景音乐", "TEA AMBIENCE"),
        ("humid", "加湿", "HUMIDITY"), ("ambient", "氛围", "ATMOSPHERE"))
for i, (key, name, en) in enumerate(INFO):
    x = SX + (452 if i % 2 == 0 else 684)
    y = SY + (18 if i < 2 else 214)
    round_card(x, y, 216, 180, 10, os.path.join(CODE, "p_%s.jpg" % key))
    slip(x + 1, y + 1 + 112, 214, 66, 9, y + 1 + 112)
    text_l(x + 1 + 16, y + 1 + 116, name, F20, TEXT)
    text_l(x + 1 + 16, y + 1 + 142, en, F16, GOLD_DIM)
    capsule(x + 1 + 127, y + 1 + 12, 72, 22, "5 档", F16)

# ---- 场景条 ----
for i, (name, sub) in enumerate((("待客", "灯 7 · 香 5"), ("独饮", "灯 4 · 乐 3"),
                                 ("清理", "全关"), ("夜读", "灯 3 · 乐 2"))):
    bx = 104 + i * 218
    d.rounded_rectangle([bx, 470, bx + 217, 546], 10, fill=BTN if i else (0xEA, 0xDC, 0xC2))
    if i == 0:
        d.rectangle([bx + 14, 486, bx + 17, 522], fill=GOLD)
    text_l(bx + 26, 484, name, F20, TEXT)
    text_l(bx + 26, 514, sub, F16, DIM)

im.save(os.path.join(ROOT, "docs", "paper_preview.png"))
print("ok")
