# -*- coding: utf-8 -*-
"""单一事实源素材生成器：按 design/spec.md 的色板/尺寸生成全部 PNG 到 code/res/。

用法： python tools/gen_assets.py
规则：文件名 <= 23 字节、扁平命名、PNG、圆角/渐变/质感全部烘进图里。
改视觉回 design/index.html + spec.md，再重跑本脚本，不许手改 main.xml 坐标。
"""
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "code", "res")
os.makedirs(OUT, exist_ok=True)

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit("需要 Pillow：pip install pillow")

# ---- 色板（与 spec.md 一一对应） ----
BG      = "#EEF1F5"
PANEL   = "#FFFFFF"
LINE    = "#C7CED8"
INK     = "#1F2937"
INK2    = "#5B6675"
MAIN    = "#1F6FEB"
RUN     = "#0FA968"
MANUAL  = "#E8A317"
STOP    = "#98A2B3"
FAULT   = "#E5484D"
MAINT   = "#EE7A17"

FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
def font(sz):
    try:
        return ImageFont.truetype(FONT_PATH, sz)
    except Exception:
        return ImageFont.load_default()

def new(w, h, color=(255, 255, 255, 0)):
    return Image.new("RGBA", (w, h), color)

def hx(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i+2], 16) for i in (0, 2, 4))

def save(im, name):
    # 保留 RGBA：流动帧 flow_a*/液位 lv*/维护罩 overlay 都依赖透明像素叠加在底图上。
    # 早先 convert("RGB") 会把透明拍成不透明白，导致自动态白底盖住整张工艺流程图。
    im.save(os.path.join(OUT, name))
    print("  gen", name, im.size, im.mode)

def rr(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)

