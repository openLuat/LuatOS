# -*- coding: utf-8 -*-
"""从 main.xml + ui_vars.lua + tiles.py 机械生成 design/spec.md

不手抄任何坐标：表格里的每个数字都来自最终交付的 main.xml，
保证 spec 与烧进设备的 XML 一字不差。
"""
import io
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE = os.path.join(ROOT, "code")
RES = os.path.join(CODE, "res")
XML = os.path.join(RES, "main.xml")
OUT = os.path.join(ROOT, "design", "spec.md")

sys.path.insert(0, os.path.join(ROOT, "tools"))
from tiles import TILES  # noqa: E402

TYPE_CN = {
    "image": "image（图/图按钮）",
    "label": "label（文本）",
    "textarea": "textarea（可编辑）",
    "keyboard": "keyboard（软键盘）",
    "container": "container",
    "table": "table（表格）",
    "chart": "chart（曲线）",
    "slider": "slider（滑块）",
    "animimg": "animimg（动图）",
}

BIND_RE = re.compile(
    r'\{\s*id\s*=\s*"([^"]+)"\s*,\s*var\s*=\s*"([^"]+)"\s*,\s*kind\s*=\s*"([^"]+)"')


def load_bind():
    with io.open(os.path.join(CODE, "ui_vars.lua"), "r", encoding="utf-8") as f:
        uv = f.read()
    out = {}
    for m in BIND_RE.finditer(uv):
        out.setdefault(m.group(1), (m.group(2), m.group(3)))
    return out


def page_ids():
    tree = ET.parse(XML)
    root = tree.getroot()
    res = []
    for rs in root.findall("resources"):
        res = list(rs)
    pages = []
    for pgs in root.findall("pages"):
        pages.extend(pgs.findall("page"))
    return root, res, pages


def tile_size(name):
    for t in TILES:
        if t[0] == name:
            return t[1], t[2], t[3]
    return None


def png_size(fn):
    p = os.path.join(RES, fn)
    with open(p, "rb") as f:
        head = f.read(32)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        # JPG：扫 SOF0
        with open(p, "rb") as f:
            data = f.read()
        i = 2
        while i < len(data) - 9:
            if data[i] != 0xFF:
                i += 1
                continue
            mk = data[i + 1]
            if mk in (0xC0, 0xC1, 0xC2):
                h = data[i + 5] * 256 + data[i + 6]
                w = data[i + 7] * 256 + data[i + 8]
                return w, h
            seg = data[i + 2] * 256 + data[i + 3]
            i += 2 + seg
        return 0, 0
    w = int.from_bytes(head[16:20], "big")
    h = int.from_bytes(head[20:24], "big")
    return w, h


