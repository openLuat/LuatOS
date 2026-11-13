# -*- coding: utf-8 -*-
"""
plcui_water_supply · 构建工具
1) 读取 web/spec.js（界面单一数据源）
2) 用 PIL 生成控件态 PNG（按钮/开关/下拉/胶囊），用 Edge 无头渲染 PLC_SVG 泵三态与整页背景
3) 生成 code/main.xml（PLCUI XML，坐标与 web/app.js 渲染几何一致）

用法:  python tools/build_ui.py          # 全量构建
       python tools/build_ui.py --xml    # 仅重新生成 main.xml
"""
import json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, "web")
CODE = os.path.join(ROOT, "code")
ASSETS = os.path.join(CODE, "assets")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
FONT = r"C:\Windows\Fonts\msyh.ttc"
FONTB = r"C:\Windows\Fonts\msyhbd.ttc"

# ---- web/app.js 渲染几何（必须与 app.js 的 cellGeom/renderCell 一致）----
FORM_X, FORM_Y, FORM_W = 14, 18, 806
TITLE_H, ROW_H = 44, 74
NAV_X, NAV_Y, NAV_BTN_H, NAV_BTN_GAP = 830, 18, 48, 8
ROW_TOP = 6
VAL_W, VAL_H = 72, 32


def load_spec():
    """spec.js 是 JS 对象字面量：去注释、给裸键加引号后按 JSON 解析。"""
    src = open(os.path.join(WEB, "spec.js"), encoding="utf-8").read()
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = src.split("=", 1)[1].strip().rstrip(";")
    src = re.sub(r"([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*:)", r'\1"\2"\3', src)
    return json.loads(src)


# ---------- PIL 素材 ----------
from PIL import Image, ImageDraw, ImageFont  # noqa: E402


def font(sz, bold=False):
    for p in ((FONTB if bold else FONT), FONT, r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, sz)
            except OSError:
                pass
    return ImageFont.load_default()


def text_w(d, txt, f):
    return d.textbbox((0, 0), txt, font=f)[2]


def rrect(path, w, h, radius, fill, txt="", tcol="#123C74", tsz=18, bold=False, border=None, grad=None):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if grad:
        for y in range(h):
            t = y / max(1, h - 1)
            c = tuple(int(grad[0][i] + (grad[1][i] - grad[0][i]) * t) for i in range(3))
            d.rectangle((0, y, w, y + 1), fill=c + (255,))
        d.rounded_rectangle((0, 0, w - 1, h - 1), radius, outline=border, fill=None)
    else:
        d.rounded_rectangle((0, 0, w - 1, h - 1), radius, fill=fill, outline=border)
    if txt:
        f = font(tsz, bold)
        tw = text_w(d, txt, f)
        bb = d.textbbox((0, 0), txt, font=f)
        d.text(((w - tw) / 2, (h - (bb[3] - bb[1])) / 2 - bb[1]), txt, font=f, fill=tcol)
    im.save(path)


def hexrgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


# ---------- 标签胶囊 PNG（镜像 web .flab：15px/600/行高19/内边距3x6/圆角3/1px边框）----------
# 共享背景后静态文字不再烘焙进 bg，改为小 PNG 资源（几十字节级，解码内存远小于整页大图）
_CHIPS = {}


def chip_png(text, maxw, extras=()):
    """extras: ((dx, dy, txt), ...) 静态单位文本（.funit 15px/600）烘进同一 PNG，
    相对胶囊左上角偏移、20px 行盒内左对齐垂直居中 —— 省 label 控件且像素与 web 一致。"""
    key = (text, maxw, tuple(extras))
    if key in _CHIPS:
        return _CHIPS[key]
    f = font(15, bold=True)
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    wrap_w = max(76, maxw) - 14          # box-sizing:border-box：减 12 内边距 + 2 边框
    lines, cur = [], ""
    for ch in str(text):
        if cur and text_w(probe, cur + ch, f) > wrap_w:
            lines.append(cur)
            cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    tw = max(text_w(probe, ln, f) for ln in lines)
    pref = tw + 14
    cw = 76 if pref < 76 else min(pref, max(76, maxw))   # .flab min-width:76 / max-width:maxw
    chh0 = 19 * len(lines) + 8          # 行高19 * 行数 + 内边距6 + 边框2
    ex = [(dx, dy, txt, text_w(probe, txt, f)) for dx, dy, txt in extras]
    w = max([cw] + [dx + tw2 for dx, _, _, tw2 in ex])   # 画布可超胶囊（容纳单位文本）
    h = max([chh0] + [dy + 20 for _, dy, _, _ in ex])
    stem = png("lb%03d" % (len(_CHIPS) + 1))[:-4]   # 控件 src 引用资源 id（无扩展名）
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, cw - 1, chh0 - 1), 3, fill="#3FD0E8", outline="#1F96AC")
    for i, ln in enumerate(lines):
        bb = d.textbbox((0, 0), ln, font=f)
        d.text(((cw - (bb[2] - bb[0])) / 2 - bb[0],
                4 + i * 19 + (19 - (bb[3] - bb[1])) / 2 - bb[1]),
               ln, font=f, fill="#10345E")
    for dx, dy, txt, _ in ex:            # .funit：15px/600/#10345E，行盒 20px 垂直居中
        bb = d.textbbox((0, 0), txt, font=f)
        d.text((dx - bb[0], dy + 10 - (bb[3] - bb[1]) / 2 - bb[1]),
               txt, font=f, fill="#10345E")
    im.save(os.path.join(ASSETS, stem + ".png"))
    _CHIPS[key] = (stem, w, h)
    return _CHIPS[key]


