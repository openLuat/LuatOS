# -*- coding: utf-8 -*-
"""FactoryHMI 素材烘焙：把 design\\index.html 的视觉元素转成 PLCUI 用的 PNG。

两类来源：
  1) 设备图元 / 图标 —— Edge headless 渲染 design\\_svg\\*.svg，透明背景截图；
  2) 卡片底 / 按钮 / 液位 / 管道流光 —— PIL 按 1024x600 屏幕坐标精确绘制。

背景是不透明整图（RGB），所以所有半透明描边都先用 mix() 混成实色再画，
避免 convert('RGB') 把 alpha 丢掉后颜色发死。

用法：
  python bake_assets.py all
  python bake_assets.py svg
  python bake_assets.py ui
"""
import os
import sys
import glob
import zlib
import shutil
import struct
import tempfile
import urllib.parse
import subprocess

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                      # ...\FactoryHMI
SVG_DIR = os.path.join(ROOT, 'design', '_svg')
OUT = os.path.join(ROOT, 'plcui', 'assets')
EDGE = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

SS = 2                                            # 超采样倍数
W, H = 1024, 600

# ---------------- 配色（与 index.html 一致） ----------------
BG0      = '#0a1219'
PANEL_C1 = '#13222f'
PANEL_C2 = '#0e1a25'
HEAD_C1  = '#182a3a'
HEAD_C2  = '#101d28'
TOPBAR_C1 = '#16293a'
TOPBAR_C2 = '#0b141c'
STAGE_C1 = '#16293b'
STAGE_C2 = '#0b141d'
LINE     = '#263d52'
LINE_S   = '#22394f'
KPI_C1   = '#162838'
KPI_C2   = '#0f1c27'
DIM_TXT  = '#8ba0b6'
CYAN     = '#22c9d8'
BLUE     = '#2f9be0'
GREEN    = '#38c67e'
AMBER    = '#f2a63c'
RED      = '#e8575c'


def c(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(fg, alpha, bg):
    """把带透明度的前色按 alpha 混到不透明底色上，返回实色。"""
    t = alpha / 255.0
    return (int(fg[0] * t + bg[0] * (1 - t)),
            int(fg[1] * t + bg[1] * (1 - t)),
            int(fg[2] * t + bg[2] * (1 - t)), 255)


def vgrad(w, h, c1, c2, a1=255, a2=255):
    col = Image.new('RGBA', (1, max(2, h)))
    px = col.load()
    for y in range(max(2, h)):
        t = y / (h - 1.0) if h > 1 else 0.0
        px[0, y] = (int(c1[0] + (c2[0] - c1[0]) * t),
                    int(c1[1] + (c2[1] - c1[1]) * t),
                    int(c1[2] + (c2[2] - c1[2]) * t),
                    int(a1 + (a2 - a1) * t))
    return col.resize((max(1, w), max(2, h)), Image.BILINEAR)


def multi_vgrad(w, h, stops):
    """多点竖直渐变，stops = [(位置0~1, 颜色), ...]。"""
    col = Image.new('RGBA', (1, max(2, h)))
    px = col.load()
    for y in range(max(2, h)):
        t = y / (h - 1.0) if h > 1 else 0.0
        lo = stops[0]
        hi = stops[-1]
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                lo, hi = stops[i], stops[i + 1]
                break
        span = (hi[0] - lo[0]) or 1e-6
        k = (t - lo[0]) / span
        px[0, y] = (int(lo[1][0] + (hi[1][0] - lo[1][0]) * k),
                    int(lo[1][1] + (hi[1][1] - lo[1][1]) * k),
                    int(lo[1][2] + (hi[1][2] - lo[1][2]) * k), 255)
    return col.resize((max(1, w), max(2, h)), Image.BILINEAR)


def hgrad_from(stops, w, h):
    return multi_vgrad(h, w, stops).rotate(90, expand=True).resize((w, h), Image.BILINEAR)


def solid_round(img, x, y, w, h, fill=None, radius=0, outline=None, width=1):
    x, y, w, h = int(x * SS), int(y * SS), int(w * SS), int(h * SS)
    d = ImageDraw.Draw(img)
    box = [x, y, x + w - 1, y + h - 1]
    if radius:
        if fill is not None:
            d.rounded_rectangle(box, radius * SS, fill=fill)
        if outline is not None:
            d.rounded_rectangle(box, radius * SS, outline=outline, width=width * SS)
    else:
        if fill is not None:
            d.rectangle(box, fill=fill)
        if outline is not None:
            d.rectangle(box, outline=outline, width=width * SS)


def grad_card(img, x, y, w, h, stops, border=LINE, radius=8):
    """stops 支持 [(0,c1),(1,c2)] 形式的多点渐变。"""
    x, y, w, h = x * SS, y * SS, w * SS, h * SS
    if isinstance(stops[0], tuple) and isinstance(stops[0][1], (tuple, list)):
        body = multi_vgrad(w, h, stops)
    else:
        body = vgrad(w, h, stops[0], stops[1])
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius * SS, fill=255)
    img.paste(body, (x, y), mask)
    if border:
        ImageDraw.Draw(img).rounded_rectangle([x, y, x + w - 1, y + h - 1], radius * SS,
                                              outline=c(border), width=SS)