def main():
    root, res, pages = page_ids()
    bind = load_bind()
    L = []
    A = L.append

    A("# PLCUI 设计说明 · 智能注塑车间 1# 产线监控总览")
    A("")
    A("> 本文件由 `tools/spec_gen.py` 从 `code/res/main.xml`、`code/ui_vars.lua`、"
      "`tools/tiles.py` 机械生成，**数字与烧进设备的 XML 完全一致**，不要手改；"
      "改布局请回 `design/index.html` + `design/theme.css`，再重跑导出一遍。")
    A("")
    A("| 项 | 值 |")
    A("|---|---|")
    A("| 目标平台 | Air8607（Air1603 平台）+ 10 寸 RGB %s×%s |"
      % (root.get("width"), root.get("height")))
    A("| 画布 | %s×%s，1:1 设计，不做响应式 |" % (root.get("width"), root.get("height")))
    A("| 页面数 | %d（entry = `%s`） |" % (len(pages), root.get("entry")))
    total = sum(1 for pg in pages for e in pg.iter() if e is not pg)
    A("| 组件数 | %d / 512 |" % total)
    A("| 资源数 | %d / 256 |" % len(res))
    A("| XML 体积 | %.1f KB / 256 KB |" % (os.path.getsize(XML) / 1024.0))
    A("| 栅格 | 4px；所有坐标为整数绝对值，不用 z-index（层叠 = 书写顺序） |")
    A("| 素材来源 | 全部 `design/theme.css` 自画 → 无头 Chromium 透明底截图 → 按包围盒裁切 |")
    A("")
    A("## 一、色板")
    A("")
    A("| 变量 | 值 | 用途 |")
    A("|---|---|---|")
    for k, v, u in [
        ("--m1", "#43494f", "机箱拉丝亮面"),
        ("--m2", "#2d3237", "面板主色"),
        ("--m3", "#1c2024", "页面底色（XML 的 page background）"),
        ("--m4", "#111417", "凹陷 / 槽底"),
        ("--amber", "#ffb43a", "温度主色、主数值"),
        ("--cyan", "#48d8d0", "压力主色、可操作项"),
        ("--green", "#63e08a", "运行 / 正常"),
        ("--red", "#ff4b40", "急停 / 严重报警"),
        ("--led", "#ffd15c", "数码管辉光"),
    ]:
        A("| `%s` | `%s` | %s |" % (k, v, u))
    A("")

    # ---------------- 页面
    A("## 二、页面与组件清单")
    A("")
    A("「烘图」= 质感不随数据变，整块栅格化成 PNG；「活组件」= 随数据变，必须是 PLCUI 组件。")
    A("")
    for pg in pages:
        pid = pg.get("id")
        A("### %s（`background=%s`）" % (pid, pg.get("background")))
        A("")
        A("| # | id | 组件 | x | y | w | h | 资源 / 内容 | 性质 | 绑定变量 |")
        A("|---|---|---|---|---|---|---|---|---|---|")
        n = 0
        for e in pg:
            if e.tag not in TYPE_CN:
                continue
            n += 1
            eid = e.get("id", "")
            src = e.get("src") or ""
            if e.tag == "image":
                extra = src
                if e.get("src-pressed"):
                    extra += " / " + e.get("src-pressed")
                if e.get("src-checked"):
                    extra += " / ✓" + e.get("src-checked")
                nature = "烘图"
                if e.get("clickable") == "true":
                    nature = "烘图·按钮"
            elif e.tag == "label":
                extra = (e.get("text") or "").replace("|", "\\|")
                nature = "活组件"
            elif e.tag == "textarea":
                extra = "初始 `%s`，键盘 `%s`" % (e.get("text") or "", e.get("keyboard") or "")
                nature = "活组件"
            elif e.tag == "keyboard":
                extra = "layout=%s" % e.get("layout", "")
                nature = "活组件"
            elif e.tag == "chart":
                extra = "%s，%s 点，%s 系列" % (
                    e.get("type"), e.get("point-count"), len(e.findall("series")))
                nature = "活组件"
            elif e.tag == "table":
                extra = "%s 行 × %s 列（含表头）" % (e.get("rows"), e.get("columns"))
                nature = "活组件"
            elif e.tag == "slider":
                extra = "%s ~ %s，值 %s" % (e.get("min"), e.get("max"), e.get("value"))
                nature = "活组件"
            else:
                extra = ""
                nature = "活组件"
            b = bind.get(eid)
            btxt = "`%s`（%s）" % (b[0], b[1]) if b else "—"
            on = e.get("on-click") or e.get("on-change") or e.get("on-submit") or ""
            if on:
                btxt = ("`%s` → `%s`" % (b[0], on)) if b else ("事件 `%s`" % on)
            A("| %d | `%s` | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                n, eid, TYPE_CN[e.tag].split("（")[0], e.get("x"), e.get("y"),
                e.get("w"), e.get("h"), extra, nature, btxt))
        A("")

    # ---------------- 资源
    A("## 三、资源清单")
    A("")
    A("文件名（含扩展名）≤ 23 字节；`src` 写资源 ID 不写路径；全部平铺在 `code/res/`，烧录时与 `main.xml` 同级。")
    A("")
    A("| 资源 ID | 文件 | 尺寸 | 解码内存 | 显示尺寸（去 pad） |")
    A("|---|---|---|---|---|")
    total_mem = 0
    for e in res:
        rid = e.get("id")
        fn = e.get("src")
        w, h = png_size(fn)
        mem = w * h * 4
        total_mem += mem
        ts = tile_size(rid)
        show = "%d×%d" % (ts[0], ts[1]) if ts else "整页背景"
        A("| `%s` | `%s` | %d×%d | %.1f KB | %s |" % (rid, fn, w, h, mem / 1024.0, show))
    A("")
    A("合计解码内存约 **%.1f MB**（PC 侧缓存 4MB，单片最大 %.1f MB）。"
      % (total_mem / 1048576.0, max(png_size(e.get("src"))[0] * png_size(e.get("src"))[1] * 4
                                  for e in res) / 1048576.0))
    A("")

    # ---------------- 数据控件
    A("## 四、数据控件参数")
    A("")
    for pg in pages:
        for e in pg.iter("chart"):
            A("### chart `%s`（页 `%s`）" % (e.get("id"), pg.get("id")))
            A("")
            A("| 属性 | 值 | 说明 |")
            A("|---|---|---|")
            A("| point-count | %s | Lua 侧 `set_values` 的数组长度必须精确等于它 |" % e.get("point-count"))
            A("| y-min / y-max | %s / %s | 传入值为归一化后的 0~100 |" % (e.get("y-min"), e.get("y-max")))
            A("| hdiv / vdiv | %s / %s | 网格线全靠背景图，组件网格关掉 |" % (e.get("hdiv"), e.get("vdiv")))
            A("| bg-opacity | %s | 0 = 透明，露出底图的刻度与网格 |" % e.get("bg-opacity"))
            A("")
            A("| 系列 | 颜色 | 物理量 | 换算（视图层） |")
            A("|---|---|---|---|")
            for s in e.findall("series"):
                phys = {"t": "料筒温度", "p": "注射压力", "s": "设定值"}.get(s.get("id"), s.get("id"))
                conv = {
                    "t": "(实测 − 180) / (260 − 180) × 100",
                    "p": "(实测 − 60) / (120 − 60) × 100",
                    "s": "(设定 − 180) / (260 − 180) × 100",
                }.get(s.get("id"), "—")
                A("| `%s` | `%s` | %s | %s |" % (s.get("id"), s.get("color"), phys, conv))
            A("")
            A("> 换算是 `data_app.norm_t` / `norm_p` 做的，**数据层仍存真实单位（℃ / MPa）**；"
              "整条数组原子更新，任一值越界则整条不改。")
            A("")
        for e in pg.iter("table"):
            A("### table `%s`（页 `%s`）" % (e.get("id"), pg.get("id")))
            A("")
            A("rows=%s（**含表头**）× columns=%s，row-height=%s，组件高 %s → %s×%s = %s ≤ %s，不溢出。"
              % (e.get("rows"), e.get("columns"), e.get("row-height"), e.get("h"),
                 e.get("rows"), e.get("row-height"),
                 int(e.get("rows")) * int(e.get("row-height")), e.get("h")))
            A("")
            A("列宽 `%s`，列对齐 `%s`。单元格文本由 `data_app.alarm_rows()` 提供，每格 ≤ 511 字节。"
              % (e.get("col-widths"), e.get("col-aligns")))
            A("")
        for e in pg.iter("slider"):
            A("### slider `%s`（页 `%s`）" % (e.get("id"), pg.get("id")))
            A("")
            A("%s ~ %s，step=%s，knob-src=`%s`，track-color=`%s`。"
              % (e.get("min"), e.get("max"), e.get("step"), e.get("knob-src"), e.get("track-color")))
            A("")
            A("旋钮图必须是**正方形**，边长等于滑块短边（横向滑块取 `h`=%s），换滑块高度要同步重出 `%s.png`。"
              % (e.get("h"), e.get("knob-src")))
            A("")

    # ---------------- 事件
    A("## 五、事件对照")
    A("")
    A("`main.xml` 里每个 `on-*` 都必须在 `code/ui_app.lua` 的 `H` 表里同名注册，否则 load 报 `E_HANDLER`。")
    A("")
    A("| 页面 | 组件 id | 事件 | handler | 行为 |")
    A("|---|---|---|---|---|")
    behavior = {
        "go_overview": "切到总览页（延 40ms 再刷）",
        "go_trend": "切到趋势页",
        "go_alarm": "切到报警页",
        "go_settings": "切到参数页",
        "line_start": "产线启动，恢复正常配色与流动",
        "line_stop": "产线停止，管路条纹定格第 0 帧",
        "line_reset": "故障复位，清急停旗标",
        "line_estop": "急停：首按进「待确认」（按钮切 pressed 态 + 5s 超时），再按才停机",
        "dev_sel0": "选中 1# 设备，详情面板换数据",
        "dev_sel1": "选中 2# 设备",
        "dev_sel2": "选中 3# 设备",
        "ack0": "确认第 1 条报警",
        "ack1": "确认第 2 条报警",
        "ack2": "确认第 3 条报警",
        "alarm_ack_all": "一键确认全部未确认报警",
        "alarm_clear": "清除已确认记录",
        "param_save": "参数落盘并提示已下发",
        "sw1": "报警蜂鸣器 开 / 关",
        "sw2": "班次自动切换 开 / 关（08:00 / 20:00）",
        "sw3": "趋势历史存储 开 / 关（本地 24h 环形缓冲）",
        "sp_change": "温度设定滑块改动 → 写 data_app.set_setpoint",
        "bright_change": "背光亮度滑块 → 写 st.bright（含 PWM 输出）",
        "param_submit": "参数框确认，越界不落盘并回滚显示",
        "param_cancel": "参数框取消，回滚到上次落盘值",
    }
    for pg in pages:
        for e in pg.iter():
            for k in ("on-click", "on-change", "on-submit", "on-cancel"):
                h = e.get(k)
                if h:
                    A("| %s | `%s` | `%s` | `H.%s` | %s |"
                      % (pg.get("id"), e.get("id"), k, h, behavior.get(h, "—")))
    A("")

    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("已生成 %s（%d 行）" % (OUT, len(L)))


if __name__ == "__main__":
    main()