def dim(style, k=0.72):
    """按钮按下态：渐变整体变暗，保证与常态图肉眼可辨（按下有反馈）"""
    (g0, g1), tc = style

    def dk(h):
        r, g, b = hexrgb(h)
        return "#%02X%02X%02X" % (int(r * k), int(g * k), int(b * k))

    return ((dk(g0), dk(g1)), tc)


# ---------- 资源命名：ASCII、≤23 字节、全局不重名（PLCUI 资源名限制） ----------
SLUG = {
    "变频": "vfd", "工频": "fpwr", "待机": "stby", "辅泵": "aux",
    "上一页": "prev", "下一页": "next", "停用": "off", "厂家设置": "factory",
    "压力校准": "pcal", "恢复默认": "reset", "确定": "ok", "触摸校准": "tcal",
    "运行画面": "runscr",
    "上电自检": "selftest", "休眠功能启用": "sleepen", "休眠时换泵": "swapslp",
    "多泵运行时不换泵": "noswap", "换泵使用小时": "swaphr", "特殊休眠环境": "spsleep",
    "轮换功能启用": "rotate",
}
_USED = set()


def slug(label):
    s = SLUG.get(label)
    return s if s else (re.sub(r"[^A-Za-z0-9]+", "", str(label)) or "x")


def png(stem):
    name = stem + ".png"
    assert name.isascii() and len(name.encode("utf-8")) <= 23, name
    assert stem not in _USED, "资源重名: " + name
    _USED.add(stem)
    return name


# 泵图有效像素裁剪偏移：build_pumps 写 tools/trim.json，gen_run 读取
PUMP_TRIM = {}


def load_trim():
    PUMP_TRIM.clear()
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "trim.json")
    if os.path.exists(path):
        PUMP_TRIM.update(json.load(open(path)))


def build_widgets(spec):
    """生成按钮/开关/下拉框/胶囊等控件态 PNG。"""
    os.makedirs(ASSETS, exist_ok=True)
    GRAY = (("#E4EAF0", "#C2CCD6"), "#22384E")
    GREEN = (("#B4E46C", "#8ED246"), "#123C74")
    GPILL = (("#A8E060", "#5FBE30"), "#FFFFFF")
    BLUE = (("#6FB6EA", "#3D8AD2"), "#FFFFFF")
    RED = (("#F07168", "#D8433A"), "#FFFFFF")
    TOGON = (("#7ED95A", "#4CB82E"), "#FFFFFF")

    def btn(name, w, h, style, txt, tsz=18, r=6, bold=False):
        g, tc = style
        rrect(os.path.join(ASSETS, name), w, h, r, None, txt, tc, tsz, bold,
              grad=tuple(hexrgb(c) for c in g), border=(30, 30, 30, 60))

    # 右侧导航按钮（灰/绿两态，按 SPEC.nav 顺序）
    for i, n in enumerate(spec["nav"]):
        t = n.split("|")[0]
        btn(f"nav_{i}_n.png", 172, 48, GRAY, t, 18, 4)
        btn(f"nav_{i}_s.png", 172, 48, GREEN, t, 18, 4, bold=True)
    # 通用小按钮（操作条 / 表单按钮）
    names = set()
    for p in spec["pages"]:
        for c in (p.get("strip") or []):
            if c.get("t") == "btn":
                names.add(c["v"])
        for row in p.get("rows") or []:
            for c in (row if isinstance(row, list) else []):
                if c.get("t") == "btn":
                    names.add(c["v"])
    for n in names:
        s = slug(n)
        btn(png(f"sbtn_{s}"), 150, 36, GRAY, n, 16, 4)
        btn(png(f"sbtn_{s}_w"), 140, 36, GRAY, n, 16, 4)
        btn(png(f"fbtn_{s}"), 120, 32, GRAY, n, 15, 4)
    # 开关按钮（toggle）：绿=开 / 灰=关 / 红
    for p in spec["pages"]:
        for row in p.get("rows") or []:
            for c in (row if isinstance(row, list) else []):
                if c.get("t") == "toggle":
                    n = max(2, len(row))
                    cw = (FORM_W - 8) // n - 8
                    w = cw - 14
                    key = slug(c["l"])
                    if c.get("red"):
                        btn(png(f"tog_{key}_a"), w, 32, RED, c["l"], 15, 4)
                        btn(png(f"tog_{key}_b"), w, 32, GRAY, c["l"], 15, 4)
                    else:
                        btn(png(f"tog_{key}_a"), w, 32, TOGON, c["l"], 15, 4)
                        btn(png(f"tog_{key}_b"), w, 32, GRAY, c["l"], 15, 4)
    # 下拉框底（文字由 label 覆盖）
    rrect(os.path.join(ASSETS, "selbox.png"), 124, 32, 3, "#FFFFFF", "", "#000", 12,
          border=hexrgb("#1E4E86") + (255,))
    # 时段供水 开关圆钮
    for on, name, fill, txt in ((False, "sw_off.png", "#B8C2CA", "关"), (True, "sw_on.png", "#5FC83C", "开")):
        rrect(os.path.join(ASSETS, name), 44, 34, 17, fill, txt, "#123C74" if not on else "#FFFFFF", 15)
    # 运行画面按钮（两态：_b 为按下态，必须比 _a 明显更暗）
    btn("run_start_a.png", 168, 46, GREEN, "自动启动", 19, 6, bold=True)
    btn("run_start_b.png", 168, 46, dim(GREEN), "自动启动", 19, 6, bold=True)
    btn("run_stop_a.png", 168, 46, GRAY, "自动停止", 19, 6, bold=True)
    btn("run_stop_b.png", 168, 46, dim(GRAY), "自动停止", 19, 6, bold=True)
    btn("run_menu_a.png", 160, 44, GRAY, "主菜单", 19, 6, bold=True)
    btn("run_menu_b.png", 160, 44, dim(GRAY), "主菜单", 19, 6, bold=True)
    btn("run_auto_a.png", 242, 42, GPILL, "自动", 19, 21, bold=True)   # a=选中(绿胶囊)
    btn("run_auto_b.png", 242, 42, BLUE, "自动", 19, 21, bold=True)    # b=未选中(蓝)
    btn("run_manual_a.png", 242, 42, GPILL, "手动", 19, 21, bold=True)
    btn("run_manual_b.png", 242, 42, BLUE, "手动", 19, 21, bold=True)
    btn("run_fault_a.png", 242, 42, BLUE, "故障记录", 19, 21, bold=True)
    btn("run_fault_b.png", 242, 42, dim(BLUE), "故障记录", 19, 21, bold=True)
    # 泵位状态胶囊
    for m in ("变频", "工频", "待机", "辅泵"):
        rrect(os.path.join(ASSETS, png(f"chip_{slug(m)}")), 86, 28, 4, "#8FE8E8", m, "#10345E", 15,
              border=hexrgb("#46B8C8") + (255,))
    # 主菜单按钮
    for i, t in enumerate(["运行画面", "时段供水", "出口设置", "入口设置", "换泵休眠",
                           "泵组设置", "系统设置", "厂家设置", "故障记录", "返回"]):
        style = GREEN if t in ("运行画面", "返回") else BLUE
        btn(f"menu_{i}.png", 238, 86, style, t.replace(" ", ""), 22, 10, bold=True)
    # 故障页按钮
    btn("flt_clear.png", 180, 52, GREEN, "清除记录", 19, 6, bold=True)
    btn("flt_back.png", 180, 52, GRAY, "返回", 19, 6, bold=True)
    print("[ok] 控件 PNG 已生成")
