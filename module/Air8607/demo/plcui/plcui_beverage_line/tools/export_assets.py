"""plcui 素材导出：把 web/*.html 设计稿导出为 plcui 的 main.xml + 图片资源。

工作方式
--------
1. 用 Playwright 打开每个页面（固定 1024x600 视口，deviceScaleFactor=1）。
2. 隐藏所有 ``.plc`` 元素后整页截图 -> 页面背景图（jpg，基线编码）。
3. 逐个显示 ``.plc[data-type=image]`` 元素并按元素包围盒裁剪截图 -> 按钮/状态图
   （normal + pressed，pressed 通过 CSS filter 加亮）。
   裁剪区域取自合成画面，因此图片不透明，盖回背景后与原设计逐像素一致。
4. 读取每个 ``.plc`` 元素的位置与 data-* 元数据，生成 main.xml。

用法
----
    python tools/export_assets.py            # 导出全部页面
    python tools/export_assets.py realtime   # 只导出指定页面
"""

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WEB = os.path.join(ROOT, "web")
OUT = os.path.join(ROOT, "code", "res")  # 图片 + main.xml 与真机 /res/ 一致

WIDTH, HEIGHT = 1024, 600

# 文件名 / 资源 id 上限（字节）。Air8607 的 luadb 与 VFS 要求 <= 23 字节
NAME_MAX = 23

STATE_SHORT = {"normal": "n", "pressed": "p", "checked": "c", "disabled": "d"}

# page id -> (html 文件, 短码, 是否入口页)
PAGES = [
    ("overview", "overview.html", "ov", True),
    ("realtime", "realtime.html", "rt", False),
    ("assets", "assets.html", "as", False),
    ("params", "params.html", "pa", False),
    ("report", "report.html", "rp", False),
    ("alarm", "alarm.html", "al", False),
]

SHORT = {pid: short for pid, _, short, _ in PAGES}


ASSET_MAP = {}


def res_name(page_id, key, state):
    """资源名：<页面短码>_<组件短名>_<状态首字母>，例如 as_chip_run_n（14 字节）。"""
    name = f"{SHORT[page_id]}_{key}_{STATE_SHORT[state]}"
    if len(name.encode("utf-8")) > NAME_MAX:
        raise SystemExit(f"资源名超长（{len(name.encode())} 字节 > {NAME_MAX}）: {name}")
    return name

# ---------------------------------------------------------------- 图表初始数据
# key = "page:widget"，value = {series_id: [数值...]}
CHARTS = {
    "realtime:trend": {
        "level": [52, 54, 57, 60, 64, 70, 78, 86, 94, 100, 98, 92, 86, 80, 74, 70,
                  68, 70, 74, 80, 88, 96, 99, 95, 86],
        "pressure": [45, 46, 47, 48, 52, 58, 66, 76, 88, 98, 100, 96, 88, 78, 70, 66,
                     68, 72, 78, 86, 92, 96, 94, 88, 80],
        "speed": [44, 45, 47, 50, 54, 58, 63, 69, 76, 84, 90, 87, 81, 75, 71, 69,
                  71, 74, 78, 82, 86, 88, 85, 82, 78],
        "temp": [58, 60, 62, 65, 69, 74, 80, 86, 92, 96, 95, 92, 88, 85, 82, 80,
                 81, 83, 86, 89, 92, 94, 92, 89, 85],
    },
    "realtime:mini_trend": {
        "cap": [62, 66, 58, 61, 70, 74, 68, 72, 80, 84, 78, 74, 70, 66, 63, 60],
    },
    "report:output_bar": {
        "d1": [1000, 0, 0, 0],
        "d2": [0, 810, 0, 0],
        "d3": [0, 0, 810, 0],
        "d4": [0, 0, 0, 557],
    },
    "report:pass_line": {
        "rate": [99.81, 99.76, 99.79, 99.72, 99.68],
    },
    "overview:line_trend": {
        "out": [40, 52, 60, 55, 68, 72, 66, 74, 80, 76, 70, 64, 58, 54],
    },
}

CHART_LABELS = {
    "report:output_bar": ["白班", "中班", "夜班", "夜班"],
}

