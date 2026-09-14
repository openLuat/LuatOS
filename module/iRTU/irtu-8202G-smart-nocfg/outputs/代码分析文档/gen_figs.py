# -*- coding: utf-8 -*-
"""生成代码分析文档插图（工业风浅色：白底/深蓝 #0f3550/琥珀 #d9a441）。直线箭头布局，规避穿越。"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
from matplotlib import font_manager

for f in [r"C:\Windows\Fonts\simhei.ttf", r"C:\Windows\Fonts\msyh.ttc"]:
    try:
        font_manager.fontManager.addfont(f)
    except Exception:
        pass
plt.rcParams["font.sans-serif"] = ["SimHei", "Microsoft YaHei"]
plt.rcParams["axes.unicode_minus"] = False

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "images")
os.makedirs(OUT, exist_ok=True)

NAVY, BLUE = "#0f3550", "#17506e"
AMBER, GOLDB = "#d9a441", "#fdf6e3"
GREYB, GREYT, LINE = "#f2f4f6", "#8a97a0", "#b9c4cc"
WHITE, RED = "#ffffff", "#b23a3a"
L1FC = "#f4f8fb"

def new_ax(w, h, xlim, ylim):
    fig, ax = plt.subplots(figsize=(w, h), dpi=150)
    ax.set_xlim(*xlim); ax.set_ylim(*ylim); ax.axis("off")
    return fig, ax

def box(ax, x, y, w, h, text, fc=WHITE, ec=NAVY, fs=9.5, tc=NAVY, bold=False,
        lw=1.4, ha="center", va="center", ls="-"):
    p = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.025",
                       fc=fc, ec=ec, lw=lw, linestyle=ls, zorder=3)
    ax.add_patch(p)
    ax.text(x + w / 2, y + h / 2, text, ha=ha, va=va, fontsize=fs, color=tc, zorder=4,
            fontweight="bold" if bold else "normal")
    return (x, y, w, h)

def arrow(ax, x1, y1, x2, y2, color=NAVY, lw=1.5, style="-|>", ls="-", ms=13):
    a = FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style, mutation_scale=ms,
                        color=color, lw=lw, linestyle=ls, zorder=2)
    ax.add_patch(a)

def save(fig, name):
    fig.savefig(os.path.join(OUT, name), bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("saved", name)

# ============ fig1 分层架构 ============
def fig1():
    fig, ax = new_ax(13.4, 8.6, (0, 13.4), (0, 8.6))
    ax.text(6.1, 8.28, "LuatOS iRTU-8202G 固件软件分层架构（事件驱动 + 协程）",
            ha="center", fontsize=13.5, color=NAVY, fontweight="bold")
    LX, LW = 0.2, 11.35   # 层盒范围
    # L0
    box(ax, LX, 6.88, LW, 1.0, "", fc="#eef4f8", ec=NAVY, lw=1.7)
    ax.text(0.45, 7.38, "L0 入口层", fontsize=11, color=NAVY, fontweight="bold", va="center")
    box(ax, 2.15, 6.99, 2.9, 0.78, "main.lua\n启动分发 / FOTA / SIM1", fs=8.3)
    box(ax, 5.25, 6.99, 2.5, 0.78, "app.lua\n装配 / 模式分发", fs=8.3)
    box(ax, 7.95, 6.99, 3.55, 0.78, "lowpower/\ndrv_normal·lowpower·psm", fs=8.0)
    # L1
    box(ax, LX, 5.12, LW, 1.36, "", fc="#eef4f8", ec=NAVY, lw=1.7)
    ax.text(0.45, 5.78, "L1 业务\n核心层", fontsize=11, color=NAVY, fontweight="bold", va="center")
    box(ax, 1.95, 5.26, 2.6, 1.08, "active_mode\nGNSS 三态主循环\nTLV/JSON 组装", fs=7.9)
    box(ax, 4.7, 5.26, 2.0, 1.08, "create\n云通道管理\nTCP/MQTT/AirCloud", fs=7.6)
    box(ax, 6.85, 5.26, 1.85, 1.08, "remote\n下行命令 11 种", fs=8.0)
    box(ax, 8.85, 5.26, 1.7, 1.08, "location\n定位采集\n(1294 源)", fs=7.8)
    box(ax, 10.7, 5.26, 1.15, 1.08, "battery\n电池", fs=8.0)
    # L2
    box(ax, LX, 3.28, LW, 1.36, "", fc="#eef4f8", ec=NAVY, lw=1.7)
    ax.text(0.45, 3.94, "L2 支撑\n服务层", fontsize=11, color=NAVY, fontweight="bold", va="center")
    box(ax, 1.75, 3.42, 1.45, 1.08, "config\n配置装载", fs=7.8)
    box(ax, 3.3, 3.42, 1.45, 1.08, "cfg_fetch\n本地配置", fs=7.8)
    box(ax, 4.85, 3.42, 1.45, 1.08, "kvstore\nfskv 键值", fs=7.8)
    box(ax, 6.4, 3.42, 1.45, 1.08, "tools\nLED 状态机", fs=7.8)
    box(ax, 7.95, 3.42, 1.7, 1.08, "boot_lbs_report\n开机 LBS", fs=7.8)
    box(ax, 9.75, 3.42, 1.15, 1.08, "update\nFOTA", fs=7.8)
    box(ax, 11.0, 3.42, 1.15, 1.08, "charge", fs=8.0)
    # L3
    box(ax, LX, 1.55, LW, 1.25, "", fc=GREYB, ec=GREYT, lw=1.3)
    ax.text(0.45, 2.16, "L3 底层库 lib\n(黑盒驱动，本项目不改)", fontsize=9.5, color=GREYT,
            fontweight="bold", va="center")
    ax.text(2.0, 2.18, "excloud(AirCloud 协议)  exmtn(运维日志)  exvib(DA221)  exs_yhm2712a(充电IC)\n"
            "exair153x_wdt(看门狗)  airlbs/lbsLoc2(基站定位)  libfota2/3  db  libnet  httpplus\n"
            "dtulib  factory(产测)   modules/exgnss = libgnss 内置库包装层(L2/L3 边界)",
            fontsize=7.8, color="#5a6772", ha="left", va="center")
    # 右侧事件总线
    box(ax, 12.15, 0.5, 0.85, 7.6, "sys\n事件\n总线\n\npublish\nsubscribe\nwaitUntil",
        fc=GOLDB, ec=AMBER, lw=1.8, fs=8.5)
    for ly in (7.38, 5.8, 3.96, 2.15):
        arrow(ax, LX + LW, ly, 12.1, ly, color=AMBER, lw=1.1)
    ax.text(6.1, 0.22, "模块间通过 sys 事件解耦（不互相 require），配合协程 waitUntil 阻塞等待",
            ha="center", fontsize=9, color=GREYT)
    save(fig, "fig1_arch.png")

# ============ fig2 开机启动流程 ============
def fig2():
    fig, ax = new_ax(13, 10.4, (0, 13), (0, 10.4))
    ax.text(6.5, 9.85, "开机启动流程（BOOT_MODE=2 强制正常模式）", ha="center", fontsize=14,
            color=NAVY, fontweight="bold")
    steps = [
        ("main.lua", "上电 → fskv.init() → mobile.simid(1) 固定 SIM1 → update.init() 启动 FOTA（开机一次 + 每 8h）"),
        ("main.lua / cfg_fetch", "cfg_fetch.init() → db 读 /luadb/air8201.cfg，判定是否含有效 gnss.network 通道配置"),
        ("main.lua", "有有效配置 → config.load_from_server + remote.init() + create.start(sheet)\n无配置 → create.start({gnss={network=config.DEFAULT_NETWORK}})（通道1 AirCloud/TCP）"),
        ("app.lua", "app.start()（延迟 2s）→ app_task：读唤醒原因 → init_all_modules()\n（kvstore → battery → location → gsensor → charge → air153c_wdt → remote → lowpower_app）"),
        ("app.lua / active_mode", "work_mode 校验：旧设备存 -1 → 强制 set_work_mode(2) 寻宠模式\nrequire('active_mode')：模块加载即 sys.taskInit(main_loop) 进入三态主循环"),
        ("main.lua / boot_lbs_report", "boot_lbs_report.start()：独立任务——联网 + 云连接成功后先做一次 LBS 定位并双通道上报"),
        ("create.lua / excloud", "create 通道 task：等 IP_READY → aircloudTask 注册双发送订阅 → excloud.setup/open\n→ getip → TCP → 鉴权(字段16) → 服务器回字段17 → publish CLOUD_CONNECTED"),
        ("active_mode.lua", "main_loop：waitUntil(CLOUD_CONNECTED, 30s) → report_startup() 开机上报\n→ 记 boot_ticks（开机 300s GNSS 常开窗口基准）→ 进入三态节流循环"),
    ]
    x_line = 1.15
    ax.plot([x_line, x_line], [0.5, 9.55], color=NAVY, lw=1.6, zorder=1)
    y = 9.05
    for i, (owner, txt) in enumerate(steps):
        nlines = txt.count("\n") + 1
        h = 0.32 + nlines * 0.30
        cy = y - h / 2
        c = plt.Circle((x_line, cy), 0.17, fc=AMBER if i % 2 == 0 else NAVY, ec="none", zorder=4)
        ax.add_patch(c)
        ax.text(x_line, cy, str(i + 1), color="white", fontsize=9.5, ha="center", va="center",
                zorder=5, fontweight="bold")
        box(ax, 1.7, y - h, 10.9, h, "", fc=WHITE if i % 2 == 0 else "#f4f8fb", ec=NAVY, lw=1.3)
        ax.text(1.95, y - h / 2 + 0.02, f"[{owner}]  {txt}", ha="left", va="center",
                fontsize=8.7, color=NAVY, zorder=4)
        if i < len(steps) - 1:
            arrow(ax, x_line, y - h - 0.06, x_line, y - h - 0.28, color=NAVY, lw=1.2)
        y = y - h - 0.36
    save(fig, "fig2_boot_flow.png")

# ============ fig3 连接鉴权与上下行（左右双列） ============
def fig3():
    fig, ax = new_ax(13.4, 10.4, (0, 13.4), (0, 10.4))
    ax.text(6.7, 10.05, "AirCloud 通道：连接鉴权 + 上下行数据流（TCP 承载）", ha="center",
            fontsize=14, color=NAVY, fontweight="bold")
    # 泳道底
    box(ax, 0.15, 0.3, 6.1, 9.3, "", fc="#f4f8fb", ec=NAVY, lw=1.4)
    box(ax, 7.15, 0.3, 6.1, 9.3, "", fc=GOLDB, ec=AMBER, lw=1.4)
    ax.text(3.2, 9.25, "设备侧：create.lua → lib/excloud.lua", ha="center", fontsize=10.5,
            color=NAVY, fontweight="bold")
    ax.text(10.2, 9.25, "AirCloud 服务器 / 合宙云", ha="center", fontsize=10.5, color="#7a5c10",
            fontweight="bold")

    # 设备列步骤（下行→上）
    dsteps = [
        ("D1 连接前注册双发送订阅", "AIRCLOUD_SEND_1 ← TLV 直发\nNET_SENT_RDY_1 ← JSON 封装\nRANDOM_DATA(1281) 转发", 7.55),
        ("D2 excloud.setup / open", "transport=tcp · use_getip=true\nauto_reconnect · mtn_log 开启", 5.55),
        ("D3 上报数据组装", "active_mode：JSON 报文\n+ build_aircloud_tlv 数组\n1293/1294 二进制流", 2.45),
    ]
    for t, sub, y in dsteps:
        box(ax, 0.4, y + 1.6, 5.5, 0.55, t, fc=NAVY, ec=NAVY, fs=8.4, tc="white", bold=True)
        box(ax, 0.4, y, 5.5, 1.5, sub, fs=7.9)
    # 服务器列步骤（下→上）
    ssteps = [
        ("S1 getip 返回", "host / port / auth_key\n(HTTP POST 接口)", 7.75),
        ("S2 校验鉴权字段16", "auth_key-IMEI-MUID\n→ 连接鉴权通过", 5.7),
        ("S3 应答 / 下行", "字段17/18 ok/success 或失败文本\n失败 → 设备武装复位看门狗\n(10min 复位，日≤5次)", 3.65),
        ("S4 业务下行命令", "任意字段 TLV 报文 → 下发", 1.45),
    ]
    for t, sub, y in ssteps:
        box(ax, 7.4, y + 1.55, 5.6, 0.55, t, fc="#7a5c10", ec="#7a5c10", fs=8.4, tc="white", bold=True)
        box(ax, 7.4, y, 5.6, 1.45, sub, fs=7.9)

    # 中央双向通道
    ax.text(6.7, 9.0, "上行 ↗ / 下行 ↙", ha="center", fontsize=10, color=RED, fontweight="bold")
    # D2 → S1（getip 请求）与 S2（鉴权）
    arrow(ax, 5.95, 6.1, 7.3, 7.9, color=RED, lw=1.9)
    ax.text(6.15, 7.15, "getip/鉴权", fontsize=8.2, color=RED, rotation=38)
    # D3 → S3（周期数据上报）
    arrow(ax, 5.95, 2.9, 7.3, 4.15, color=RED, lw=1.9)
    ax.text(6.15, 3.3, "数据帧", fontsize=8.2, color=RED, rotation=35)
    # S3 → D1（鉴权成功/应答回调）
    arrow(ax, 7.3, 6.7, 5.95, 7.75, color=BLUE, lw=1.9)
    ax.text(7.1, 7.5, "auth_result", fontsize=7.8, color=BLUE, rotation=-35)
    # S4 → 设备（下行命令 REMOTE_COMMAND）
    arrow(ax, 7.3, 2.6, 5.95, 1.8, color=BLUE, lw=1.9)
    ax.text(7.25, 2.0, "下行命令", fontsize=8.2, color=BLUE, rotation=-42)
    # D1 → S3?（上行应答）忽略
    # 心跳说明条
    box(ax, 0.4, 0.5, 5.5, 0.85,
        "心跳保活（aircloudTask）：距上次发送 ≥300s\n→ 发 RANDOM_DATA(1281) {csq,eci,rsrp,band}",
        fs=7.6, fc=WHITE, ec=LINE)
    box(ax, 7.4, 0.5, 5.6, 0.85, "数据帧即保活：服务器收到任意上行\n都刷新链路活跃（心跳仅兜底）", fs=7.9)
    save(fig, "fig3_comm_flow.png")

# ============ fig4 上报运行模式状态机 ============
def fig4():
    fig, ax = new_ax(13.4, 8.3, (0, 13.4), (0, 8.3))
    ax.text(6.7, 8.0, "上报运行模式状态机（GNSS 三态 + fast_report 实时上报）", ha="center",
            fontsize=14, color=NAVY, fontweight="bold")
    # 顶部说明条
    box(ax, 0.7, 7.2, 12.0, 0.55,
        "由 active_mode.main_loop 驱动：每轮先查实时上报到期 → 评估 GNSS 开关 → 节流上报 → waitUntil 震动事件",
        fc="#eef4f8", ec=LINE, fs=8.6, tc=BLUE)
    # 三态盒（y 5.05..6.75）
    states = [
        (0.7, "GNSS 开启态", "上报间隔 10s ｜ 功耗 mode0 全功率\n带 1293(20Hz流) + 1294(1Hz五元组流)", "#e8f0f7", NAVY),
        (4.95, "GNSS 关闭态", "上报间隔 300s ｜ 功耗 mode1 低功耗\n带 1292 单点三轴；无二进制流", "#f4f8fb", NAVY),
        (9.2, "实时上报态 (fast_report)", "上报间隔 1s ｜ 功耗 mode0\n持续 60s（重复下发续期）｜不带 1293/1294", GOLDB, "#7a5c10"),
    ]
    for x, t, sub, fc, ec in states:
        box(ax, x, 5.15, 3.5, 1.6, "", fc=fc, ec=ec, lw=1.8)
        ax.text(x + 1.75, 6.35, t, ha="center", va="center", fontsize=10.5, color=NAVY,
                fontweight="bold")
        ax.text(x + 1.75, 5.72, sub, ha="center", va="center", fontsize=7.6, color="#3c4a55")
    # 开关切换（双箭头横在空隙）
    arrow(ax, 4.3, 5.95, 4.9, 5.95, color=NAVY, lw=1.6)
    arrow(ax, 4.9, 5.35, 4.3, 5.35, color=NAVY, lw=1.6)
    ax.text(4.6, 6.25, "评估命中\n→ 开", ha="center", fontsize=6.6, color=NAVY)
    ax.text(4.6, 5.08, "静止超\n180s → 关", ha="center", fontsize=6.6, color=NAVY)
    # 触发源盒（底部）
    box(ax, 0.7, 3.3, 6.0, 1.3,
        "is_gnss_required 命中（任一）：\n① 开机 300s 内\n② 正在震动（DA221 中断）\n③ 最近 180s 内震过\n④ 实时上报结束后 180s 保持窗口",
        fc=WHITE, ec=NAVY, fs=7.9)
    arrow(ax, 3.7, 3.3, 2.9, 5.15, color=NAVY, lw=1.5)
    box(ax, 7.2, 3.3, 5.6, 1.0,
        "静止超 180s（以上条件全不成立）\n→ 关 GNSS、停流采样、清缓冲、降功耗 mode1",
        fc=WHITE, ec=NAVY, fs=8.2)
    arrow(ax, 10.0, 3.3, 6.85, 5.15, color=NAVY, lw=1.5)
    # fast_report / FORCE_REPORT / 到期（最底部横条）
    box(ax, 0.7, 1.35, 12.0, 1.4,
        "云命令 fast_report（任意态可入）→ publish FAST_REPORT_START → 进入实时上报态（先强制开 GNSS），1s×60s\n"
        "60s 到期 → 强制回到 GNSS 开启态并保持 180s，之后按震动条件正常评估\n"
        "云命令 get_device_data → FORCE_REPORT → 立即补报一帧（不切换 GNSS 状态，恢复原节流）",
        fc=GOLDB, ec=AMBER, fs=8.6, tc="#5a4409")
    arrow(ax, 10.95, 6.75, 10.3, 5.15, color=RED, lw=1.5)  # 实时态顶部→底部(标注在盒右侧)
    ax.text(12.35, 6.15, "fast_report\n进入/续期", fontsize=6.8, color=RED, ha="center")
    save(fig, "fig4_mode_state.png")

# ============ fig5 事件订阅关系 ============
def fig5():
    fig, ax = new_ax(13.6, 9.6, (0, 13.6), (0, 9.6))
    ax.text(6.8, 9.25, "全局事件总线：发布方 → 事件 → 订阅方（重点业务事件）", ha="center",
            fontsize=13.5, color=NAVY, fontweight="bold")
    box(ax, 5.9, 0.6, 1.8, 8.2, "sys 事件总线\n\npublish\nsubscribe\nwaitUntil",
        fc=GOLDB, ec=AMBER, lw=1.9, fs=8.6)
    rows = [
        ("gsensor 震动回调\n(2s 限流后)", "MOTION_EVENT", "active_mode main_loop\nwaitUntil 提前醒 / 常驻标志"),
        ("drv_lowpower\nWAKEUP2 唤醒", "MOTION_EVENT", "同上（低功耗路径）"),
        ("remote.fast_report", "FAST_REPORT_START", "active_mode：实时上报态"),
        ("remote.get_device_data", "FORCE_REPORT", "active_mode：立即补报一帧"),
        ("create 三通道收包", "REMOTE_COMMAND", "remote 命令分发 + tools LED"),
        ("create 各通道 task", "CLOUD_CONNECTED", "active_mode / boot_lbs_report"),
        ("active_mode 低电检测", "BATTERY_LOW", "lowpower_app 降级策略"),
        ("battery 轮询任务", "CHARGING_START/STOP", "tools LED 状态机"),
        ("业务模块 create.send / send_aircloud", "NET_SENT_RDY_1 / AIRCLOUD_SEND_1", "create.aircloudTask\n直发 excloud"),
    ]
    y = 8.15
    for pub, ev, sub in rows:
        box(ax, 0.3, y - 0.3, 3.9, 0.6, pub, fc="#f4f8fb", fs=7.4)
        box(ax, 9.4, y - 0.3, 3.9, 0.6, sub, fc="#eef4f8", fs=7.4)
        arrow(ax, 4.2, y, 5.9, y, color=AMBER, lw=1.2)
        arrow(ax, 7.7, y, 9.4, y, color=BLUE, lw=1.2)
        ax.text(6.8, y, ev, ha="center", va="center", fontsize=6.6, color="#7a5c10",
                bbox=dict(boxstyle="round,pad=0.15", fc="white", ec=AMBER, lw=0.7))
        y -= 0.84
    save(fig, "fig5_event_bus.png")

if __name__ == "__main__":
    fig1(); fig2(); fig3(); fig4(); fig5()
    print("ALL DONE")