# ---------- Edge 无头渲染 ----------
import tempfile  # noqa: E402

PAGE_IDS = ["page-run", "page-menu", "page-fault", "p_time", "p_out", "p_in",
            "p_sleep", "p_pumps", "p_sys1", "p_sys2", "p_factory"]

def edge_shot(url, out_png, w, h, scale=1, transparent=True):
    cmd = [EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars",
           "--no-first-run", f"--force-device-scale-factor={scale}",
           f"--window-size={w},{h}", "--virtual-time-budget=3000"]
    if transparent:
        cmd.append("--default-background-color=00000000")
    cmd.append(f"--screenshot={out_png}")
    cmd.append(url)
    r = subprocess.run(cmd, capture_output=True, timeout=120)
    if not os.path.exists(out_png):
        raise RuntimeError("Edge 截图失败: " + r.stderr.decode("gbk", "ignore")[-300:])
    return out_png


# ---------- 泵三态（SVG 重着色 -> Edge 渲染 -> 叠数字） ----------
PUMP_MAPS = {
    "run": {"#67BBBB": "#5BC8FF", "#568A89": "#3E86C8", "#385857": "#2E6BA8",
            "#2A6969": "#23578F", "#224F4F": "#1B4272", "#214F4F": "#1B4272",
            "#1E4444": "#173A66", "#1C4040": "#15355E", "#142D2D": "#0F2544",
            "#112626": "#0D1F3A"},   # 变频=蓝
    "freq": {"#67BBBB": "#FF7A6E", "#568A89": "#D14A3E", "#385857": "#B0382B",
             "#2A6969": "#94291F", "#224F4F": "#7A2219", "#214F4F": "#6D1D15",
             "#1E4444": "#601811", "#1C4040": "#59150F", "#142D2D": "#3F0E09",
             "#112626": "#360B07"},   # 工频=红
    "stand": {"#67BBBB": "#B8C2CC", "#568A89": "#8A96A2", "#385857": "#6E7A86",
              "#2A6969": "#5E6A76", "#224F4F": "#4A5662", "#214F4F": "#4A5662",
              "#1E4444": "#424E5A", "#1C4040": "#3E4A56", "#142D2D": "#323E4A",
              "#112626": "#2A3642"},  # 待机=灰
}
PUMP_W, PUMP_H = 86, 132

