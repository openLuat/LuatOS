"""PLCUI 工程单一事实源：页面布局 + 素材清单 + 事件名。

gen_assets.py 按本文件的 ASSETS / 版面常量烘图，
gen_xml.py 按本文件的 PAGES 生成 code/main.xml 与 design/spec.md，
gen_html.py 按同一份数据生成 design/index.html。

视觉风格：浅蓝工业风（对齐 plcui_water_supply 的既有观感）——
天空蓝渐变底 + 白色圆角面板 + 绿色标题条 + 白色数值框 + 糖果色按钮 + 3D 拟物设备。
静态外观（标题副行、面板、标题条、说明文字、设备图形）全部烘进每页 1024x600 背景图，
运行时只叠动态控件（数值、指示灯、步骤条、液位、波纹、曲线、表格）。

页面：
1、run   运行总览：工艺流程图（含腔体实时压力与温度）+ 电磁阀 / 步进 / 加热三块操作面板
         + 实时状态 + 操作带
2、man   环节手动：六个环节各自启动 / 停止
3、test  膨胀参数：三次膨胀记录表 + 拟合曲线 + 结果

坐标系：1024 x 600，绝对定位，元素坐标全部取偶数栅格。
"""

W, H = 1024, 600

# ---------------- 配色 ----------------
SKY_TOP = "#8FD3F2"     # 天空渐变上
SKY_BOT = "#CBE9F8"     # 天空渐变下
FLOOR = "#DDE8F1"       # 地面
WHITE = "#FFFFFF"
INK = "#0B2E52"         # 主文字（深藏青）
INK2 = "#1A5C8E"        # 次文字
INK3 = "#4A7EA6"        # 说明文字
GREEN_TOP, GREEN_BOT, GREEN_LINE, GREEN_INK = "#BCE76A", "#7FBE2C", "#5E9A1C", "#2A5A0C"
BLUE_TOP, BLUE_BOT, BLUE_LINE = "#63B8EE", "#1F6DB4", "#155691"
RED_TOP, RED_BOT, RED_LINE = "#F0716C", "#C42F2B", "#96140F"
GRAY_TOP, GRAY_BOT, GRAY_LINE, GRAY_INK = "#F8FBFD", "#CBD8E3", "#94AEC4", "#274156"
CYAN = "#2FB8E8"
BOX_BORDER = "#8CC2E2"

VAL_BLUE = "#0E63B0"    # 压力数值
VAL_ORANGE = "#D97706"  # 温度数值
VAL_GREEN = "#2E8B2E"   # 结果数值

# ---------------- 版面常量 ----------------
PLANT_X, PLANT_Y, PLANT_W, PLANT_H = 16, 120, 580, 304
LAMP = 36

# 密闭腔体：玻璃内壁本身就是"178mm 量筒"，1mm = 1px，不再缩放。
# 外框含上下 12px 金属盖，内壁 166..344 正好 178px。
CH_X0, CH_Y0, CH_X1, CH_Y1 = 186, 154, 446, 356
CH_LEFT, CH_RIGHT = 190, 438          # 内壁左右（液位与软塞的边界）
CH_TOP, CH_BOT = 166, 344             # 内壁上下，178px = 178mm
CH_MM = CH_BOT - CH_TOP               # 178

# 软塞（活塞）：横向填满腔体内壁，厚度 24px；行程 110mm，最低位贴腔底。
CAR_W, CAR_H = CH_RIGHT - CH_LEFT, 24     # 248 x 24
CAR_X = CH_LEFT
CAR_SPAN = 110                            # 行程像素 = mm 数
CAR_STEPS = 10                            # 11 个预置档位（每档 11mm）
CAR_STEP = CAR_SPAN // CAR_STEPS
CAR_TOP = CH_BOT - CAR_H                  # pos=0 时软塞顶 = 320

# 活塞杆：从电机底（=腔体顶 154）伸到软塞顶，长度随档位变，
# 所以烘 11 张不同高度的小图，与软塞同档切显隐 —— 杆永远不越过软塞。
ROD_W = 12
ROD_X = (CH_LEFT + CH_RIGHT) // 2 - ROD_W // 2    # 308，腔体中线 314
ROD_TOP = CH_Y0                            # 154
ROD_H = CAR_TOP - ROD_TOP + 2              # 168（+2 压在软塞里，避免缝隙）