def center_text(d, box, txt, f, fill):
    x0, y0, x1, y1 = box
    bb = d.textbbox((0, 0), txt, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text((x0 + (x1 - x0 - tw) / 2 - bb[0], y0 + (y1 - y0 - th) / 2 - bb[1]),
           txt, font=f, fill=fill)

# =====================================================================
# 1) 状态切换键：普通 / 按下 / 选中（6 键共用形状，颜色按状态）
#    btn_state_n.png / btn_state_p.png / btn_state_c.png
# =====================================================================
def gen_state_btn():
    """6 个状态键 × 三态，文字烘进图（静态文字不占活组件）"""
    W, H = 90, 48
    keys = (
        ("stop", "停机", STOP), ("local", "就地", MANUAL),
        ("remote", "远程", "#F0B429"), ("auto", "自动", RUN),
        ("fault", "故障", FAULT), ("maint", "维护", MAINT),
    )
    for name, txt, edge in keys:
        for suffix, bg, fg, border in (
            ("n", PANEL, edge, edge),
            ("p", "#E8EDF5", edge, edge),
            ("c", edge, "#FFFFFF", edge),
        ):
            im = new(W, H)
            d = ImageDraw.Draw(im)
            rr(d, (2, 2, W-3, H-3), 6, fill=hx(bg), outline=hx(border), width=3)
            center_text(d, (2, 2, W-3, H-3), txt, font(18), hx(fg))
            save(im, "sw_" + name + "_" + suffix + ".png")

# =====================================================================
# 2) 操作键：文字烘进图，普通 / 按下 / 禁用三态
# =====================================================================
def gen_op_btn():
    W, H = 84, 48
    keys = (
        ("p1", "泵1启停", MAIN), ("p2", "泵2启停", MAIN),
        ("mx", "搅拌机", MAIN), ("mode", "手/自动", MAIN),
        ("rst", "故障复位", FAULT),
    )
    for name, txt, edge in keys:
        pre = "btnrst" if name == "rst" else "btnop_" + name
        for suffix, bg, fg, border in (
            ("n", PANEL, edge, edge),
            ("p", "#E8EDF5", edge, edge),
            ("d", "#F2F4F7", "#AEB6C2", "#C7CED8"),
        ):
            im = new(W, H)
            d = ImageDraw.Draw(im)
            rr(d, (2, 2, W-3, H-3), 6, fill=hx(bg), outline=hx(border), width=3 if suffix != "d" else 2)
            center_text(d, (2, 2, W-3, H-3), txt, font(16), hx(fg))
            save(im, pre + "_" + suffix + ".png")

# =====================================================================
# 3) 设备状态徽章：6 色胶囊 bd_run/stop/manual/fault/lock/auto.png
# =====================================================================
def gen_badges():
    W, H = 76, 28
    for name, color in (
        ("bd_run", RUN), ("bd_stop", STOP), ("bd_manual", MANUAL),
        ("bd_fault", FAULT), ("bd_lock", MAINT), ("bd_auto", MAIN),
    ):
        im = new(W, H)
        d = ImageDraw.Draw(im)
        rr(d, (1, 1, W-2, H-2), 14, fill=hx(color))
        save(im, name + ".png")

# =====================================================================
# 4) 工艺流程 6 态底图：flow_stop/local/remote/auto/fault/maint.png
#    716 x 164，与 HTML 内联 SVG 同尺寸同坐标；虚线流动不烘进底图
# =====================================================================
def flow_pipeline(flow, accent):
    W, H = 716, 164
    im = new(W, H)
    d = ImageDraw.Draw(im)
    f16 = font(16); f20 = font(20)
    c = hx(flow); a = hx(accent)
    # 药剂罐
    d.rounded_rectangle((14, 18, 100, 122), radius=4, outline=c, width=3)
    d.line((20, 40, 94, 40), fill=c, width=3)
    center_text(d, (14, 126, 100, 146), "药剂罐", f16, hx(INK))
    center_text(d, (14, 145, 100, 164), "PAC / PAM", f16, hx(INK2))
    # 罐到双泵汇管
    d.line((100, 70, 124, 70), fill=c, width=4)
    d.line((124, 44, 124, 96), fill=c, width=4)
    d.line((124, 44, 142, 44), fill=c, width=4)
    d.line((124, 96, 142, 96), fill=c, width=4)
    # 计量泵 1
    d.rounded_rectangle((142, 20, 216, 68), radius=6, outline=c, width=3)
    d.ellipse((166, 31, 192, 57), outline=c, width=3)
    center_text(d, (166, 31, 192, 57), "P1", f16, a)
    center_text(d, (142, 70, 216, 90), "PAC 计量泵", f16, hx(INK))
    # 计量泵 2
    d.rounded_rectangle((142, 72, 216, 120), radius=6, outline=c, width=3)
    d.ellipse((166, 83, 192, 109), outline=c, width=3)
    center_text(d, (166, 83, 192, 109), "P2", f16, a)
    center_text(d, (142, 120, 216, 140), "PAM 计量泵", f16, hx(INK))
    # 泵到混合器汇管
    for seg in ((216,44,248,44),(216,96,248,96),(248,44,248,96),(248,70,282,70)):
        d.line(seg, fill=c, width=4)
    # 管道混合器
    d.rounded_rectangle((282, 28, 416, 112), radius=6, outline=c, width=3)
    d.line((306, 38, 392, 102), fill=c, width=3)
    d.line((392, 38, 306, 102), fill=c, width=3)
    d.ellipse((335, 56, 363, 84), outline=c, width=3)
    center_text(d, (282, 114, 416, 136), "管道混合器", f16, hx(INK))
    # 混合器到流量计
    d.line((416, 70, 466, 70), fill=c, width=4)
    # 出水流量计
    d.ellipse((466, 30, 546, 110), outline=c, width=3)
    center_text(d, (466, 40, 546, 70), "FT", f20, a)
    center_text(d, (466, 68, 546, 92), "m3/h", f16, hx(INK2))
    center_text(d, (466, 114, 546, 136), "出水流量计", f16, hx(INK))
    # 出水
    d.line((546, 70, 652, 70), fill=c, width=4)
    d.line((652, 70, 640, 62), fill=c, width=4)
    d.line((652, 70, 640, 78), fill=c, width=4)
    center_text(d, (654, 44, 716, 68), "出水", f16, hx(INK))
    center_text(d, (654, 72, 716, 96), "5 NTU", f16, hx(INK2))
    return im

def gen_flow():
    for name, flow, accent in (
        ("flow_stop",  "#B9C2CE", STOP),
        ("flow_local", "#D9B25C", MANUAL),
        ("flow_remote","#E8C15E", MANUAL),
        ("flow_auto",  RUN,       RUN),
        ("flow_fault", FAULT,     FAULT),
        ("flow_maint", MAINT,     MAINT),
    ):
        save(flow_pipeline(flow, accent), name + ".png")

# =====================================================================
# 5) 自动态流动虚线 4 帧（透明底，叠在流程底图上）flow_a0..3.png
# =====================================================================
def gen_flow_anim():
    W, H = 716, 164
    segments = [
        (100,70,124,70),(124,44,142,44),(124,96,142,96),
        (216,44,248,44),(216,96,248,96),(248,70,282,70),
        (416,70,466,70),(546,70,652,70),
    ]
    for k in range(4):
        im = new(W, H)
        d = ImageDraw.Draw(im)
        for (x0,y0,x1,y1) in segments:
            length = x1 - x0
            # 每帧把 9px 亮段沿管线推进 8px
            pos = (k * 8) % 17
            x = x0 + pos
            while x < x1:
                xe = min(x + 9, x1)
                d.line((x, y0, xe, y1), fill=hx(RUN), width=3)
                x += 17
        save(im, "flow_a%d.png" % k)

# =====================================================================
# 6) 0.5 秒判读辅助：数值辉光底 / 输出条槽 / 输出填充 / 数据块底
# =====================================================================
def gen_misc():
    # 输出条槽 180x10
    im = new(180, 10); d = ImageDraw.Draw(im)
    rr(d, (0,0,179,9), 5, fill=hx("#D8DEE7")); save(im, "bar_slot.png")
    # 输出填充 180x10（用 set_crop 裁宽度，绿底）
    im = new(180, 10); d = ImageDraw.Draw(im)
    rr(d, (0,0,179,9), 5, fill=hx(RUN)); save(im, "bar_fill.png")
    # 数据块底 212x84
    im = new(212, 84); d = ImageDraw.Draw(im)
    rr(d, (1,1,210,82), 6, fill=hx("#F7F9FC"), outline=hx("#E4E9F0"), width=2)
    save(im, "datablock.png")
    # 设备行底 224x68
    im = new(224, 68); d = ImageDraw.Draw(im)
    rr(d, (1,1,222,66), 6, fill=hx("#F7F9FC"), outline=hx("#E4E9F0"), width=2)
    save(im, "devrow.png")

# =====================================================================
# 6b) 状态徽标底板 6 态（152x56）与状态横幅底板 6 态（1000x36）
#     颜色随状态变 -> 必须有独立图，运行时 set_src 切换（2.11）
# =====================================================================
def tint(color, ratio=0.16):
    c = hx(color)
    return tuple(int(255 * (1 - ratio) + v * ratio) for v in c)

def gen_state_plates():
    states = (
        ("stop", STOP, "#E4E8EE", "#4B5563"),
        ("local", MANUAL, "#FFF3D6", "#8A5B00"),
        ("remote", "#F0B429", "#FFF6DC", "#8A5B00"),
        ("auto", RUN, "#DCF5E9", "#0A6B43"),
        ("fault", FAULT, "#FDE4E5", "#A3161B"),
        ("maint", MAINT, "#FDEAD8", "#9A4A05"),
    )
    # 徽标底板 152x56
    for name, edge, bg, _ in states:
        im = new(152, 56); d = ImageDraw.Draw(im)
        rr(d, (2,2,149,53), 6, fill=hx(bg), outline=hx(edge), width=3)
        save(im, "bdg_" + name + ".png")
    # 横幅底板 1000x36
    for name, edge, bg, _ in states:
        im = new(1000, 36); d = ImageDraw.Draw(im)
        rr(d, (2,2,997,33), 6, fill=hx(bg), outline=hx(edge), width=3)
        save(im, "bn_" + name + ".png")

# =====================================================================
# 7) 液位罐液面 5 档（74x76 透明底，按档裁高度）lv0..4.png
# =====================================================================
def gen_level():
    W, H = 74, 76
    heights = [76, 61, 45, 30, 15]
    for i, hh in enumerate(heights):
        im = new(W, H)
        d = ImageDraw.Draw(im)
        d.rectangle((0, H-hh, W-1, H-1), fill=hx("#2E7BE0"))
        d.rectangle((0, H-hh, W-1, H-hh+2), fill=hx("#5B9BF0"))
        save(im, "lv%d.png" % i)

def gen_overlay():
    """维护检修橙罩：半透明整块 + 挂牌卡片 + 文案，单图 set_hidden 即可"""
    W, H = 740, 344
    im = new(W, H)
    d = ImageDraw.Draw(im)
    # 半透明橙罩（RGBA 保留 alpha）
    d.rounded_rectangle((2, 2, W-3, H-3), radius=6,
                        fill=(238, 122, 23, 60), outline=hx(MAINT), width=4)
    # 挂牌卡片
    d.rounded_rectangle((W//2-150, H//2-60, W//2+150, H//2+60), radius=8,
                        fill=(255, 247, 238, 255), outline=hx(MAINT), width=5)
    center_text(d, (W//2-150, H//2-48, W//2+150, H//2+12), "挂牌", font(40), hx(MAINT))
    center_text(d, (W//2-150, H//2+12, W//2+150, H//2+52), "检修中 · 操作锁定", font(18), hx("#9A4A05"))
    im.save(os.path.join(OUT, "overlay_maint.png"))
    print("  gen overlay_maint.png", im.size)

if __name__ == "__main__":
    print("素材输出到:", OUT)
    gen_state_btn()
    gen_op_btn()
    gen_badges()
    gen_state_plates()
    gen_flow()
    gen_flow_anim()
    gen_misc()
    gen_level()
    gen_overlay()
    print("完成，共", len([f for f in os.listdir(OUT) if f.endswith(".png")]), "张 PNG")