def build_pumps():
    svg = open(os.path.join(WEB, "assets", "pump.svg"), encoding="utf-8").read()
    tmp = tempfile.mkdtemp(prefix="plcui_pump_")
    for state, pal in PUMP_MAPS.items():
        s = svg
        for a, b in pal.items():
            s = re.sub(re.escape(a), b.upper(), s, flags=re.I)
        # object-fit:contain 等效：按 viewBox 比例缩放到 2x 盒并居中
        # （根节点 width/height 带 px 后缀，必须精确改写 svg 根属性，不能用裸数字正则）
        vb = re.search(r'viewBox="[\d.\-eE]+ [\d.\-eE]+ ([\d.]+) ([\d.]+)"', s)
        vw, vh = float(vb.group(1)), float(vb.group(2))
        k = min(PUMP_W * 2 / vw, PUMP_H * 2 / vh)
        s = re.sub(r'(<svg\b[^>]*?)\swidth="[^"]*"', r'\1width="%.2f"' % (vw * k), s, count=1)
        s = re.sub(r'(<svg\b[^>]*?)\sheight="[^"]*"', r'\1height="%.2f"' % (vh * k), s, count=1)
        html = (f'<html><body style="margin:0;background:transparent">'
                f'<div style="width:{PUMP_W * 2}px;height:{PUMP_H * 2}px;'
                f'display:flex;align-items:center;justify-content:center">{s}</div></body></html>')
        hf = os.path.join(tmp, f"{state}.html")
        open(hf, "w", encoding="utf-8").write(html)
        shot = edge_shot("file:///" + hf.replace("\\", "/"), os.path.join(tmp, f"{state}.png"),
                         PUMP_W * 2, PUMP_H * 2, scale=1, transparent=True)
        base = Image.open(shot).convert("RGBA").resize((PUMP_W, PUMP_H), Image.LANCZOS)
        for i in range(1, 6):
            im = base.copy()
            d = ImageDraw.Draw(im)
            f = font(22, True)
            t = str(i)
            bb = d.textbbox((0, 0), t, font=f)
            tx = (PUMP_W - (bb[2] - bb[0])) / 2 - bb[0]
            ty = 47 - (bb[3] - bb[1]) / 2 - bb[1]
            d.text((tx, ty + 1), t, font=f, fill=(0, 0, 0, 140))
            d.text((tx, ty), t, font=f, fill="#FFFFFF")
            im.save(os.path.join(ASSETS, f"pump_{i}_{state}.png"))
    # 有效像素裁剪：去掉透明边，位图尺寸 = 可见像素区域（省内存、省内存解码）
    for state in PUMP_MAPS:
        boxes = []
        for i in range(1, 6):
            path = os.path.join(ASSETS, f"pump_{i}_{state}.png")
            # alpha>=8 才算有效像素，排除 LANCZOS 重采样的半透明幽灵边
            a = Image.open(path).split()[3].point(lambda v: 255 if v >= 8 else 0)
            boxes.append(a.getbbox())
        x0 = min(b[0] for b in boxes)
        y0 = min(b[1] for b in boxes)
        x1 = max(b[2] for b in boxes)
        y1 = max(b[3] for b in boxes)
        for i in range(1, 6):
            path = os.path.join(ASSETS, f"pump_{i}_{state}.png")
            Image.open(path).crop((x0, y0, x1, y1)).save(path)
        PUMP_TRIM[state] = [x0, y0, x1 - x0, y1 - y0]
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "trim.json"), "w") as f:
        json.dump(PUMP_TRIM, f)
    print("[ok] 泵体三态 x5 数字 PNG 已生成（有效像素裁剪 %s）" % PUMP_TRIM)


# ---------- 整页背景烘焙（index.html?bake=1&page=xx -> bg_xx.jpg） ----------
FORM_FAMILY = ("p_out", "p_in", "p_sleep", "p_pumps", "p_sys1", "p_sys2", "p_factory")


def build_backgrounds():
    """烘焙整页背景。表单族 7 页的铬层（渐变/面板/行分隔）完全相同，
    共用 bg_form.jpg（chrome 模式：无文字无控件），文字/值框全部由 XML 控件呈现。"""
    tmp = tempfile.mkdtemp(prefix="plcui_bg_")
    web_url = "file:///" + WEB.replace("\\", "/") + "/index.html"
    jobs = [(pid.replace("page-", ""), f"{web_url}?bake=1&page={pid}")
            for pid in PAGE_IDS if pid.replace("page-", "") not in FORM_FAMILY]
    jobs.append(("form", f"{web_url}?chrome=1"))
    for pid, url in jobs:
        shot = os.path.join(tmp, pid + ".png")
        edge_shot(url, shot, 1024, 600, scale=1, transparent=False)
        # 真机单块堆上限 ~1.2MB，整帧 RGB565 解码缓冲 1,228,800 会 alloc fail；
        # 上下两条（各 614,400）分别解码，规避单块限制（bg_*_t / bg_*_b）
        im = Image.open(shot).convert("RGB")
        im.crop((0, 0, 1024, 300)).save(
            os.path.join(ASSETS, f"bg_{pid}_t.jpg"), quality=88, optimize=True)
        im.crop((0, 300, 1024, 600)).save(
            os.path.join(ASSETS, f"bg_{pid}_b.jpg"), quality=88, optimize=True)
    print(f"[ok] 整页背景 JPG x{len(jobs)}x2 条带已烘焙（表单族 7 页共用 bg_form）")
