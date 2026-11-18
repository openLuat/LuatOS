# -*- coding: utf-8 -*-
"""电动车仪表盘 布局验算
把 app_config.LAYOUT 与各模块里写死的坐标抄一份，逐条验算：
  x >= 0, y >= 0, x+w <= 父内容宽, y+h <= 父内容高
另外查两件事（都是真机踩过的坑）：
  · 同一层卡片矩形两两不得相交（右列 cardBatt 与 cardIndR 曾完全重叠）
  · 卡片顶部高光线 w = cw-28，窄控件不该画（no_glint）
"""
import math

W, H = 1024, 600
bads = []
checks = 0
cards_rect = []          # (tag, x, y, w, h) 用于重叠检测


def L(v, minimum=16):
    """label 高度兜底：max(声明高, 字号+3)"""
    return max(16, v)


def check(parent, pw, ph, tag, x, y, w, h):
    global checks
    checks += 1
    if x < 0 or y < 0 or x + w > pw or y + h > ph:
        bads.append((parent, tag, x, y, w, h, x + w, y + h, pw, ph))


def label(parent, pw, ph, tag, x, y, w, h, size):
    hh = max(h, L(size) + 3)
    check(parent, pw, ph, tag + "[label]", x, y, w, hh)


def shape(parent, pw, ph, tag, x, y, w, h):
    check(parent, pw, ph, tag + "[shape]", x, y, w, h)


def card(parent, pw, ph, tag, x, y, w, h, bw=1, glint=True):
    check(parent, pw, ph, tag + "[card]", x, y, w, h)
    cw, ch = w - 2 * bw, h - 2 * bw
    if parent == "page":
        cards_rect.append((tag, x, y, w, h))
    if glint and cw - 28 >= 8:
        check(tag, cw, ch, "glint", 14, 0, cw - 28, 1)
    return (cw, ch)


def group(parent, pw, ph, tag, x, y, w, h):
    check(parent, pw, ph, tag + "[group]", x, y, w, h)
    return (w, h)


# ---------------- 页面 ----------------
PAGE = ("page", W, H)

# ---- 背景层：色斑 + 底部氛围光（全屏 shape，椭圆出血由 shape 自身裁剪）----
shape(*PAGE, "backdrop.orb", 0, 0, W, H)
shape(*PAGE, "backdrop.amb", 0, 0, W, H)

# ---- 顶栏 ----（GPS/4G/BT 那行已随设计稿删除）
shape(*PAGE, "topbar.dot", 24, 20, 10, 10)
label(*PAGE, "topbar.live", 42, 14, 64, 22, 16)
cw, ch = card(*PAGE, "topbar.chip", 474, 14, 76, 26, glint=False)
label("topbar.chip", cw, ch, "chip.lb", 0, 1, 74, 22, 16)
label(*PAGE, "topbar.date", 660, 16, 136, 22, 16)
label(*PAGE, "topbar.clock", 832, 10, 108, 30, 22)
cw, ch = card(*PAGE, "topbar.theme", 952, 10, 44, 44, glint=False)
shape("topbar.theme", cw, ch, "theme.icon", 9, 9, 24, 24)