def save1x(img, name, w, h):
    img.resize((w, h), Image.LANCZOS).save(os.path.join(OUT, name + '.png'))


# =====================================================================
# 一、SVG 图元：一次排版截图，再按记录裁切
# =====================================================================
SPRITES = [
    ('t101',        't101.svg',  76, 108, ''),
    ('t102',        't102.svg',  84, 152, ''),
    ('p101_on',     'p101.svg', 122,  50, 'brightness(1.12) saturate(1.2)'),
    ('p101_off',    'p101.svg', 122,  50, 'grayscale(0.85) brightness(0.58)'),
    ('fv101_open',  'fv101.svg', 52,  51, 'brightness(1.12) saturate(1.2)'),
    ('fv101_close', 'fv101.svg', 52,  51, 'grayscale(0.85) brightness(0.58)'),
    ('e101_on',     'e101.svg',  90,  34, 'brightness(1.12) saturate(1.2)'),
    ('e101_off',    'e101.svg',  90,  34, 'grayscale(0.85) brightness(0.58)'),
    ('p102_on',     'p102.svg',  66,  65, 'brightness(1.12) saturate(1.2)'),
    ('p102_off',    'p102.svg',  66,  65, 'grayscale(0.85) brightness(0.58)'),
    ('fv102_open',  'fv102.svg', 27,  76, 'brightness(1.12) saturate(1.2)'),
    ('fv102_close', 'fv102.svg', 27,  76, 'grayscale(0.85) brightness(0.58)'),
    ('box',         'box.svg',   44,  41, ''),
    ('logo',        'logo.svg',  28,  29, ''),
    ('ic_flow',     'ic-flow.svg',  22, 22, ''),
    ('ic_param',    'ic-param.svg', 22, 22, ''),
    ('ic_alarm',    'ic-alarm.svg', 22, 22, ''),
    ('ic_trend',    'ic-trend.svg', 22, 22, ''),
]


def uri(path):
    return 'file:///' + urllib.parse.quote(os.path.abspath(path).replace('\\', '/'), safe=':/')