# ---------- XML 生成（几何与 web/app.js renderCell/renderSched 严格镜像）----------
from xml.sax.saxutils import escape, quoteattr  # noqa: E402

BORDER = 2
CX, CY = FORM_X + BORDER, FORM_Y + BORDER
GO2PAGE = {"page-run": "run", "page-fault": "fault"}
GO2HANDLER = {"run": "go_run", "fault": "go_flt", "p_factory": "go_p_factory",
              "p_sys2": "go_p_sys2", "p_sys1": "go_p_sys1", "menu": "go_menu"}


def go_handler(target):
    return GO2HANDLER.get(target, "go_" + target)
PROBE = {"run": "rn", "menu": "mn", "fault": "ft", "p_time": "pt", "p_out": "po",
         "p_in": "pi", "p_sleep": "ps", "p_pumps": "pp", "p_sys1": "y1",
         "p_sys2": "y2", "p_factory": "pf"}
SEL_OPTS = {}


def esc(t):
    return escape(str(t))


def tag(name, attrs, close=True):
    def key(k):
        return k if k == "font_size" else k.replace("_", "-")
    a = "".join(f' {key(k)}={quoteattr(str(v))}' for k, v in attrs.items() if v is not None)
    return f"<{name}{a}/>" if close else f"<{name}{a}>"


def cell_geom(n, idx, merged):
    if merged:
        return 330, 466
    if n == 1:
        return 8, 790
    W = (FORM_W - 8) // n
    return 4 + idx * W, W - 8


def band_top(r, sched=False):
    t = CY + TITLE_H + (44 if sched else 0)
    return t + r * ROW_H


TEXT_TYPES = {"label", "textarea", "keyboard", "table"}


class Page:
    def __init__(self, pid, title):
        self.pid = pid
        self.out = []
        self.n = 0

    def add(self, name, x, y, w, h, **attrs):
        self.n += 1
        if name in TEXT_TYPES and "font" not in attrs:
            attrs["font"] = "hzfont"   # font_size 仅对 hzfont 合法，中文也依赖它
        wid = attrs.pop("id", f"{PROBE[self.pid]}_{self.n}")
        self.out.append(tag(name, {"id": wid, "x": int(x), "y": int(y),
                                   "w": int(w), "h": int(h), **attrs}))
        return wid

    def text(self, x, y, w, h, txt, size=16, color="#123C74", align="left", **kw):
        return self.add("label", x, y, w, h, text=esc(txt), font_size=size,
                        color=color, align=align, **kw)

    def value(self, x, y, w, h, val, size=17, align="center", **kw):
        return self.add("textarea", x, y, w, h, text=esc(val), font_size=size,
                        color="#16243C", align=align, max_length=10,
                        accepted_chars="0123456789.-", keyboard="kb",
                        one_line="true", on_submit="val_submit",
                        on_cancel="val_cancel", **kw)

    def img(self, x, y, w, h, src, handler=None, pressed=None, **kw):
        return self.add("image", x, y, w, h, src=src,
                        src_pressed=pressed, clickable="true" if handler else None,
                        on_click=handler, **kw)

    def kb(self):
        self.add("keyboard", 24, 180, 454, 234, id="kb", layout="number", hidden="true")

    def xml(self):
        body = "\n      ".join(self.out)
        return (f'    <page id="{self.pid}" background="#101820">\n'
                f"      {body}\n    </page>")


def page_bg(p, stem):
    """整页背景 = 上下两条 JPG（bg_*_t / bg_*_b），避开真机单块解码缓冲上限"""
    p.img(0, 0, 1024, 300, stem + "_t")
    p.img(0, 300, 1024, 300, stem + "_b")


def form_nav(p, pid):
    for i, n in enumerate(SPEC["nav"]):
        t, target = n.split("|")
        cur = (target == pid) or (pid == "p_sys2" and target == "p_sys1")
        p.img(NAV_X, NAV_Y + i * (NAV_BTN_H + NAV_BTN_GAP), 172, NAV_BTN_H,
              f"nav_{i}_{'s' if cur else 'n'}",
              go_handler(target) if target != pid else None,
              pressed=f"nav_{i}_n")
    p.text(NAV_X, 360, 180, 28, "", size=20, color="#C8F060", align="center", id=pid + "_cd")
    p.text(NAV_X, 388, 180, 28, "", size=20, color="#C8F060", align="center", id=pid + "_ct")


ACT_ID = {("p_pumps", "恢复默认"): "act_reset", ("p_sys2", "压力校准"): "act_pcal",
          ("p_factory", "停用"): "act_off", ("p_factory", "确定"): "act_ok",
          ("p_factory", "触摸校准"): "act_tcal"}