# ---------------------------------------------------------------- 表格初始数据
TABLES = {
    "assets:device_table": [
        ["A", "设备名称", "运行状态", "运行时长", "运行次数", "启停次数", "维护周期", "健康度"],
        ["1", "空瓶卸垛机", "运行", "280:00:00", "运行", "1", "125", "运行"],
        ["2", "洗瓶机", "运行", "288:30:00", "待机", "1", "125", "待机"],
        ["3", "瓶身检测机", "运行", "280:10:00", "待机", "1", "125", "待机"],
        ["4", "灌装机", "运行", "286:00:00", "待机", "1", "125", "待机"],
        ["5", "旋盖机", "运行", "288:20:00", "待机", "1", "125", "待机"],
        ["6", "贴标机", "运行", "280:00:00", "待机", "1", "125", "待机"],
        ["7", "喷标机", "运行", "290:10:00", "待机", "1", "125", "待机"],
        ["8", "喷码机", "运行", "280:50:00", "待机", "1", "125", "待机"],
        ["9", "装箱机", "运行", "280:00:00", "待机", "1", "125", "待机"],
        ["10", "码垛机", "运行", "280:00:00", "待机", "1", "125", "待机"],
        ["11", "吹瓶机", "运行", "281:00:00", "待机", "1", "121", "待机"],
        ["12", "套标机", "运行", "280:00:00", "待机", "1", "125", "待机"],
        ["13", "裹包机", "运行", "280:00:00", "待机", "1", "125", "待机"],
        ["14", "AGV 转车", "运行", "280:00:00", "待机", "1", "125", "待机"],
    ],
    "report:defect_table": [
        ["原因", "数量", "占比", "无盖", "无标", "其他", "备注"],
        ["液位不合格", "32瓶", "22.8%", "14瓶", "17.7%", "6瓶", "7.6%"],
        ["贴标错位", "28瓶", "20.5%", "18瓶", "11.4%", "6瓶", "7.6%"],
        ["喷码异常", "19瓶", "13.5%", "9瓶", "11.4%", "6瓶", "5.2%"],
        ["瓶盖不良", "14瓶", "10.0%", "11瓶", "9.8%", "3瓶", "3.1%"],
    ],
    "alarm:alarm_table": [
        ["报警时间", "设备名称", "报警内容", "级别", "处理状态"],
        ["10:28:15", "灌装机", "灌装压力偏高", "警告", "处理中"],
        ["10:15:42", "灌装机", "灌装压力偏高", "警告", "处理中"],
        ["10:15:42", "旋盖机", "扭矩异常", "紧急", "未确认"],
        ["09:52:06", "贴标机", "标签偏移", "警告", "已恢复"],
        ["09:30:11", "贴标机", "标签偏移", "警告", "已恢复"],
        ["09:30:11", "装箱机", "光电传感器异常", "提示", "已确认"],
    ],
}