def bake_svg():
    W_TOTAL, GAP, PAD = 300, 14, 10
    x, y, row_h = PAD, PAD, 0
    rects = {}
    for name, svg, w, h, _f in SPRITES:
        if x + w + PAD > W_TOTAL:
            x = PAD
            y += row_h + GAP
            row_h = 0
        rects[name] = (x, y, w, h)
        x += w + GAP
        row_h = max(row_h, h)
    total_h = y + row_h + PAD

    parts = []
    for name, svg, w, h, filt in SPRITES:
        rx, ry, rw, rh = rects[name]
        style = 'width:%dpx;height:%dpx' % (rw, rh)
        if filt:
            style += ';filter:' + filt
        parts.append('<img src="%s" style="position:absolute;left:%dpx;top:%dpx;%s">'
                     % (uri(os.path.join(SVG_DIR, svg)), rx, ry, style))

    html = ('<!DOCTYPE html><html><head><meta charset="utf-8"><style>'
            'html,body{margin:0;padding:0;background:transparent;overflow:hidden}'
            'img{display:block}</style></head><body>%s</body></html>' % ''.join(parts))

    tmpdir = tempfile.mkdtemp(prefix='bakesvg_')
    page = os.path.join(tmpdir, 'sprites.html')
    with open(page, 'w', encoding='utf-8') as f:
        f.write(html)
    shot = os.path.join(tmpdir, 'sprites.png')
    prof = os.path.join(tmpdir, 'edgeprof')

    subprocess.run([
        EDGE, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
        '--no-default-browser-check', '--disable-extensions',
        '--allow-file-access-from-files',
        '--default-background-color=00000000',
        '--force-device-scale-factor=3',
        '--user-data-dir=' + prof,
        '--virtual-time-budget=4000',
        '--window-size=%d,%d' % (W_TOTAL, total_h),
        '--screenshot=' + shot, uri(page),
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)

    if not os.path.exists(shot):
        print('SVG 截图失败')
        return False

    big = Image.open(shot).convert('RGBA')
    scale = big.width / float(W_TOTAL)
    print('截图 %dx%d  scale=%.2f' % (big.width, big.height, scale))

    for name, svg, w, h, _f in SPRITES:
        rx, ry, rw, rh = rects[name]
        box = (int(rx * scale), int(ry * scale), int((rx + rw) * scale), int((ry + rh) * scale))
        big.crop(box).resize((rw, rh), Image.LANCZOS).save(os.path.join(OUT, name + '.png'))

    full = Image.open(os.path.join(OUT, 'box.png')).convert('RGBA')
    layer = Image.new('RGBA', full.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([9, 15, 34, 35], 2, fill=(60, 220, 235, 255))
    d.rectangle([9, 15, 34, 17], fill=(210, 255, 255, 255))
    full.alpha_composite(layer)
    full.save(os.path.join(OUT, 'box_full.png'))

    # 图库图标自带宽白底，抠成透明（只抠与画面四边连通的浅色，图标内部白色保留）
    for ic in ('ic_flow', 'ic_param', 'ic_alarm', 'ic_trend'):
        knockout_white(os.path.join(OUT, ic + '.png'))

    shutil.rmtree(tmpdir, ignore_errors=True)
    return True


def knockout_white(path, thresh=200, sat=30):
    """从四边泛洪，把连通的浅色背景像素清成透明。"""
    if not os.path.exists(path):
        return
    im = Image.open(path).convert('RGBA')
    w, h = im.size
    px = im.load()
    seen = [[False] * w for _ in range(h)]
    stack = []
    for x in range(w):
        stack.append((x, 0))
        stack.append((x, h - 1))
    for y in range(h):
        stack.append((0, y))
        stack.append((w - 1, y))

    def light(x, y):
        r, g, b, a = px[x, y]
        return a > 0 and r >= thresh and g >= thresh and b >= thresh \
            and max(r, g, b) - min(r, g, b) < sat

    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        if seen[y][x] or not light(x, y):
            continue
        seen[y][x] = True
        px[x, y] = (0, 0, 0, 0)
        stack.append((x + 1, y))
        stack.append((x - 1, y))
        stack.append((x, y + 1))
        stack.append((x, y - 1))
    im.save(path)


# =====================================================================
# 二、页面背景与控件底图
# =====================================================================
def new_page():
    return Image.new('RGBA', (W * SS, H * SS), c(BG0))


def topbar(img):
    grad_card(img, 0, 0, W, 58, [(0.0, c(TOPBAR_C1)), (1.0, c(TOPBAR_C2))],
              border=None, radius=0)
    solid_round(img, 0, 57, W, 1, c(LINE_S))
    # 品牌图标底座（半透明红，先混色）
    solid_round(img, 19, 14, 30, 31, mix(c(RED), 26, c(TOPBAR_C1)), radius=5)
    # 顶栏底部一道细高光
    solid_round(img, 0, 0, W, 1, mix((120, 180, 230), 40, c(TOPBAR_C1)))


def card_head(img, x, y, w, h=44):
    grad_card(img, x, y, w, h, [(0.0, c(HEAD_C1)), (1.0, c(HEAD_C2))],
              border=None, radius=0)
    d = ImageDraw.Draw(img)
    d.line([x * SS, (y + h) * SS, (x + w) * SS, (y + h) * SS], fill=c(LINE), width=SS)
    d.line([x * SS, (y + 1) * SS, (x + w) * SS, (y + 1) * SS],
           fill=mix((150, 210, 250), 18, c(HEAD_C1)), width=SS)


def pipe_h(img, x, y, w, h):
    px, py = x * SS, y * SS
    body = multi_vgrad(w * SS, h * SS, [
        (0.00, c('#2c3f52')), (0.16, c('#6f879c')), (0.34, c('#a8bccd')),
        (0.60, c('#5d7387')), (0.84, c('#314457')), (1.00, c('#1d2c3a'))])
    mask = Image.new('L', (w * SS, h * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], 3 * SS, fill=255)
    img.paste(body, (px, py), mask)


def pipe_v(img, x, y, w, h):
    body = hgrad_from([
        (0.00, c('#2c3f52')), (0.16, c('#6f879c')), (0.34, c('#a8bccd')),
        (0.60, c('#5d7387')), (0.84, c('#314457')), (1.00, c('#1d2c3a'))], w * SS, h * SS)
    mask = Image.new('L', (w * SS, h * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], 3 * SS, fill=255)
    img.paste(body, (x * SS, y * SS), mask)


def page_common():
    """四页共用页壳：整屏底色 + 顶栏 + 底部导航区压暗。卡片底改由 container 画。"""
    img = new_page()
    topbar(img)
    # 内容区顶部一道极淡的渐变，避免大片纯色发死
    grad_card(img, 0, 58, W, 120, [(0.0, c('#0d1a25')), (1.0, c(BG0))],
              border=None, radius=0)
    # 底部操作条区域压暗
    grad_card(img, 0, 512, W, 88, [(0.0, c(BG0)), (1.0, c('#070d13'))],
              border=None, radius=0)
    img.resize((W, H), Image.LANCZOS).convert('RGB').save(
        os.path.join(OUT, 'bg.jpg'), quality=92, subsampling=0)


def page_canvas():
    """工艺画布 996x294：渐变底 + 网格 + 管道 + 输送带（只有工艺页用）。"""
    sw, sh = 996, 294
    img = Image.new('RGBA', (sw * SS, sh * SS), c('#0e1a24'))
    grad_card(img, 0, 0, sw, sh, [(0.0, c(STAGE_C1)), (0.55, c('#101d29')),
                                  (1.0, c(STAGE_C2))], border=None, radius=0)
    # 左上柔光
    glow = Image.new('RGBA', (sw * SS, sh * SS), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(30, 0, -1):
        a = int(1.6 * i)
        gd.ellipse([-sw * SS * 0.35 + i * 7, -sh * SS * 0.85 + i * 5,
                    sw * SS * 0.85 - i * 7, sh * SS * 0.75 - i * 5],
                   fill=(30, 62, 90, a))
    img.alpha_composite(glow, (0, 0))

    # 网格
    d = ImageDraw.Draw(img)
    grid_col = mix((86, 138, 182), 16, c('#0e1a24'))
    gx = 6
    while gx < sw:
        d.line([gx * SS, 0, gx * SS, sh * SS], fill=grid_col, width=SS)
        gx += 31
    gy = 6
    while gy < sh:
        d.line([0, gy * SS, sw * SS, gy * SS], fill=grid_col, width=SS)
        gy += 31

    # 管道（画布内坐标，与 main.xml 的组件坐标一一对应）
    for x, w in ((106, 40), (268, 32), (352, 32), (468, 38), (596, 56), (718, 50), (795, 57)):
        pipe_h(img, x, 125, w, 14)
    pipe_v(img, 845, 139, 14, 61)

    # 输送带 420,250 560x26
    cx, cy, cw, ch = 420, 250, 560, 26
    solid_round(img, cx, cy, cw, ch, c('#0c1620'), radius=3, outline=c('#2b465c'))
    solid_round(img, cx + 1, cy + 1, cw - 2, 4, c('#3d5568'))
    solid_round(img, cx + 1, cy + 5, cw - 2, 18, c('#1e2c38'))
    d = ImageDraw.Draw(img)
    for i in range(0, cw - 8, 14):
        d.rectangle([(cx + 1 + i) * SS, (cy + 5) * SS,
                     (cx + 1 + i + 7) * SS, (cy + 23) * SS], fill=c('#31475a'))
    # 输送带两端滚轮
    solid_round(img, cx, cy + 1, 6, ch - 2, c('#48607a'), radius=2)
    solid_round(img, cx + cw - 6, cy + 1, 6, ch - 2, c('#48607a'), radius=2)

    img.resize((sw, sh), Image.LANCZOS).convert('RGB').save(
        os.path.join(OUT, 'canvas.jpg'), quality=92, subsampling=0)


# ---------------- 控件多态底图（透明 PNG） ----------------
def button(name, w, h, c1, c2, border, radius=8):
    """渐变圆角按钮：保留竖向渐变与描边，**不做顶部高光**。

    高光是低 alpha 的白色，设备端会做预乘（255×34/255），渲染成一块深灰/黑，
    就是"按钮上半截发黑"。整张图只用不透明像素，圆角外保持透明。
    """
    img = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
    body = vgrad(w * SS, h * SS, c1, c2)
    mask = Image.new('L', (w * SS, h * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1],
                                           radius * SS, fill=255)
    img.paste(body, (0, 0), mask)
    ImageDraw.Draw(img).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1],
                                          radius * SS, outline=c(border), width=SS)
    save1x(img, name, w, h)


def bake_ui():
    button('btn_run_n', 96, 56, c('#2fa46a'), c('#1b7147'), '#3ec27a')
    button('btn_run_p', 96, 56, c('#27895a'), c('#155c39'), '#59dda0')
    button('btn_run_c', 96, 56, c('#3fb877'), c('#1d7d4e'), '#7ff0b6')
    button('btn_stop_n', 96, 56, c('#3d4a5b'), c('#26313d'), '#4b5d72')
    button('btn_stop_p', 96, 56, c('#333e4c'), c('#1e2731'), '#5d718a')
    button('btn_stop_c', 96, 56, c('#4a5a6e'), c('#2c3946'), '#6d8298')
    button('btn_estop_n', 160, 56, c('#e0474c'), c('#8e1d23'), '#ff8186')
    button('btn_estop_p', 160, 56, c('#c33a3f'), c('#711318'), '#ff9a9e')

    button('nav_n', 146, 56, c('#1a2b3a'), c('#121f2b'), LINE)
    button('nav_c', 146, 56, c('#1d4a63'), c('#143b50'), '#2f7fa8')

    # 参数页 / 报警页的宽按钮改由 XML 的 container 画底（纯色，不依赖图片解码），
    # 这里不再生成 btn_apply_* / btn_ack_* / btn_all_* / btn_reset_*。

    # 透明命中层
    for nm, rw, rh in (('hit_kpi', 160, 100), ('hit_row', 698, 44), ('hit_recipe', 364, 62)):
        Image.new('RGBA', (rw, rh), (0, 0, 0, 0)).save(os.path.join(OUT, nm + '.png'))

    # 报警行选中高亮：设备端会对低 alpha 做预乘，半透明会变黑块，这里用实色
    rowc = Image.new('RGBA', (698, 44), c('#163a52'))
    ImageDraw.Draw(rowc).rectangle([0, 43, 697, 43], fill=c('#2f9be0'))
    rowc.save(os.path.join(OUT, 'row_c.png'))

    # 配方卡两态
    for nm, c1, c2, bd in (('recipe_n', '#16283a', '#101d29', LINE),
                           ('recipe_c', '#12293a', '#12293a', '#2f9be0')):
        rimg = Image.new('RGBA', (364 * SS, 62 * SS), (0, 0, 0, 0))
        grad_card(rimg, 0, 0, 364, 62, [(0.0, c(c1)), (1.0, c(c2))], border=bd, radius=8)
        rimg.resize((364, 62), Image.LANCZOS).save(os.path.join(OUT, nm + '.png'))

    # 选中圆点
    chk = Image.new('RGBA', (22 * SS, 22 * SS), (0, 0, 0, 0))
    dc = ImageDraw.Draw(chk)
    dc.ellipse([0, 0, 22 * SS - 1, 22 * SS - 1], fill=c('#2f9be0'), outline=c('#7fc9f5'), width=SS)
    dc.ellipse([7 * SS, 7 * SS, 15 * SS, 15 * SS], fill=(255, 255, 255, 255))
    save1x(chk, 'chk_on', 22, 22)

    chkoff = Image.new('RGBA', (22 * SS, 22 * SS), (0, 0, 0, 0))
    ImageDraw.Draw(chkoff).ellipse([0, 0, 22 * SS - 1, 22 * SS - 1],
                                   outline=c('#3b5872'), width=SS)
    save1x(chkoff, 'chk_off', 22, 22)

    for name, dot, body, border in (
            ('pill_run', GREEN, '#12202c', '#2b4a63'),
            ('pill_manual', AMBER, '#221a0e', '#6b5325'),
            ('pill_stop', '#61758a', '#12202c', '#2b4a63'),
            ('pill_estop', RED, '#2a1110', '#7a2b2f')):
        w, h = 150, 34
        img = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
        mask = Image.new('L', (w * SS, h * SS), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], 17 * SS, fill=255)
        img.paste(Image.new('RGBA', (w * SS, h * SS), c(body)), (0, 0), mask)
        ImageDraw.Draw(img).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], 17 * SS,
                                              outline=c(border), width=SS)
        ImageDraw.Draw(img).ellipse([11 * SS, 12 * SS, 21 * SS, 22 * SS], fill=c(dot))
        save1x(img, name, w, h)

    for name, col in (('bell_off', '#3a2229'), ('bell_on', '#5c1e23')):
        img = Image.new('RGBA', (30 * SS, 26 * SS), (0, 0, 0, 0))
        ImageDraw.Draw(img).polygon([(15 * SS, 0), (30 * SS, 26 * SS), (0, 26 * SS)],
                                    fill=c(col))
        ImageDraw.Draw(img).polygon([(15 * SS, 5 * SS), (25 * SS, 23 * SS), (5 * SS, 23 * SS)],
                                    fill=c('#e8575c'))
        save1x(img, name, 30, 26)

    for name, col in (('lamp_green', GREEN), ('lamp_amber', AMBER), ('lamp_red', RED),
                      ('lamp_gray', '#61758a')):
        img = Image.new('RGBA', (16 * SS, 16 * SS), (0, 0, 0, 0))
        ImageDraw.Draw(img).ellipse([0, 0, 15 * SS, 15 * SS], fill=c(col))
        save1x(img, name, 16, 16)

    # 管道流动光带（两张错相位，交替 set_hidden 形成流动感）
    flow_w, flow_h = 746, 14
    for idx, name in enumerate(('flow_a', 'flow_b')):
        img = Image.new('RGBA', (flow_w * SS, flow_h * SS), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        step = 56
        for i in range(-1, flow_w // step + 2):
            sx = i * step + idx * (step // 2)
            for k in range(0, 24):
                t = k / 23.0
                a = int(190 * (1 - abs(t - 0.5) * 2))
                d.rectangle([(sx + k) * SS, 0, (sx + k + 1) * SS, flow_h * SS],
                            fill=(150, 247, 255, a))
        save1x(img.filter(ImageFilter.GaussianBlur(0.7 * SS)), name, flow_w, flow_h)

    for name, active in (('nozzle_idle', False), ('nozzle_run', True)):
        w, h = 20, 9
        img = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        top = c('#bff4fb') if active else c('#8ea6bb')
        bot = c('#22c9d8') if active else c('#4a6076')
        for y in range(h):
            t = y / (h - 1.0)
            x0 = int((0.28 - 0.28 * t) * w)
            x1 = int((0.72 + 0.28 * t) * w)
            d.rectangle([x0 * SS, y * SS, x1 * SS, (y + 1) * SS],
                        fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
        save1x(img, name, w, h)

    def level(name, w, h, ratio):
        img = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
        lh = int(h * ratio)
        if lh <= 0:
            save1x(img, name, w, h)
            return
        body = vgrad(w * SS, lh * SS, (60, 220, 235, 215), (24, 135, 180, 230))
        mask = Image.new('L', (w * SS, lh * SS), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * SS - 1, lh * SS - 1], 3 * SS, fill=255)
        img.paste(body, (0, (h - lh) * SS), mask)
        ImageDraw.Draw(img).rectangle([0, (h - lh) * SS, w * SS, (h - lh) * SS + SS],
                                      fill=(210, 255, 255, 235))
        save1x(img, name, w, h)

    for i in range(5):
        level('lv_a_%d' % i, 56, 96, i * 0.25)
        level('lv_b_%d' % i, 64, 136, i * 0.25)

    print('UI 素材完成')


def pack_chunk(typ, payload):
    return (struct.pack('>I', len(payload)) + typ + payload
            + struct.pack('>I', zlib.crc32(typ + payload) & 0xffffffff))


def split_png_idat(path, chunk_size=6000):
    """把一个 IDAT 拆成多个。

    PLCUI 的 png_hardware_safe 只有"单 IDAT + 8bit RGB/RGBA"才走硬件解码，
    而硬件路径在 Air8607 上会丢掉 alpha（透明区变白块）。拆成多块后走
    LVGL LodePNG 软件解码，alpha 正常。

    返回是否改写过文件。
    """
    data = open(path, 'rb').read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return False
    pos = 8
    idat = b''
    pre = []
    while pos + 8 <= len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if typ == b'IDAT':
            idat += payload
        elif typ == b'IEND':
            break
        else:
            pre.append((typ, payload))
    if not idat:
        return False
    out = [data[:8]]
    for typ, payload in pre:
        out.append(pack_chunk(typ, payload))
    for i in range(0, len(idat), chunk_size):
        out.append(pack_chunk(b'IDAT', idat[i:i + chunk_size]))
    out.append(pack_chunk(b'IEND', b''))
    open(path, 'wb').write(b''.join(out))
    return True


def postprocess():
    n = 0
    for p in sorted(glob.glob(os.path.join(OUT, '*.png'))):
        if split_png_idat(p):
            n += 1
    # 背景已改用 JPG，清掉旧 PNG 免得混淆
    for p in glob.glob(os.path.join(OUT, 'bg_*.png')):
        os.remove(p)
    print('PNG 多 IDAT 处理:', n, '张；旧背景 PNG 已清理')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('all', 'ui'):
        page_common()
        page_canvas()
        bake_ui()
    if what in ('all', 'svg'):
        if not bake_svg():
            sys.exit(1)
    postprocess()
    print('输出目录:', OUT)