def gen_form(page):
    """表单族生成：7 页共用 bg_form 铬层，所有文字/值框/控件全部控件化。
    坐标严格镜像 web renderCell/renderForm（.frow 1px 边 → abs = band_top + 1 + 内联 top）。"""
    pid = page["id"]
    p = Page(pid, page["title"])
    page_bg(p, "bg_form")
    rows = page.get("rows", [])
    strip = page.get("strip", [])
    merged = len(rows) >= 7 and strip
    # 标题（web .f-title：25px/700/#0A2C5C 居中，44px 行盒）
    p.text(CX, CY + 7, FORM_W - 4, 28, page["title"], size=25,
           color="#0A2C5C", align="center")
    if page.get("sub"):
        p.text(CX + 10, CY + 11, 66, 22, page["sub"], size=16, color="#0A2C5C")
        p.add("container", 96, 31, 52, 26, background="#FFFFFF",
              border_color="#0A2C5C", border_width="1")
        p.value(96, 34, 52, 22, page.get("subv", ""), size=16, id=pid + "_sub")
        p.text(152, CY + 11, 24, 22, page.get("subu", ""), size=16, color="#0A2C5C")
    if page.get("ver"):
        p.text(606, CY + 14, 200, 20, page["ver"], size=15,
               color="#0A2C5C", align="right")
    for r, row in enumerate(rows):
        cells = row if isinstance(row, list) else []
        bt = band_top(r)
        if not cells:
            continue
        for i, c in enumerate(cells):
            x, w = cell_geom(len(cells), i, merged and r == 6)
            X, Y = CX + x, bt
            cols3 = w < 300
            valX = 112 if cols3 else 160
            if c.get("dt"):
                extras = [(min(200, w - 320) + 30 + k * 62 + 50, 8, t)
                          for k, t in enumerate(["年", "月", "日", "时"])]
                cn, cw, chh = chip_png(c["l"] + ":", w - 320, extras)
                p.img(X, Y + 13, cw, chh, cn)
                for k in range(4):
                    bx = X + min(200, w - 320) + 30 + k * 62
                    p.add("container", bx, Y + 17, 48, VAL_H, background="#FFFFFF",
                          border_color="#1E4E8C", border_width="1")
                    p.value(bx, Y + 23, 48, 20, "0", size=17)
            elif c.get("t") == "toggle":
                key = slug(c["l"])
                on = bool(c.get("on") or c.get("red"))
                # id 即资源基名 tog_<key>，main.lua 用 ev.id 直接翻 _a/_b（不依赖自动编号）
                p.img(X + 6, Y + 21, w - 14, 32,
                      f"tog_{key}_{'a' if on else 'b'}", "tog_click",
                      pressed=f"tog_{key}_{'a' if on else 'b'}", id=f"tog_{key}")
                SEL_OPTS.setdefault("__tog__", {})[f"tog_{key}"] = on
                if c.get("h"):
                    p.text(X + 6, Y + 55, w - 14, 32, c["h"], size=12, color="#0A2C5C")
            elif c.get("t") == "sel":
                cn, cw, chh = chip_png(c["l"] + ":", w - 140)
                p.img(X, Y + 15, cw, chh, cn)
                sid = p.img(X + w - 132, Y + 19, 124, 32, "selbox", "sel_click")
                p.text(X + w - 132, Y + 26, 124, 20, c["v"], size=15,
                       color="#123C74", align="center", id=sid + "L")
                SEL_OPTS[sid] = {"opts": c["opts"], "cur": c["v"]}
            elif c.get("t") == "btn":
                b = slug(c["v"])
                p.img(X + w / 2 - 60, Y + 21, 120, 32, f"fbtn_{b}", "act_click",
                      pressed=f"fbtn_{b}", id=ACT_ID.get((pid, c["v"]), f"act_{b}"))
            elif c.get("l") or c.get("v"):
                vx = X + (300 if c.get("wide") else valX)
                extras = ((vx + 78 - X, 10, c["u"]),) if c.get("u") else ()
                cn, cw, chh = chip_png(
                    c["l"], 260 if c.get("wide") else (104 if cols3 else 140), extras)
                p.img(X, Y + 13, cw, chh, cn)
                p.add("container", vx, Y + 19, VAL_W, VAL_H, background="#FFFFFF",
                      border_color="#1E4E8C", border_width="1")
                p.value(vx, Y + 25, VAL_W, 20, c.get("v", ""), size=17)
                if c.get("h"):
                    hx = X + 430 if c.get("wide") else (X + 4 if cols3 else X + 276)
                    p.text(hx, Y + 9, (w - 440 if c.get("wide") else 122), 32,
                           c["h"], size=12, color="#0A2C5C")
    bt = band_top(6)
    for i, c in enumerate(strip):
        if merged:
            if c.get("t") == "btn":
                b = slug(c["v"])
                p.img(CX + 14 + i * 156, bt + 21, 140, 36, f"sbtn_{b}_w",
                      go_handler(GO2PAGE.get(c.get("go", ""), c.get("go", ""))),
                      pressed=f"sbtn_{b}_w")
        else:
            bx = CX + 20 + i * 170
            if c.get("t") == "btn":
                b = slug(c["v"])
                p.img(bx, bt + 21, 150, 36, f"sbtn_{b}",
                      go_handler(GO2PAGE.get(c.get("go", ""), c.get("go", ""))),
                      pressed=f"sbtn_{b}")
            else:
                extras = ((188, 6, c["u"]),) if c.get("u") else ()
                cn, cw, chh = chip_png(c["l"], 104, extras)
                p.img(bx, bt + 19, cw, chh, cn)
                p.add("container", bx + 110, bt + 21, VAL_W, VAL_H,
                      background="#FFFFFF", border_color="#1E4E8C", border_width="1")
                p.value(bx + 110, bt + 27, VAL_W, 20, c.get("v", ""), size=17)
    form_nav(p, pid)
    p.kb()
    return p
