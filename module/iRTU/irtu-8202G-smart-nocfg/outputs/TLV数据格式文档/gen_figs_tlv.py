# -*- coding: utf-8 -*-
"""TLV 数据格式文档插图生成（6 幅，工业风，与代码分析文档同风格）。"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm

# 中文字体
for f in [r"C:\Windows\Fonts\simhei.ttf", r"C:\Windows\Fonts\msyh.ttc",
          r"C:\Windows\Fonts\msyhbd.ttc"]:
    if os.path.exists(f):
        fm.fontManager.addfont(f)
plt.rcParams["font.sans-serif"] = ["SimHei", "Microsoft YaHei"]
plt.rcParams["axes.unicode_minus"] = False

NAVY, AMBER, GOLDB = "#0f3550", "#d9a441", "#f7ecd4"
LINE, GREEN, RED, BLUE, GRAY = "#7d93a3", "#2e7d52", "#a94442", "#3a6ea5", "#eef2f4"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "images")
os.makedirs(OUT, exist_ok=True)


def new_ax(w, h, xlim, ylim):
    fig, ax = plt.subplots(figsize=(w, h))
    ax.set_xlim(*xlim)
    ax.set_ylim(*ylim)
    ax.axis("off")
    fig.subplots_adjust(left=0.01, right=0.99, top=0.99, bottom=0.01)
    return fig, ax


def box(ax, x, y, w, h, text, fc=GOLDB, ec=NAVY, fs=10, tc=NAVY, bold=False, lw=1.4):
    ax.add_patch(plt.Rectangle((x, y), w, h, facecolor=fc, edgecolor=ec, lw=lw, zorder=2))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs,
            color=tc, fontweight="bold" if bold else "normal", zorder=3)


def arrow(ax, x1, y1, x2, y2, color=NAVY, lw=1.4):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="-|>", color=color, lw=lw))


def save(fig, name):
    path = os.path.join(OUT, name)
    fig.savefig(path, bbox_inches="tight", facecolor="white", dpi=110)
    plt.close(fig)
    print("saved", path)


# ---------------------------------------------------------------- fig1 整包结构
def fig1():
    fig, ax = new_ax(13, 7.2, (0, 13), (0, 7.2))
    ax.text(6.5, 6.9, "AirCloud 上行报文整体结构：16 字节消息头 + N 个 TLV 字段", ha="center",
            fontsize=14.5, color=NAVY, fontweight="bold")

    # 消息头 16B（按字节比例 8/2/2/4）
    hx, hy, hh = 0.7, 5.3, 0.85
    ax.text(0.7, 6.35, "消息头（固定 16 字节）", fontsize=11, color=NAVY, fontweight="bold")
    segs = [(8, "设备 ID\n8 字节", "BCD 压缩 IMEI → 7 字节\n（1 字节设备类型 + 14 位数字）"),
            (2, "序列号\n2 字节", "大端 1~65535\n循环递增"),
            (2, "消息长度\n2 字节", "大端 = body 长度\n（TLV 总字节）"),
            (4, "flags 4 字节", "bit0-3 协议版本(=2)\nbit4 回复 / bit5 UDP / bit6 key")]
    x = hx
    total = 16
    for wb, t1, t2 in segs:
        w = wb / total * 11.0
        box(ax, x, hy, w, hh, t1, fc="#dce8f2", fs=10.5, bold=True)
        ax.text(x + w / 2, hy - 0.12, t2, ha="center", va="top", fontsize=8.6, color="#41586b")
        # 字节数标注
        ax.text(x + w / 2, hy + hh + 0.06, f"{wb}B", ha="center", fontsize=9, color=AMBER,
                fontweight="bold")
        x += w
    ax.plot([hx, hx + 11.0], [hy, hy], color=NAVY, lw=1.6)
    ax.text(hx + 11.15, hy + hh / 2, "16B", fontsize=10, color=NAVY, fontweight="bold")

    # body：TLV 串
    by = 2.6
    ax.text(0.7, by + 1.8, "消息体 body（msg_length 字节）= 顺序排列的 1~N 个 TLV 字段", fontsize=11,
            color=NAVY, fontweight="bold")
    tl = [("TLV-1", "field_type 2B\nlength 2B\nvalue N1B", 3.1),
          ("TLV-2", "field_type 2B\nlength 2B\nvalue N2B", 3.1),
          ("…", "", 0.8),
          ("TLV-N", "field_type 2B\nlength 2B\nvalue NB", 3.1)]
    x = hx
    for name, txt, w in tl:
        if name == "…":
            ax.text(x + w / 2, by + 0.6, "…", ha="center", fontsize=20, color=NAVY)
            x += w
            continue
        box(ax, x, by, w, 1.5, "", fc=GRAY)
        ax.text(x + w / 2, by + 1.32, name, ha="center", fontsize=10.5, color=NAVY, fontweight="bold")
        ax.text(x + w / 2, by + 0.62, txt, ha="center", va="center", fontsize=9.3, color="#26323b")
        x += w
    ax.text(x + 0.25, by + 0.75, "大端序（Big-Endian）\n无填充、无对齐、紧凑排列", fontsize=9.5,
            color=GREEN, va="center")

    # 约束提示条
    box(ax, 0.7, 1.4, 11.6, 0.85,
        "约束：消息体（全部 TLV 字节之和）≤ 1400 字节；本固件最大字段 1293 = 4B 头 + 900B = 904B，为整包留足余量",
        fc="#fdf6e3", ec=AMBER, fs=10.5, tc="#5a5343")
    ax.text(6.5, 0.75, "上行仅此一种报文形态（037 起）：定位帧 / 指令应答帧(1296~1299) / 兜底状态帧(799+782+1290+1027)，均 = 16B 消息头 + N×TLV",
            ha="center", fontsize=10, color=NAVY,
            bbox=dict(boxstyle="round,pad=0.45", fc="#e8f1ec", ec=GREEN, lw=1.2))
    save(fig, "fig1_frame.png")


# ---------------------------------------------------------------- fig2 TLV 结构
def fig2():
    fig, ax = new_ax(13, 7.0, (0, 13), (0, 7.0))
    ax.text(6.5, 6.7, "TLV 通用结构与 field_type 位域", ha="center", fontsize=14.5,
            color=NAVY, fontweight="bold")

    # 左：TLV 布局
    lx, ly = 0.7, 4.5
    ax.text(0.7, 6.15, "每个 TLV 字段的字节布局", fontsize=11.5, color=NAVY, fontweight="bold")
    box(ax, lx, ly, 1.9, 1.15, "field_type\n2 字节", fc="#dce8f2", fs=10.5, bold=True)
    box(ax, lx + 1.9, ly, 1.9, 1.15, "length\n2 字节", fc="#fdebd3", fs=10.5, bold=True)
    box(ax, lx + 3.8, ly, 2.6, 1.15, "value\nN 字节", fc="#e2efdf", fs=10.5, bold=True)
    ax.text(lx + 0.95, ly - 0.18, "bit15-12=data_type\nbit11-0=field_meaning", ha="center",
            va="top", fontsize=8.8, color=BLUE)
    ax.text(lx + 2.85, ly - 0.18, "value 的字节数\n大端", ha="center", va="top", fontsize=8.8, color="#8a5a13")
    ax.text(lx + 5.1, ly - 0.18, "由 data_type 决定编码\n（见数据类型一节）", ha="center", va="top",
            fontsize=8.8, color=GREEN)

    # field_type 位域放大图
    zx, zy = 0.7, 1.75
    ax.text(0.7, 3.45, "field_type 16bit 位域（大端发送）", fontsize=11.5, color=NAVY, fontweight="bold")
    labels = [("15", "data_type\nbit15"), ("14", ""), ("13", ""), ("12", "bit12"),
              ("11", "field_meaning ← bit11"), ("10", ""), ("9", ""), ("8", ""),
              ("7", ""), ("6", ""), ("5", ""), ("4", ""), ("3", ""), ("2", ""),
              ("1", ""), ("0", "bit0")]
    wbit = 0.5
    for i, (bit, lab) in enumerate(labels):
        fc = "#cfe0ee" if i < 4 else "#fdf3dd"
        box(ax, zx + i * wbit, zy, wbit, 0.85, bit, fc=fc, fs=9)
    ax.text(zx + 2 * wbit, zy + 1.02, "数据类型（0~5）", ha="center", fontsize=9.5, color=BLUE,
            fontweight="bold")
    ax.text(zx + 10 * wbit, zy + 1.02, "字段含义编号（0~4095）", ha="center", fontsize=9.5,
            color="#8a5a13", fontweight="bold")
    box(ax, zx, 0.35, 8.0, 0.95,
        "组包：field_type = data_type × 4096 + (field_meaning % 4096)\n解析：type = field_type >> 12    field = field_type & 0xFFF",
        fc="#f2f4f6", ec=LINE, fs=9.3, tc="#26323b")

    # 右：实例表
    ex, ey = 9.2, 5.0
    ax.text(ex, ey + 0.75, "field_type 实例（十六进制字节）", fontsize=11.5, color=NAVY, fontweight="bold")
    rows = [("1290 上报模式状态", "INTEGER(0)", "0x050A", "05 0A"),
            ("512 GNSS 经度", "ASCII(3)", "0x3200", "32 00"),
            ("799 电池电压", "INTEGER(0)", "0x031F", "03 1F"),
            ("1027 固件版本", "ASCII(3)", "0x3403", "34 03"),
            ("1296 应答 msg_id", "ASCII(3)", "0x3510", "35 10"),
            ("1298 应答结果码", "INTEGER(0)", "0x0512", "05 12"),
            ("1293 三轴流", "BINARY(4)", "0x450D", "45 0D"),
            ("1295 实时1s三轴流", "BINARY(4)", "0x450F", "45 0F")]
    ax.text(ex + 0.1, ey + 0.12, "字段", fontsize=9.5, color=NAVY, fontweight="bold")
    ax.text(ex + 1.8, ey + 0.12, "类型", fontsize=9.5, color=NAVY, fontweight="bold")
    ax.text(ex + 2.9, ey + 0.12, "值", fontsize=9.5, color=NAVY, fontweight="bold")
    ax.text(ex + 3.6, ey + 0.12, "字节", fontsize=9.5, color=NAVY, fontweight="bold")
    for i, (f, t, v, b) in enumerate(rows):
        yy = ey - 0.42 * (i + 1)
        ax.text(ex + 0.1, yy, f, fontsize=9.0, color="#26323b")
        ax.text(ex + 1.8, yy, t, fontsize=9.0, color=BLUE)
        ax.text(ex + 2.9, yy, v, fontsize=9.0, color="#26323b")
        ax.text(ex + 3.6, yy, b, fontsize=9.0, color=RED, fontweight="bold",
                )
    save(fig, "fig2_tlv_head.png")


# ---------------------------------------------------------------- fig3 数据类型
def fig3():
    fig, ax = new_ax(13, 6.9, (0, 13), (0, 6.9))
    ax.text(6.5, 6.6, "六种数据类型（DATA_TYPES，嵌入 field_type 高 4bit）", ha="center",
            fontsize=14.5, color=NAVY, fontweight="bold")
    cards = [
        ("INTEGER = 0", "整数，4 字节大端（无符号编码）", "value=1  →  00 00 00 01\nvalue=3850 → 00 00 0F 0A", "#dce8f2"),
        ("FLOAT = 1", "×1000 取整后按 4 字节大端\n（非 IEEE 754！收发两端同约定）", "value=25.5 → 25500\n→ 00 00 63 9C", "#fdebd3"),
        ("BOOLEAN = 2", "1 字节：0x00 假 / 0x01 真", "true → 01", "#e2efdf"),
        ("ASCII = 3", "字符串原样字节（UTF-8）", "\"ok\" → 6F 6B\n\"121.53600\" → 9 字节", "#f3e8f1"),
        ("BINARY = 4", "二进制原样字节（1293/1294/1295 用）", "900B 三轴流原样放入\n不转义、无填充", "#e8e4f3"),
        ("UNICODE = 5", "Unicode 字符串原样字节（本固件未用）", "—", "#eeeeee"),
    ]
    x0, y0, cw, ch, gx, gy = 0.7, 3.9, 3.75, 2.45, 0.15, 0.4
    for i, (name, desc, ex, fc) in enumerate(cards):
        cx = x0 + (i % 3) * (cw + gx)
        cy = y0 - (i // 3) * (ch + gy)
        box(ax, cx, cy, cw, ch, "", fc=fc, ec=NAVY)
        ax.text(cx + cw / 2, cy + ch - 0.38, name, ha="center", fontsize=11.5, color=NAVY,
                fontweight="bold")
        ax.text(cx + cw / 2, cy + ch - 0.98, desc, ha="center", va="center", fontsize=9.2,
                color="#26323b")
        ax.text(cx + cw / 2, cy + 0.42, ex, ha="center", va="center", fontsize=9.2, color=RED,
                )
    box(ax, 0.7, 0.2, 11.6, 0.72,
        "注意：encode_value 对空 ASCII 返回空 → build_tlv 失败 → 整个字段被跳过（业务层已按“空值一律不上报”规避）",
        fc="#fdf6e3", ec=AMBER, fs=10.5, tc="#5a5343")
    save(fig, "fig3_datatypes.png")


# ---------------------------------------------------------------- fig4 1293
def fig4():
    fig, ax = new_ax(13, 7.6, (0, 13), (0, 7.6))
    ax.text(6.5, 7.3, "字段 1293：20Hz 三轴原始数据流（BINARY，12bit 紧凑编码）", ha="center",
            fontsize=14.5, color=NAVY, fontweight="bold")

    # 流程
    steps = [("DA221 中断+定时\n20Hz 采样", "#dce8f2"),
             ("每样本 x/y/z\n12bit 原始计数\n暂存 6B int16", "#e8e4f3"),
             ("滚动缓冲\n≤200 样本\n(10 秒窗口)", "#fdebd3"),
             ("每 2 样本\n6×12bit → 72bit\n→ 9 字节", "#e2efdf"),
             ("100 组 × 9B\n= 900 字节\nTLV 1293", "#f3e8f1")]
    x = 0.7
    for i, (t, fc) in enumerate(steps):
        box(ax, x, 5.55, 2.15, 1.25, t, fc=fc, fs=9.5)
        if i < len(steps) - 1:
            arrow(ax, x + 2.15, 6.17, x + 2.45, 6.17)
        x += 2.45

    # 72bit 位条
    ax.text(0.7, 5.05, "每 2 个样本 = 9 字节 = 连续 72bit 位流（每值 12bit，MSB 在前）", fontsize=11,
            color=NAVY, fontweight="bold")
    bits = [("x1", "#cfe0ee"), ("y1", "#fdebd3"), ("z1", "#e2efdf"),
            ("x2", "#cfe0ee"), ("y2", "#fdebd3"), ("z2", "#e2efdf")]
    bx, bw = 0.7, 1.55
    for i, (t, fc) in enumerate(bits):
        box(ax, bx + i * bw, 4.0, bw, 0.8, f"{t}  (12bit)", fc=fc, fs=10.5, bold=True)
    ax.text(bx + 6 * bw + 0.2, 4.4, "= 9 字节", fontsize=11, color=NAVY, fontweight="bold", va="center")

    # pack12 公式 + 字节示例
    ax.text(0.7, 3.55, "pack12(a, b)：两个 12bit 值装入 3 字节", fontsize=11, color=NAVY, fontweight="bold")
    box(ax, 0.7, 2.35, 5.9, 1.05,
        "byte0 = (a >> 4) & 0xFF\nbyte1 = ((a & 0xF) << 4) | ((b >> 8) & 0xF)\nbyte2 = b & 0xFF",
        fc="#f2f4f6", ec=LINE, fs=9.6, tc="#26323b")
    ax.text(0.7, 2.05, "示例：x1=-1, y1=2047, z1=0, x2=-2048, y2=1, z2=-1", fontsize=10, color="#26323b")
    box(ax, 0.7, 1.25, 5.9, 0.62,
        "FF F7 FF   00 08 00   00 1F FF      （9 字节）",
        fc="#fff", ec=NAVY, fs=10.5, tc=RED)

    # 解码要点
    dx = 7.1
    ax.text(dx, 3.55, "服务端解码步骤", fontsize=11, color=NAVY, fontweight="bold")
    steps2 = ["① 每 9 字节一组，读成连续 72bit 位流（大端）",
              "② 按 12bit 切出 6 个无符号值 → x1,y1,z1,x2,y2,z2",
              "③ 符号还原：值 ≥ 0x800 则 减 4096（12bit 两补码）",
              "④ 得到 -2048~2047 原始计数；±2g 量程下\ng = 计数 / 1024（1LSB ≈ 0.977mg）"]
    y = 3.15
    for s in steps2:
        box(ax, dx, y - 0.18, 5.3, 0.78 if "\n" in s else 0.5, s, fc=GRAY, ec=LINE, fs=9.3,
            tc="#26323b")
        y -= (1.0 if "\n" in s else 0.72)
    box(ax, 0.7, 0.3, 11.7, 0.6,
        "上报条件：GNSS 开启且非实时上报；TLV 总长 4 + 900 = 904 字节（≤ 1400 上限）；样本数为奇数时丢弃最旧 1 个样本",
        fc="#fdf6e3", ec=AMBER, fs=10, tc="#5a5343")
    save(fig, "fig4_1293.png")


# ---------------------------------------------------------------- fig5 1294
def fig5():
    fig, ax = new_ax(13, 7.2, (0, 13), (0, 7.2))
    ax.text(6.5, 6.9, "字段 1294：GNSS 1Hz 定位五元组流（BINARY，int16 差值编码）", ha="center",
            fontsize=14.5, color=NAVY, fontweight="bold")

    # 每样本 10B 布局
    ax.text(0.7, 6.3, "每个样本 10 字节 = 5 个有符号 int16（大端，string.pack \">i2i2i2i2i2\"），时间正序", fontsize=11,
            color=NAVY, fontweight="bold")
    segs = [("经度差\ndLng", "#cfe0ee"), ("纬度差\ndLat", "#fdebd3"), ("速度\nspeed", "#e2efdf"),
            ("航向\ncourse", "#f3e8f1"), ("海拔\nalt", "#e8e4f3")]
    x = 0.7
    for t, fc in segs:
        box(ax, x, 5.15, 2.1, 1.0, t, fc=fc, fs=10.5, bold=True)
        ax.text(x + 1.05, 4.92, "2 字节 int16", ha="center", va="top", fontsize=8.8, color="#41586b")
        x += 2.1
    ax.text(x + 0.15, 5.65, "× 最多 10 个样本\n= 最多 100 字节", fontsize=9.8, color=GREEN, va="center")

    # 编码公式表
    ax.text(0.7, 4.25, "编码公式（ref = 本报文 512/513 字段上报的坐标）", fontsize=11, color=NAVY,
            fontweight="bold")
    rows = [("dLng", "(样本经度 - ref_lng) × 100000", "1LSB = 0.00001° ≈ 1.1m，范围 ±0.33°"),
            ("dLat", "(样本纬度 - ref_lat) × 100000", "1LSB = 0.00001° ≈ 1.1m，范围 ±0.33°"),
            ("speed", "km/h × 10（RMC 节值 × 1.852 × 10）", "1LSB = 0.1km/h"),
            ("course", "度 × 10", "1LSB = 0.1°（静止时航向不可信）"),
            ("alt", "米（整数）", "1LSB = 1m")]
    y = 3.85
    hdr = [("分量", 0.9), ("编码", 4.6), ("分辨率 / 范围", 8.6)]
    for t, cx in hdr:
        ax.text(cx, y, t, fontsize=9.8, color=NAVY, fontweight="bold")
    y -= 0.42
    for i, (a, b, c) in enumerate(rows):
        fc = GRAY if i % 2 == 0 else "#ffffff"
        ax.add_patch(plt.Rectangle((0.7, y - 0.11), 11.7, 0.42, facecolor=fc, edgecolor="none", zorder=1))
        ax.text(0.9, y, a, fontsize=9.6, color=BLUE, fontweight="bold", zorder=2)
        ax.text(4.6, y, b, fontsize=9.6, color="#26323b", zorder=2)
        ax.text(8.6, y, c, fontsize=9.6, color="#41586b", zorder=2)
        y -= 0.42

    # 字节示例
    ax.text(0.7, 1.35, "示例：ref=(lat 31.22610, lng 121.53600)，样本 lng=121.5372, lat=31.22565, "
                       "速度=12.3km/h, 航向=275.6°, 海拔=1050m", fontsize=9.8, color="#26323b")
    box(ax, 0.7, 0.55, 11.7, 0.62,
        "dLng=+120 → 00 78    dLat=-45 → FF D3    speed=123 → 00 7B    course=2756 → 0A C4    alt=1050 → 04 1A",
        fc="#fff", ec=NAVY, fs=10.3, tc=RED)
    ax.text(0.7, 0.18, "服务端还原：经度 = ref_lng + dLng ÷ 100000（其他分量同逆向换算）；无 fix 期间缓冲为空，整字段缺席",
            fontsize=9.5, color="#5a5343")
    save(fig, "fig5_1294.png")


# ---------------------------------------------------------------- fig6 字段使用矩阵
def fig6():
    fig, ax = new_ax(13, 8.2, (0, 13), (0, 8.2))
    ax.text(6.5, 7.9, "field_meaning 分区与本固件各上报状态下字段出现矩阵", ha="center",
            fontsize=14.5, color=NAVY, fontweight="bold")

    # 分区条（等宽展示，区间号标注在条内）
    zones = [(16, 32, "控制信令\n16-31", "#cfe0ee"), (256, 512, "传感采集\n256-511", "#e8e4f3"),
             (512, 768, "GNSS 定位\n512-767", "#e2efdf"), (768, 1024, "设备参数\n768-1023", "#fdebd3"),
             (1024, 1280, "软件/内存\n1024-1279", "#f3e8f1"), (1280, 1535, "通用测试\n1280-1535", "#fdf3dd")]
    zx, zw = 0.7, 11.7
    for lo, hi, t, fc in zones:
        w = zw / len(zones)
        box(ax, zx, 6.55, w - 0.06, 0.95, t, fc=fc, fs=9.5, bold=True)
        zx += w
    ax.text(0.7, 6.2, "（分区等宽示意，实际区段宽度不同：控制/通用各 16/256 个编号，仅示意边界）", fontsize=8.5, color="#7d93a3")

    # 矩阵
    ax.text(6.5, 5.75, "字段出现矩阵：●=携带  ○=条件携带  —=不携带", ha="center", fontsize=10.5,
            color="#41586b")
    rows = [
        ("1290 上报模式状态", "●", "●", "●"),
        ("799 VOLTAGE 电池电压 mV", "●", "●", "●"),
        ("1291 charging 充电状态", "●", "●", "●"),
        ("782 SIGNAL_STRENGTH_4G 信号CSQ", "●", "●", "●"),
        ("512/513 经纬度（ASCII）", "●", "●", "●"),
        ("519 LOCATION_METHOD 定位方式", "●", "●", "●"),
        ("772 SERVING_CELL 驻留频段", "●", "●", "●"),
        ("774/776/779/783 型号/开机原因/唤醒间隔/ICCID", "●", "●", "●"),
        ("1292 单点三轴 \"x,y,z\"(g)", "●", "—", "●"),
        ("1293 20Hz 三轴流（12bit）", "—", "●", "—"),
        ("1294 1Hz NMEA 五元组流", "—", "●", "—"),
        ("1295 实时1s三轴流（12bit）", "—", "—", "●"),
        ("515/516/517 卫星 CN/总数/可见数", "○", "○", "○"),
        ("1027 FIRMWARE_VERSION 版本号", "●", "—", "—"),
    ]
    col_x = [8.9, 9.9, 10.9]
    heads = ["GNSS 关\n(300s 帧)", "GNSS 开\n(10s 帧)", "实时上报\n(1s 帧)"]
    for cx, h in zip(col_x, heads):
        ax.text(cx, 5.32, h, ha="center", fontsize=9, color=NAVY, fontweight="bold")
    y = 5.0
    for i, (name, a, b, c) in enumerate(rows):
        if i % 2 == 0:
            ax.add_patch(plt.Rectangle((0.7, y - 0.115), 11.7, 0.26, facecolor=GRAY,
                                       edgecolor="none", zorder=1))
        ax.text(0.9, y, name, fontsize=9.0, color="#26323b", zorder=2)
        mark = {"●": ("●", GREEN), "○": ("○", AMBER), "—": ("—", "#a0aab2")}
        for cx, v in zip(col_x, (a, b, c)):
            t, cc = mark[v]
            ax.text(cx, y, t, ha="center", fontsize=10.5, color=cc, zorder=2)
        y -= 0.31
    ax.text(0.9, y - 0.14, "○ 515/516/517：仅 gps_status=2（GNSS 定位成功，含沿用最近成功点）时携带",
            fontsize=8.8, color="#8a5a13")
    ax.text(0.9, y - 0.34, "1027：仅 GNSS 关闭态携带 —— 静默期让服务端持续感知固件版本（如判断升级是否生效）",
            fontsize=8.8, color="#8a5a13")
    ax.text(0.9, y - 0.54, "1295：实时 1s 帧携带最近 1 秒 20 样本（12bit 编码 90B），格式与 1293 完全相同",
            fontsize=8.8, color="#8a5a13")
    ax.text(0.9, y - 0.74, "另有两类独立帧：指令应答帧 1296~1299（每条下行命令一条）；兜底状态帧 799+782+1290+1027（静默≥300s 保活）",
            fontsize=8.8, color="#8a5a13")
    save(fig, "fig6_fields.png")


if __name__ == "__main__":
    fig1()
    fig2()
    fig3()
    fig4()
    fig5()
    fig6()
    print("ALL DONE")