# 液位：腔体内壁的整块区域，11 张预烘素材靠 set_src 切换。
# 不用 image:set_size —— 那是 PLCUI 1.0.2 的接口，目标固件 1.0.1 没有。
#
# 档位按"活塞行程"分，不按 0~100% 腔高分：活塞行程只有 110mm，
# 液面最高就停在 110mm（腔高的 62%），所以 11 张素材正好对应
# 液面 0 / 11 / 22 … 110 mm，与软塞的 11 个预置档位一一对齐：
# 液面顶边 = 软塞下沿 = 344 - 11i，像素上严丝合缝。
LIQ_X, LIQ_W = CH_LEFT, CH_RIGHT - CH_LEFT   # 190, 248
LIQ_TOP, LIQ_H = CH_TOP, CH_MM               # 166, 178
LIQ_BOT = CH_BOT                             # 344
LIQ_MM, LIQ_SPAN, LIQ_STEPS = CH_MM, CAR_SPAN, CAR_STEPS
LIQ_STEP = LIQ_SPAN // LIQ_STEPS             # 11

# 两个电磁阀都接在腔体底部：横向落在腔体范围内，纵向在腔体下方。
V1_XY = (250, 390)      # 电磁阀 1 中心（页面坐标）
V2_XY = (382, 390)      # 电磁阀 2 中心（页面坐标）

CHIP_Y, CHIP_W, CHIP_H = 76, 158, 34
CHIP_GAP = 164

BTN_BAND_Y = 520


def filename(rid):
    """资源 ID -> 文件名：整页大图走 JPG（真机硬解快），其余走 PNG。"""
    return rid + (".jpg" if rid.startswith("bg_") else ".png")


def _img(page, wid, x, y, w, h, src, **kw):
    d = {"tag": "image", "id": wid, "x": x, "y": y, "w": w, "h": h, "src": src}
    d.update(kw)
    page.append(d)


def _btn(page, wid, x, y, w, h, src, event, **kw):
    d = {"tag": "image", "id": wid, "x": x, "y": y, "w": w, "h": h,
         "src": src, "src-pressed": src + "_p", "clickable": "true", "on-click": event}
    d.update(kw)
    page.append(d)


def _lab(page, wid, x, y, w, h, text, size=18, color=INK, align="left"):
    page.append({"tag": "label", "id": wid, "x": x, "y": y, "w": w, "h": h,
                 "text": text, "font": "hzfont", "font_size": size,
                 "color": color, "align": align})


def _chrome(page, bg, title):
    """每页一张背景大图：天空 / 地面 / 副标题 / 时钟底板 / 底部操作带。"""
    _img(page, "tb_bg", 0, 0, W, H, bg)
    _lab(page, "tb_title", 22, 8, 380, 44, title, 34, INK)
    _img(page, "tb_lamp", 392, 18, 32, 32, "im_lamp_idle")
    _lab(page, "tb_badge", 434, 20, 300, 32, "待机", 20, INK)
    _img(page, "tb_alarm", 430, 14, 264, 36, "im_alarm")
    page[-1]["hidden"] = "true"
    _lab(page, "tb_cd", 768, 12, 232, 20, "2026/11/17", 16, INK3, "right")
    _lab(page, "tb_ct", 768, 30, 232, 28, "12:00:00", 22, INK, "right")


def _chips(page):
    """六段工艺步骤条，三态素材 st{i}_g / st{i}_a / st{i}_d。"""
    for i in range(6):
        _img(page, "stp%d" % (i + 1), 16 + i * CHIP_GAP, CHIP_Y, CHIP_W, CHIP_H,
             "st%d_g" % (i + 1))