def gen_sched(page):
    pid = page["id"]
    p = Page(pid, page["title"])
    page_bg(p, "bg_" + pid)
    S = SPEC["layout"]["sched"]
    for r, row in enumerate(page["rows"]):
        bt = band_top(r, sched=True)
        p.img(CX + S["swX"], bt + 21, 44, 34, "sw_on" if row["sw"] else "sw_off",
              "sw_click", pressed="sw_on" if row["sw"] else "sw_off")
        for k, f in enumerate(("sh", "sm", "eh", "em", "p")):
            x = S[{"sh": "shX", "sm": "smX", "eh": "ehX", "em": "emX", "p": "pX"}[f]]
            # 白框已烘焙在 bg_p_time.jpg（web bake 保留 input.fval），仅需居中文本
            p.value(CX + x, bt + 27, 52, 20, row[f], size=17)
    bt = band_top(5, sched=True)   # 5 条时段行之后的第 6 条 band（索引 5）
    for i, c in enumerate(page.get("strip", [])):
        if c.get("t") == "btn":
            b = slug(c["v"])
            p.img(CX + 20 + i * 170, bt + 21, 150, 36, f"sbtn_{b}",
                  go_handler(GO2PAGE.get(c.get("go", ""), c.get("go", ""))),
                  pressed=f"sbtn_{b}")
        else:
            p.value(CX + 500, bt + 27, VAL_W, 20, c.get("v", ""), size=17)
    form_nav(p, pid)
    p.kb()
    return p


RUN_PUMPS = [("run", "变频"), ("freq", "工频"), ("freq", "工频"),
             ("stand", "待机"), ("stand", "待机")]
# 值框（bg_run 实测顶边 130/212/294/376，高 44）垂直居中：框顶 + (44-27)//2 = 框顶+8
RUN_VALS = [("run_p", 138, "1.87"), ("run_t", 220, "2.00"),
            ("run_l", 302, "1.20"), ("run_f", 384, "46.50")]


def gen_run():
    load_trim()
    p = Page("run", "")
    page_bg(p, "bg_run")
    p.text(24, 14, 200, 26, "", size=20, color="#123C74", id="run_cd")
    p.text(24, 40, 200, 26, "", size=20, color="#123C74", id="run_ct")
    for i, (st, mode) in enumerate(RUN_PUMPS):
        x = 216 + i * 104
        tr = PUMP_TRIM.get(st)          # [x0, y0, w, h]，无裁剪数据时回退原盒
        if tr:
            p.img(x + tr[0], 300 + tr[1], tr[2], tr[3], f"pump_{i + 1}_{st}",
                  id=f"pump_img_{i + 1}")
        else:
            p.img(x, 300, PUMP_W, PUMP_H, f"pump_{i + 1}_{st}", id=f"pump_img_{i + 1}")
        p.img(x, 524, 86, 28, f"chip_{slug(mode)}", id=f"pump_chip_{i + 1}")
    for wid, y, v in RUN_VALS:
        p.add("textarea", 778, y, 176, 32, text=v, font_size=24, color="#16243C",
              align="left", max_length=8, accepted_chars="0123456789.",
              keyboard="kb", one_line="true", on_submit="val_submit",
              on_cancel="val_cancel", id=wid)
    p.img(332, 64, 168, 46, "run_start_a", "run_start", pressed="run_start_b")
    p.img(524, 64, 168, 46, "run_stop_a", "run_stop", pressed="run_stop_b")
    p.img(28, 538, 160, 44, "run_menu_a", "go_menu", pressed="run_menu_b")
    p.img(768, 438, 242, 42, "run_auto_a", "set_auto", pressed="run_auto_b", id="run_auto")
    p.img(768, 488, 242, 42, "run_manual_b", "set_manual", pressed="run_manual_a", id="run_manual")
    p.img(768, 538, 242, 42, "run_fault_a", "go_flt", pressed="run_fault_b")
    p.kb()
    return p


MENU = [("运行画面", "run"), ("时段供水", "p_time"), ("出口设置", "p_out"),
        ("入口设置", "p_in"), ("换泵休眠", "p_sleep"), ("泵组设置", "p_pumps"),
        ("系统设置", "p_sys1"), ("厂家设置", "p_factory"), ("故障记录", "fault"),
        ("返回", "run")]