# ---- 表盘（雾光层 408 @308,86；动态层 412 @306,84；轴心 44 @490,268）----
# 静态层只剩轨道 + 刻度：表盘面 face_r 已删除（表盘透明）
SB, DB, HS = 408, 412, 44
CX, CY = 512, 290
shape(*PAGE, "dial.glow", CX - SB // 2, CY - SB // 2, SB, SB)
shape(*PAGE, "dial.static", CX - SB // 2, CY - SB // 2, SB, SB)
shape(*PAGE, "dial.progress", CX - DB // 2, CY - DB // 2, DB, DB)
shape(*PAGE, "dial.needle", CX - DB // 2, CY - DB // 2, DB, DB)
shape(*PAGE, "dial.hub", CX - HS // 2, CY - HS // 2, HS, HS)

# 刻度数字：r=148，9 个 40x22 的 label
for i in range(0, 33, 4):
    t = i / 32.0
    deg = 135 + 270 * t
    rad = deg * math.pi / 180
    nx = math.floor(CX + 148 * math.cos(rad) + 0.5)
    ny = math.floor(CY + 148 * math.sin(rad) + 0.5)
    label(*PAGE, "dial.num%d" % i, nx - 20, ny - 11, 40, 22, 18)

# 表盘内文字
label(*PAGE, "dial.brand", CX - 150, 176, 300, 22, 16)
label(*PAGE, "dial.speed", CX - 150, 306, 300, 68, 64)
label(*PAGE, "dial.unit", CX - 150, 378, 300, 22, 18)
label(*PAGE, "dial.odo", CX - 150, 406, 300, 19, 16)

# ---- 指示灯卡（230x150 内容区）----
for side, x0 in (("L", 24), ("R", 768)):
    cw, ch = card(*PAGE, "inds.card" + side, x0, 64, 232, 152)
    for row, y in zip("abc", (2, 53, 104)):
        rw, rh = group("inds.card" + side, cw, ch, "row" + row, 14, y, 202, 44)
        tag = "inds." + side + row
        shape("inds.row" + row, rw, rh, tag + ".icon", 0, 7, 30, 30)
        label("inds.row" + row, rw, rh, tag + ".txtbadge", 0, 10, 30, 24, 16)
        label("inds.row" + row, rw, rh, tag + ".name", 38, 11, 160, 22, 16)

# ---- 模式卡 ----
cw, ch = card(*PAGE, "mode.card", 24, 228, 232, 152)
label("mode.card", cw, ch, "mode.title", 14, 10, 202, 19, 16)
for i, y in enumerate((34, 74, 114), 1):
    pw, ph = card("mode.card", cw, ch, "mode.pill%d" % i, 14, y, 202, 34, glint=False)
    label("mode.pill%d" % i, pw, ph, "pill%d.lb" % i, 0, 5, 200, 22, 16)

# ---- 骑行卡（92 高，均速已挪到底带）----
cw, ch = card(*PAGE, "ride.card", 24, 392, 232, 92)
label("ride.card", cw, ch, "ride.title", 14, 12, 202, 19, 16)
label("ride.card", cw, ch, "ride.val", 14, 40, 202, 40, 34)

# ---- 电量卡（右列 228..484；内容区 230x254）----
# 功率卡已删，空出的 228..380 并入电量卡；段条 / 量程也删了（shape 要重建）
cw, ch = card(*PAGE, "batt.card", 768, 228, 232, 256)
label("batt.card", cw, ch, "batt.title", 14, 44, 202, 19, 16)
label("batt.card", cw, ch, "batt.val", 14, 76, 104, 67, 64)
label("batt.card", cw, ch, "batt.pct", 100, 114, 30, 22, 18)
check("batt.card", cw, ch, "batt.rule", 14, 172, 202, 1)
label("batt.card", cw, ch, "batt.sub", 14, 188, 202, 22, 16)
# 幽灵水印：电池身 W.outline(140,72,72x96) + 凸头 (162,62,28x12)
# 电池芯 4 格：60x18，间隙 4，自下而上 top = 144 / 122 / 100 / 78
check("batt.card", cw, ch, "batt.ghost", 140, 72, 72, 96)
check("batt.card", cw, ch, "batt.ghostNub", 162, 62, 28, 12)
for gy in (144, 122, 100, 78):
    check("batt.card", cw, ch, "batt.cell%d" % gy, 146, gy, 60, 18)

# ---- 底部数据带（3 栏 x 324）----
cw, ch = card(*PAGE, "band.card", 24, 496, 976, 88)
COL_W = 324
for i in range(3):
    x = COL_W * i
    label("band.card", cw, ch, "band.cap%d" % i, x, 10, COL_W, 19, 16)
    label("band.card", cw, ch, "band.val%d" % i, x, 34, COL_W, 40, 34)
    if i:
        check("band.card", cw, ch, "band.div%d" % i, x, 12, 1, 62)

# ---------------- 卡片矩形两两不得相交 ----------------
overlaps = []
for i, a in enumerate(cards_rect):
    for b in cards_rect[i + 1:]:
        if (a[1] < b[1] + b[3] and b[1] < a[1] + a[3]
                and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]):
            overlaps.append((a[0], b[0]))

print("checks =", checks)
print("cards  =", len(cards_rect), "".join("\n  %-14s x=%3d..%3d y=%3d..%3d\n"
      % (c[0], c[1], c[1] + c[3], c[2], c[2] + c[4]) for c in cards_rect), end="")
if overlaps:
    for a, b in overlaps:
        print("OVERLAP: %s <-> %s" % (a, b))
else:
    print("OVERLAPS: 0")
if not bads:
    print("VIOLATIONS: 0  (空清单 = 全部子控件 right/bottom 均在父内容区内)")
else:
    for b in bads:
        print("VIOLATION parent=%s tag=%s rect=(%d,%d,%d,%d) right=%d bottom=%d content=%dx%d" % b)