def esc(text):
    return (str(text)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;"))


def collect_script():
    """在页面里找出所有 .plc 元素及其元数据。"""
    return """
() => {
  const stage = document.querySelector('.stage');
  const out = {page: stage.dataset.page, widgets: []};
  document.querySelectorAll('.plc').forEach((el) => {
    const r = el.getBoundingClientRect();
    const d = el.dataset;
    const     item = {
      id: d.id, type: d.type,
      asset: d.asset || '',
      x: Math.round(r.x), y: Math.round(r.y),
      w: Math.round(r.width), h: Math.round(r.height),
      text: (d.text !== undefined ? d.text : (el.textContent || '')).trim(),
      fontsize: parseInt(d.fontsize || '0', 10),
      color: d.color || '',
      align: d.align || '',
      handler: d.handler || '',
      states: d.states || '',
      keyboard: d.keyboard || '',
      layout: d.layout || '',
      maxlen: d.maxlen || '',
      chars: d.chars || '',
      submit: d.submit || '',
      cancel: d.cancel || '',
      chart: d.chart || 'line',
      points: d.points || '',
      ymin: d.ymin || '',
      ymax: d.ymax || '',
      hdiv: d.hdiv || '',
      vdiv: d.vdiv || '',
      series: d.series || '',
      rows: d.rows || '',
      cols: d.cols || '',
      widths: d.widths || '',
      aligns: d.aligns || '',
      rowheight: d.rowheight || '',
      grid: d.grid || '',
      header: d.header || '',
      padding: d.padding || ''
    };
    out.widgets.push(item);
  });
  return out;
}
"""


def hide_style(selector):
    return """(sel) => {
      let s = document.getElementById('__export_style');
      if (!s) { s = document.createElement('style'); s.id = '__export_style'; document.head.appendChild(s); }
      s.textContent = sel;
    }"""


def launch(playwright):
    last = None
    for kwargs in ({"channel": "msedge"}, {"channel": "chrome"}, {}):
        try:
            return playwright.chromium.launch(**kwargs)
        except Exception as exc:  # noqa: BLE001
            last = exc
    raise last


def export_page(browser, page_id, html, exported, verbose):
    url = "file:///" + os.path.join(WEB, html).replace(os.sep, "/")
    page = browser.new_page(viewport={"width": WIDTH, "height": HEIGHT},
                            device_scale_factor=1)
    page.goto(url)
    page.wait_for_timeout(400)
    data = page.evaluate(collect_script())

    os.makedirs(OUT, exist_ok=True)

    # ---- 背景（隐藏全部 .plc 组件）----
    page.evaluate(hide_style(""), ".plc{visibility:hidden}")
    page.wait_for_timeout(120)
    bg_png = os.path.join(OUT, "_bg_tmp.png")
    page.screenshot(path=bg_png, clip={"x": 0, "y": 0, "width": WIDTH, "height": HEIGHT})
    bg_id = f"bg_{SHORT[page_id]}"
    bg_jpg = os.path.join(OUT, f"{bg_id}.jpg")
    Image.open(bg_png).convert("RGB").save(bg_jpg, "JPEG", quality=88, subsampling=0,
                                           progressive=False)
    os.remove(bg_png)

    # ---- 状态图 ----
    assets = []
    for w in data["widgets"]:
        if w["type"] != "image":
            continue
        key = w["asset"] or w["id"]
        states = [s for s in w["states"].split(",") if s]
        if not states:
            states = ["normal"]
        if key == "blank":
            assets.append(("blank", "blank.png"))
            continue
        if key == "power":
            # CSS 渐变渲染的开关红圆偏心 2-3px，改用几何作图保证同心
            from make_extra_assets import write_power_switch
            for state in states:
                name = res_name(page_id, key, state)
                write_power_switch(OUT, name, checked=(state != "normal"))
                assets.append((name, f"{name}.png"))
            continue
        if key == "anim_belt":
            # 传送带光点动画帧（透明 PNG，8 帧由 Lua 定时器轮播）
            from make_extra_assets import write_anim_frames
            for name in write_anim_frames(OUT):
                assets.append((name, f"{name}.png"))
            continue
        for state in states:
            name = res_name(page_id, key, state)
            ASSET_MAP.setdefault(name, f"{page_id} {w['id']} {state}")
            if name in exported:
                assets.append((name, f"{name}.png"))
                continue
            exported.add(name)
            page.evaluate(
                """([id, pressed]) => {
                  document.querySelectorAll('.plc').forEach(e => {
                    e.style.visibility = (e.dataset.id === id) ? 'visible' : 'hidden';
                  });
                  const el = document.querySelector(`.plc[data-id="${id}"]`);
                  el.classList.remove('st-normal', 'st-pressed', 'st-checked', 'st-disabled');
                  el.classList.add('st-' + pressed);
                }""",
                [w["id"], state])
            page.wait_for_timeout(60)
            path = os.path.join(OUT, f"{name}.png")
            page.screenshot(path=path, clip={"x": w["x"], "y": w["y"],
                                             "width": w["w"], "height": w["h"]})
            assets.append((name, f"{name}.png"))
            page.evaluate("""(id) => {
              const el = document.querySelector(`.plc[data-id="${id}"]`);
              el.classList.remove('st-normal', 'st-pressed', 'st-checked', 'st-disabled');
            }""", w["id"])

    page.close()
    if verbose:
        print(f"  {page_id}: {len(data['widgets'])} 组件, {len(assets)} 张状态图")
    return data, assets


def widget_xml(page_id, w, resources):
    attrs = [f'id="{w["id"]}"', f'x="{w["x"]}"', f'y="{w["y"]}"',
             f'w="{w["w"]}"', f'h="{w["h"]}"']
    if w["type"] == "label":
        attrs += ['font="hzfont"', f'font_size="{w["fontsize"]}"',
                  f'color="{w["color"] or "#ffffff"}"',
                  f'align="{w["align"] or "left"}"',
                  f'text="{esc(w["text"])}"']
        return "      <label " + " ".join(attrs) + "/>"

    if w["type"] == "textarea":
        attrs += ['font="hzfont"', f'font_size="{w["fontsize"] or 16}"',
                  f'color="{w["color"] or "#ffffff"}"',
                  f'align="{w["align"] or "left"}"',
                  'one-line="true"']
        if w["maxlen"]:
            attrs.append(f'max-length="{w["maxlen"]}"')
        if w["chars"]:
            attrs.append(f'accepted-chars="{esc(w["chars"])}"')
        if w["keyboard"]:
            attrs.append(f'keyboard="{w["keyboard"]}"')
        if w["submit"]:
            attrs.append(f'on-submit="{w["submit"]}"')
        if w["cancel"]:
            attrs.append(f'on-cancel="{w["cancel"]}"')
        attrs.append(f'text="{esc(w["text"])}"')
        return "      <textarea " + " ".join(attrs) + "/>"

    if w["type"] == "image":
        states = [s for s in w["states"].split(",") if s] or ["normal"]
        key = w["asset"] or w["id"]
        if key == "blank":
            attrs.append('src="blank"')
        elif key == "anim_belt":
            attrs.append('src="anim_belt_0"')
        else:
            attrs.append(f'src="{res_name(page_id, key, "normal")}"')
        for state, attr in (("pressed", "src-pressed"), ("checked", "src-checked"),
                            ("disabled", "src-disabled")):
            if state in states:
                attrs.append(f'{attr}="{res_name(page_id, key, state)}"')
        if w["handler"]:
            attrs += ['clickable="true"', f'on-click="{w["handler"]}"']
        return "      <image " + " ".join(attrs) + "/>"

    if w["type"] == "keyboard":
        attrs += ['layout="' + (w["layout"] or "number") + '"', 'font="hzfont"',
                  f'font_size="{w["fontsize"] or 18}"', 'hidden="true"']
        return "      <keyboard " + " ".join(attrs) + "/>"

    if w["type"] == "chart":
        attrs += [f'type="{w["chart"]}"', f'point-count="{w["points"]}"',
                  f'y-min="{w["ymin"]}"', f'y-max="{w["ymax"]}"',
                  f'hdiv="{w["hdiv"] or 0}"', f'vdiv="{w["vdiv"] or 0}"',
                  'bg-opacity="0"', 'line-width="2"', 'grid-color="#1d5871"']
        head = "      <chart " + " ".join(attrs) + ">\n"
        body = ""
        values = CHARTS.get(f'{page_id}:{w["id"]}', {})
        for spec in [s for s in w["series"].split(",") if s]:
            sid, color = spec.split(":")
            vals = values.get(sid, [0] * int(w["points"]))
            body += (f'        <series id="{sid}" color="{color}" values="'
                     + ",".join(str(v) for v in vals) + '"/>\n')
        return head + body + "      </chart>"

    if w["type"] == "table":
        rows = TABLES.get(f'{page_id}:{w["id"]}', [])
        nrows = int(w["rows"] or len(rows))
        ncols = int(w["cols"] or (len(rows[0]) if rows else 1))
        attrs += [f'rows="{nrows}"', f'columns="{ncols}"', 'font="hzfont"',
                  f'font_size="{w["fontsize"] or 14}"',
                  f'color="{w["color"] or "#dff2fb"}"',
                  'background="#061e2c"', 'border-color="#265a73"',
                  'header-color="#0d3d55"', 'alternate-color="#08242f"',
                  'border-width="1"', f'cell-padding="{w["padding"] or 6}"',
                  f'row-height="{w["rowheight"] or 30}"',
                  f'header="{w["header"] or "true"}"', f'grid="{w["grid"] or "false"}"',
                  'header-align="center"']
        if w["widths"]:
            attrs.append(f'col-widths="{w["widths"]}"')
        if w["aligns"]:
            attrs.append(f'col-aligns="{w["aligns"]}"')
        head = "      <table " + " ".join(attrs) + ">\n"
        body = ""
        for r, row in enumerate(rows, start=1):
            for c, cell in enumerate(row, start=1):
                body += (f'        <cell row="{r}" column="{c}" '
                         f'text="{esc(cell)}"/>\n')
        return head + body + "      </table>"

    raise ValueError(f"unsupported type {w['type']}")


def main():
    only = set(sys.argv[1:])
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("需要 playwright: python -m pip install playwright")
        return 1

    # 全量导出时先清掉旧素材（改名后避免残留旧文件占用 luadb 空间）
    if not only and os.path.isdir(OUT):
        for name in os.listdir(OUT):
            if name.lower().endswith((".png", ".jpg")):
                os.remove(os.path.join(OUT, name))

    blank = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    blank.save(os.path.join(OUT, "blank.png"), "PNG")

    xml_pages = []
    resources = []
    exported = set()
    widget_total = 0
    with sync_playwright() as pw:
        browser = launch(pw)
        for page_id, html, short, entry in PAGES:
            if only and page_id not in only:
                continue
            print(f"[{page_id}] {html}")
            data, assets = export_page(browser, page_id, html, exported, True)
            bg_id = f"bg_{short}"
            resources.append((bg_id, f"{bg_id}.jpg"))
            resources.extend(assets)
            lines = [f'    <page id="{page_id}" background="#04121f">',
                     f'      <image id="bg" x="0" y="0" w="{WIDTH}" h="{HEIGHT}" '
                     f'src="{bg_id}"/>']
            for w in data["widgets"]:
                lines.append(widget_xml(page_id, w, resources))
            lines.append("    </page>")
            widget_total += len(data["widgets"]) + 1
            xml_pages.append((page_id, entry, "\n".join(lines)))
        browser.close()

    xml = ['<?xml version="1.0" encoding="UTF-8"?>',
           f'<ui version="0.1" width="{WIDTH}" height="{HEIGHT}" entry="overview">',
           "  <resources>"]
    seen = set()
    for rid, src in resources:
        if rid in seen:
            continue
        seen.add(rid)
        xml.append(f'    <image id="{rid}" src="{src}"/>')
    xml.append("  </resources>")
    xml.append("  <pages>")
    for _, _, body in xml_pages:
        xml.append(body)
    xml.append("  </pages>")
    xml.append("</ui>")

    target = os.path.join(OUT, "main.xml")
    with open(target, "w", encoding="utf-8", newline="\n") as fp:
        fp.write("\n".join(xml) + "\n")
    print(f"写出 {target}: {len(seen)} 个资源, {widget_total} 个组件")
    if widget_total > 512:
        print("!! 组件数超过 PLCUI_MAX_WIDGETS(512)")
    if len(seen) > 256:
        print("!! 资源数超过 PLCUI_MAX_RESOURCES(256)")

    # 资源短名 -> 设计稿来源，方便以后排查"哪个 png 对应哪个按钮"
    if ASSET_MAP:
        map_path = os.path.join(HERE, "asset_map.txt")
        with open(map_path, "w", encoding="utf-8", newline="\n") as fp:
            fp.write("# name  source(page widget state)  bytes\n")
            for name in sorted(ASSET_MAP):
                fp.write(f"{name}  {ASSET_MAP[name]}  {len(name.encode())}\n")
        print(f"写出 {map_path}")

    # 文件名长度自检（<= NAME_MAX 字节）
    long_names = [f for f in os.listdir(OUT)
                  if len(f.encode("utf-8")) > NAME_MAX]
    if long_names:
        print("!! 以下文件名超过 23 字节:", long_names)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