def gen_menu():
    p = Page("menu", "")
    page_bg(p, "bg_menu")
    for i, (t, target) in enumerate(MENU):
        p.img(120 + (i % 3) * 256, 110 + (i // 3) * 104, 238, 86,
              f"menu_{i}", go_handler(target), pressed=f"menu_{i}")
    return p


FAULTS = [("出水超压", "2026/04/02 15:20:11", "2026/04/02 15:20:30"),
          ("变频器故障", "2026/04/02 15:18:02", "2026/04/02 15:18:40")]


def gen_fault():
    p = Page("fault", "")
    page_bg(p, "bg_fault")
    cells = []
    hdr = ["序号", "故障内容", "发生时间", "清除时间"]
    for c, t in enumerate(hdr, 1):
        cells.append(tag("cell", {"row": 1, "column": c, "text": esc(t)}))
    for r, f in enumerate(FAULTS, 2):
        for c, t in enumerate([r - 1, *f], 1):
            cells.append(tag("cell", {"row": r, "column": c, "text": esc(t)}))
    p.out.append("<table id=\"flt_tbl\" x=\"60\" y=\"96\" w=\"904\" h=\"320\" rows=\"8\" "
                 "columns=\"4\" col-widths=\"90,354,230,230\" col-aligns=\"center,left,center,center\" "
                 "row-height=\"40\" header=\"true\" grid=\"true\" "
                 "header-color=\"#62C8F0\" alternate-color=\"#EAF4FC\" background=\"#FFFFFF\" "
                 "border-color=\"#7FA8CC\" border-width=\"1\" color=\"#16243C\" "
                 "font=\"hzfont\" font_size=\"16\">"
                 + "".join(cells) + "</table>")
    p.img(300, 520, 180, 52, "flt_clear", "clear_faults", pressed="flt_clear")
    p.img(544, 520, 180, 52, "flt_back", "go_run", pressed="flt_back")
    p.text(830, 32, 180, 28, "", size=20, color="#C8F060", align="center", id="ft_cd")
    p.text(830, 60, 180, 28, "", size=20, color="#C8F060", align="center", id="ft_ct")
    return p


RESOURCES = []  # (id, file) 按使用顺序去重


def res(rid, fname):
    if (rid, fname) not in RESOURCES:
        RESOURCES.append((rid, fname))
    return rid


def collect_resources(pages_xml):
    """扫描已生成控件的 src 引用，收集资源清单（PNG/JPG 均按文件名引用）。"""
    used = []
    for _, xml in pages_xml:
        # tag() 输出时属性名下划线转连字符，XML 里是 src-pressed
        for m in re.finditer(r'(?:src|src-pressed)="([^"]+)"', xml):
            used.append(m.group(1))
    for u in dict.fromkeys(used):
        ext = ".jpg" if u.startswith("bg_") else ".png"
        res(u, u + ext)
    # 运行期动态切换的资源族一并声明（main.lua 切换泵态/开关/模式时需可寻址）
    for fn in sorted(os.listdir(ASSETS)):
        if DYN_KEEP.match(fn):
            res(fn.rsplit(".", 1)[0], fn)


# 运行期会动态切换的资源族（main.lua 切换状态/按下态），即使 XML 未直接引用也保留
DYN_KEEP = re.compile(r"^(pump_\d_\w+|tog_\w+|chip_\w+|sw_on|sw_off|run_\w+)\.png$")


def clean_assets():
    """删除 assets 中未被引用的残留文件（改名/换素材后的旧 PNG/JPG）。"""
    keep = {f for _, f in RESOURCES}
    for fn in os.listdir(ASSETS):
        if fn not in keep and not DYN_KEEP.match(fn):
            os.remove(os.path.join(ASSETS, fn))
            print("[clean] 移除未引用资源:", fn)


def gen_ids_lua(tog_map):
    os.makedirs(CODE, exist_ok=True)
    lines = ["-- 由 build_ui.py 自动生成：开关初态 / 下拉选项",
             "return {", "  tog = {"]
    for k, v in tog_map.items():
        lines.append(f"    [{quoteattr(k)}] = {'true' if v else 'false'},")
    lines.extend(["  },", "  sel = {"])
    for k, v in SEL_OPTS.items():
        if k == "__tog__":
            continue
        opts = ",".join(quoteattr(o) for o in v["opts"])
        lines.append(f"    [{quoteattr(k)}] = {{opts={{{opts}}}, cur={quoteattr(v['cur'])}}},")
    lines.extend(["  },", "}"])
    with open(os.path.join(CODE, "ui_ids.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    global SPEC
    SPEC = load_spec()
    xml_only = "--xml" in sys.argv
    if not xml_only:
        build_widgets(SPEC)
        build_pumps()
        build_backgrounds()
    pages = []
    pages.append(("run", gen_run().xml()))
    for page in SPEC["pages"]:
        node = gen_sched(page) if page.get("type") == "sched" else gen_form(page)
        pages.append((node.pid, node.xml()))
    pages.append(("menu", gen_menu().xml()))
    pages.append(("fault", gen_fault().xml()))
    collect_resources(pages)
    clean_assets()
    res_xml = "\n      ".join(tag("image", {"id": r[0], "src": r[1]}) for r in RESOURCES)
    doc = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<ui version="0.1" width="1024" height="600" entry="run">\n'
           "  <resources>\n      " + res_xml + "\n  </resources>\n  <pages>\n"
           + "\n".join(x for _, x in pages) + "\n  </pages>\n</ui>\n")
    os.makedirs(CODE, exist_ok=True)
    open(os.path.join(CODE, "main.xml"), "w", encoding="utf-8").write(doc)
    gen_ids_lua(SEL_OPTS.pop("__tog__", {}))
    wc = sum(x.count("<image ") + x.count("<label ") + x.count("<textarea ")
             + x.count("<keyboard ") + x.count("<table ") + x.count("<container ")
             for _, x in pages)
    print(f"[ok] main.xml 已生成：{len(pages)} 页 / 控件 {wc} (上限512) / 资源 {len(RESOURCES)} (上限256)")


if __name__ == "__main__":
    main()
