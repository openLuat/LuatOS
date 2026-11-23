"""生成两套主题素材对照图（暖夜 dev_* vs 宣纸 p_*）"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE = os.path.join(ROOT, "code")

KEYS = ("light", "incense", "music", "humid", "ambient")
NAMES = {"light": "茶台灯光", "incense": "香薰", "music": "背景音乐",
         "humid": "加湿", "ambient": "氛围"}

CW, CH = 200, 179
GAP, PAD, LABEL = 12, 24, 34
TOP = 52
W = PAD * 2 + CW * 2 + GAP
H = TOP + (CH + LABEL + GAP) * 5 + PAD

im = Image.new("RGB", (W, H), (0x1A, 0x14, 0x0E))
d = ImageDraw.Draw(im)


def font(sz, bold=False):
    for p in ("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc",
              "C:/Windows/Fonts/simhei.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


F20, F18, F16 = font(20, True), font(18, True), font(16)

d.text((PAD, 14), "暖夜 dev_*.jpg", font=F18, fill=(0xF3, 0xE4, 0xC8))
d.text((PAD + CW + GAP, 14), "宣纸 p_*.jpg", font=F18, fill=(0xF3, 0xE4, 0xC8))

for i, k in enumerate(KEYS):
    y = TOP + i * (CH + LABEL + GAP)
    for j, (sub, bgc) in enumerate((("dev_%s.jpg" % k, (0x14, 0x0F, 0x0A)),
                                    ("p_%s.jpg" % k, (0xF4, 0xEC, 0xDD)))):
        x = PAD + j * (CW + GAP)
        d.rounded_rectangle([x - 2, y - 2, x + CW + 1, y + CH + 1], 6, fill=bgc)
        im.paste(Image.open(os.path.join(CODE, sub)).convert("RGB").resize((CW, CH), Image.LANCZOS), (x, y))
        d.text((x, y + CH + 8), "%s  %s" % (NAMES[k], sub), font=F16,
               fill=(0xC8, 0xB4, 0x94) if j == 0 else (0x6B, 0x5C, 0x49))

im.save(os.path.join(ROOT, "docs", "assets_compare.png"))
print("ok %dx%d" % (W, H))