def _plant(page):
    """工艺流程图上的动态件：液位、软塞、活塞杆、两个阀门指示灯。

    run 页与 dev 页共用同一组 ID（同 ID 跨页合法，运行时只 find 当前页），
    所以界面层不需要为两页各写一套刷新逻辑。

    层叠顺序 = 添加顺序：液位 -> 活塞杆 -> 软塞 -> 阀门灯 -> 读数。
    软塞横向填满腔体内壁，压在活塞杆上，所以杆的下端永远被软塞盖住、
    不会从软塞下方露出来；杆的上端接在电机底部（腔体顶）。
    """
    _img(page, "pv_liq", LIQ_X, LIQ_TOP, LIQ_W, LIQ_H, "im_liq%02d" % LIQ_STEPS)
    page[-1]["hidden"] = "true"
    # 活塞杆：11 档长度，与软塞同档切显隐，杆底始终等于软塞顶
    for i in range(CAR_STEPS + 1):
        _img(page, "pv_rod%d" % i, ROD_X, ROD_TOP, ROD_W, ROD_H - i * CAR_STEP,
             "im_rod%02d" % i)
        if i != 0:
            page[-1]["hidden"] = "true"
    # 软塞：11 个预置位置（每档 11mm），最低位贴腔底
    for i in range(CAR_STEPS + 1):
        _img(page, "pv_car%d" % i, CAR_X, CAR_TOP - i * CAR_STEP,
             CAR_W, CAR_H, "im_car")
        if i != 0:
            page[-1]["hidden"] = "true"
    _img(page, "pv_v1", V1_XY[0] - LAMP // 2, V1_XY[1] - LAMP // 2, LAMP, LAMP, "im_valve_c")
    _img(page, "pv_v2", V2_XY[0] - LAMP // 2, V2_XY[1] - LAMP // 2, LAMP, LAMP, "im_valve_c")
    # 左侧读数卡片：腔体实时压力与温度（字号比原主读数面板缩小一号）
    _lab(page, "pv_pv", 26, 170, 70, 40, "0.0", 30, VAL_BLUE)
    _lab(page, "pv_pu", 96, 178, 60, 22, "kPa", 16, INK3)
    _lab(page, "pv_tv", 26, 234, 70, 36, "25.0", 26, VAL_ORANGE)
    _lab(page, "pv_tu", 96, 242, 60, 22, "℃", 16, INK3)

    # 右侧三个工艺参数：液面高度 / 软塞高度 / 体积比，统一 16 号 INK2
    _lab(page, "pv_lv", 452, 208, 140, 24, "液面高度 0.0 mm", 16, INK2)
    _lab(page, "pv_cv", 452, 240, 140, 24, "软塞高度 0.0 mm", 16, INK2)
    _lab(page, "pv_xv", 452, 272, 140, 24, "体积比 1.000", 16, INK2)


def _page_run():
    p = []
    _chrome(p, "bg_run", "蒸气压测定仪")
    _chips(p)
    _plant(p)

    # 右列设备操作：电磁阀 / 步进电机 / 加热（面板与绿标题条烘在背景里）
    _btn(p, "dv_v1o", 628, 156, 112, 48, "bt_v1o", "dev_op")
    _btn(p, "dv_v1c", 748, 156, 112, 48, "bt_v1c", "dev_op")
    _lab(p, "ds_v1", 872, 166, 120, 24, "阀1:关", 18, INK2)
    _btn(p, "dv_v2o", 628, 208, 112, 48, "bt_v2o", "dev_op")
    _btn(p, "dv_v2c", 748, 208, 112, 48, "bt_v2c", "dev_op")
    _lab(p, "ds_v2", 872, 218, 120, 24, "阀2:关", 18, INK2)

    _btn(p, "dv_up", 628, 304, 112, 48, "bt_up", "dev_op")
    _btn(p, "dv_down", 748, 304, 112, 48, "bt_down", "dev_op")
    _btn(p, "dv_mstop", 868, 304, 120, 48, "bt_mstop", "dev_op")
    _lab(p, "ds_step", 862, 273, 132, 22, "步长 10", 16, GREEN_INK)
    _btn(p, "dv_s5", 628, 358, 72, 48, "bt_s5", "dev_step")
    _btn(p, "dv_s10", 702, 358, 72, 48, "bt_s10", "dev_step")
    _btn(p, "dv_s25", 776, 358, 72, 48, "bt_s25", "dev_step")
    _btn(p, "dv_nup", 850, 358, 68, 48, "bt_nup", "dev_jump")
    _btn(p, "dv_ndn", 920, 358, 68, 48, "bt_ndn", "dev_jump")

    _lab(p, "hs_temp", 628, 433, 180, 22, "设定 37.5℃", 16, GREEN_INK)
    _btn(p, "hs_on", 628, 460, 100, 48, "bt_heat_on", "heat_on")
    _btn(p, "hs_off", 736, 460, 100, 48, "bt_heat_off", "heat_off")
    _btn(p, "hs_minus", 844, 460, 72, 48, "bt_minus", "temp_minus")
    _btn(p, "hs_plus", 924, 460, 72, 48, "bt_plus", "temp_plus")

    # 实时状态两行三列
    _lab(p, "rs_1", 30, 456, 180, 22, "环节 --", 17, INK2)
    _lab(p, "rs_2", 222, 456, 180, 22, "阀1:关 阀2:关", 17, INK2)
    _lab(p, "rs_3", 414, 456, 176, 22, "步进 0.0 mm", 17, INK2)
    _lab(p, "rs_4", 30, 484, 180, 22, "液位 0%", 17, INK2)
    _lab(p, "rs_5", 222, 484, 180, 22, "加热 关", 17, INK2)
    _lab(p, "rs_6", 414, 484, 176, 22, "蒸气压 -- kPa", 17, VAL_GREEN)

    _btn(p, "bd_auto", 16, 532, 140, 56, "bt_auto", "auto_start")
    _btn(p, "bd_pause", 164, 532, 96, 56, "bt_pause", "auto_pause")
    _btn(p, "bd_reset", 268, 532, 96, 56, "bt_reset", "reset")
    _btn(p, "bd_estop", 372, 532, 112, 56, "bt_estop", "estop")
    _btn(p, "bd_test", 504, 532, 112, 56, "bt_gtest", "go_test")
    return p


def _page_man():
    p = []
    _chrome(p, "bg_man", "环节手动")
    _chips(p)
    for i in range(6):
        x = 16 + (i % 3) * 332
        y = 120 + (i // 3) * 148
        n = i + 1
        _img(p, "mv_l%d" % n, x + 16, y + 42, 32, 32, "im_lamp_idle")
        _lab(p, "mv_s%d" % n, x + 58, y + 44, 240, 26, "待机", 18, INK2)
        _btn(p, "mv_g%d" % n, x + 14, y + 84, 112, 48, "bt_go", "st_go")
        _btn(p, "mv_h%d" % n, x + 140, y + 84, 112, 48, "bt_halt", "st_halt")

    _lab(p, "ms_1", 30, 452, 300, 22, "当前环节 --", 17, INK2)
    _lab(p, "ms_2", 350, 452, 300, 22, "腔体压力 0.0 kPa", 17, INK2)
    _lab(p, "ms_3", 670, 452, 320, 22, "腔体温度 25.0 ℃", 17, INK2)
    _lab(p, "ms_4", 30, 482, 300, 22, "步进位置 0.0 mm", 17, INK2)
    _lab(p, "ms_5", 350, 482, 300, 22, "加热 关 / 阀1:关 阀2:关", 17, INK2)
    _lab(p, "ms_6", 670, 482, 320, 22, "蒸气压 -- kPa", 17, VAL_GREEN)

    _btn(p, "bd_back", 16, 532, 112, 56, "bt_back", "go_run")
    _btn(p, "bd_test", 136, 532, 112, 56, "bt_gtest", "go_test")
    _btn(p, "bd_reset", 744, 532, 96, 56, "bt_reset", "reset")
    _btn(p, "bd_estop", 856, 532, 112, 56, "bt_estop", "estop")
    return p


def _page_test():
    p = []
    _chrome(p, "bg_test", "膨胀参数")
    _chips(p)
    p.append({"tag": "table", "id": "ts_tbl", "x": 16, "y": 120, "w": 600, "h": 200,
              "rows": 5, "columns": 5, "row-height": 40,
              "col-widths": "80,150,120,120,130",
              "col-aligns": "center,center,center,center,center",
              "align": "center", "header-align": "center",
              "grid": "false", "header": "true", "cell-padding": 6,
              "font": "hzfont", "font_size": 19, "color": INK,
              "background": WHITE, "header-color": "#A8D84B",
              "alternate-color": "#EFF7FC", "border-color": BOX_BORDER,
              "border-width": 2,
              "cells": [(1, 1, "次数"), (1, 2, "压力 kPa"), (1, 3, "温度 ℃"),
                        (1, 4, "体积比"), (1, 5, "残差 kPa"),
                        (2, 1, "1"), (2, 2, "---"), (2, 3, "---"), (2, 4, "---"), (2, 5, "---"),
                        (3, 1, "2"), (3, 2, "---"), (3, 3, "---"), (3, 4, "---"), (3, 5, "---"),
                        (4, 1, "3"), (4, 2, "---"), (4, 3, "---"), (4, 4, "---"), (4, 5, "---"),
                        (5, 1, "结论"), (5, 2, "---"), (5, 3, "---"), (5, 4, "---"), (5, 5, "---")]})

    p.append({"tag": "chart", "id": "ts_chart", "x": 26, "y": 392, "w": 580, "h": 108,
              "type": "line", "point-count": 3, "y-min": 0, "y-max": 120,
              "hdiv": 4, "vdiv": 4, "line-width": 3, "grid-color": "#B7D6E8",
              "bg-opacity": 0,
              "series": [
                  {"id": "mea", "color": "#0E63B0", "values": "0,0,0"},
                  {"id": "fit", "color": "#D97706", "values": "0,0,0"},
              ]})

    _lab(p, "ts_a", 632, 162, 200, 60, "0.0", 40, VAL_GREEN)
    _lab(p, "ts_au", 838, 182, 80, 28, "kPa", 20, INK3)
    _lab(p, "ts_b", 632, 288, 200, 52, "0.0", 32, VAL_BLUE)
    _lab(p, "ts_bu", 838, 300, 80, 26, "kPa", 18, INK3)
    _lab(p, "ts_c", 632, 400, 200, 52, "0.0", 32, INK)
    _lab(p, "ts_cu", 838, 412, 80, 26, "kPa", 18, INK3)
    _lab(p, "ts_r", 760, 474, 220, 28, "0.00 kPa", 22, VAL_ORANGE)

    _btn(p, "bd_tstart", 16, 532, 128, 56, "bt_tstart", "test_start")
    _btn(p, "bd_tstop", 152, 532, 112, 56, "bt_tstop", "test_stop")
    _btn(p, "bd_calc", 272, 532, 112, 56, "bt_recalc", "test_calc")
    _btn(p, "bd_man", 392, 532, 112, 56, "bt_gman", "go_man")
    _btn(p, "bd_back", 512, 532, 112, 56, "bt_back", "go_run")
    _btn(p, "bd_reset", 744, 532, 96, 56, "bt_reset", "reset")
    _btn(p, "bd_estop", 856, 532, 112, 56, "bt_estop", "estop")
    return p


PAGES = [
    {"id": "run", "background": SKY_TOP, "widgets": _page_run()},
    {"id": "man", "background": SKY_TOP, "widgets": _page_man()},
    {"id": "test", "background": SKY_TOP, "widgets": _page_test()},
]
ENTRY = "run"


# ================================ 素材清单 ==============================
def _assets():
    a = [
        ("bg_run", (W, H), "运行总览页背景：工艺流程图 + 电磁阀/步进/加热三块操作面板 + 实时状态面板"),
        ("bg_man", (W, H), "环节手动页背景：六张环节卡片 + 状态摘要条"),
        ("bg_test", (W, H), "膨胀参数页背景：表格框 + 曲线面板 + 四个结果框"),
        ("im_alarm", (264, 36), "急停告警胶囊（与状态文字同位互斥显示）"),
        ("im_car", (CAR_W, CAR_H), "活塞软塞（横向填满腔体，11 个预置位置共用这一张）"),
        ("im_valve_o", (LAMP, LAMP), "电磁阀指示灯-开"),
        ("im_valve_c", (LAMP, LAMP), "电磁阀指示灯-关"),
        ("im_lamp_idle", (32, 32), "状态灯-待机"),
        ("im_lamp_run", (32, 32), "状态灯-运行"),
        ("im_lamp_done", (32, 32), "状态灯-已完成"),
        ("im_lamp_alarm", (32, 32), "状态灯-告警"),
    ]
    for i in range(LIQ_STEPS + 1):
        mm = i * LIQ_STEP
        a.append(("im_liq%02d" % i, (LIQ_W, LIQ_H),
                  "腔体液面 %d mm（腔高 %d%%，整块素材，运行时按级 set_src）"
                  % (mm, round(mm * 100.0 / LIQ_MM))))
        a.append(("im_rod%02d" % i, (ROD_W, ROD_H - i * CAR_STEP),
                  "活塞杆 %d mm 档（电机底到软塞顶，11 张长度配套软塞档位）" % mm))
    for i in range(6):
        a.append(("st%d_g" % (i + 1), (CHIP_W, CHIP_H), "步骤条-未开始"))
        a.append(("st%d_a" % (i + 1), (CHIP_W, CHIP_H), "步骤条-进行中"))
        a.append(("st%d_d" % (i + 1), (CHIP_W, CHIP_H), "步骤条-已完成"))
    for wid, size, text, style in BTN_SPEC:
        a.append((wid, size, "按钮 %s（%s）" % (text, style)))
        a.append((wid + "_p", size, "按钮 %s 按下态" % text))
    return a


BTN_SPEC = (
    ("bt_auto", (140, 56), "自动运行", "green"),
    ("bt_pause", (96, 56), "暂停", "gray"),
    ("bt_reset", (96, 56), "复位", "gray"),
    ("bt_estop", (112, 56), "急停", "red"),
    ("bt_back", (112, 56), "返回运行", "blue"),
    ("bt_gman", (112, 56), "手动控制", "blue"),
    ("bt_gtest", (112, 56), "膨胀参数", "blue"),
    ("bt_tstart", (128, 56), "开始测试", "green"),
    ("bt_tstop", (112, 56), "停止测试", "red"),
    ("bt_recalc", (112, 56), "重新计算", "gray"),
    ("bt_go", (112, 48), "启动", "green"),
    ("bt_halt", (112, 48), "停止", "gray"),
    ("bt_v1o", (112, 48), "阀1开", "green"),
    ("bt_v1c", (112, 48), "阀1关", "gray"),
    ("bt_v2o", (112, 48), "阀2开", "green"),
    ("bt_v2c", (112, 48), "阀2关", "gray"),
    ("bt_up", (112, 48), "上行", "blue"),
    ("bt_down", (112, 48), "下行", "gray"),
    ("bt_mstop", (120, 48), "步进停", "gray"),
    ("bt_s5", (72, 48), "5mm", "gray"),
    ("bt_s10", (72, 48), "10mm", "gray"),
    ("bt_s25", (72, 48), "25mm", "gray"),
    ("bt_nup", (68, 48), "上移", "blue"),
    ("bt_ndn", (68, 48), "下移", "gray"),
    ("bt_heat_on", (100, 48), "加热开", "green"),
    ("bt_heat_off", (100, 48), "加热关", "gray"),
    ("bt_minus", (72, 48), "-0.5", "gray"),
    ("bt_plus", (72, 48), "+0.5", "blue"),
)

ASSETS = _assets()

BTN_TEXT = {}
BTN_STYLE = {}
for _wid, _size, _text, _style in BTN_SPEC:
    BTN_TEXT[_wid] = _text
    BTN_STYLE[_wid] = _style

CHIP_TEXT = ("1 进液", "2 清洗", "3 定量", "4 加热", "5 膨胀", "6 计算")

# 环节卡片标题（bg_man 烘图用）
STAGE_TITLE = ("1 进液", "2 清洗密闭腔体", "3 定量进液 1/4",
               "4 加热恒温 37.5℃", "5 三次膨胀测定", "6 结果计算")

# 页名 -> 背景副标题（烘进背景图）
SUBTITLE = {
    "bg_run": "三次膨胀法 / 密闭腔体 DC-01",
    "bg_man": "六个环节独立启动与停止",
    "bg_test": "三点记录 / 拟合曲线 / 结果参数",
}

# main.xml 里出现的 on-click 值，ui_app.lua 必须有同名函数
EVENTS = ("auto_start", "auto_pause", "auto_stop", "reset", "estop",
          "go_run", "go_man", "go_test",
          "st_go", "st_halt", "dev_op", "dev_step", "dev_jump",
          "heat_on", "heat_off", "temp_minus", "temp_plus",
          "test_start", "test_stop", "test_calc")
