"""plcui 素材导出：把 web/*.html 注塑产线设计稿导出为 plcui 的 main.xml + 图片资源。

工作方式
--------
1. 用 Playwright 打开每个页面（固定 1024x600 视口，deviceScaleFactor=1）。
2. 隐藏/清空所有动态组件后整页截图 -> 页面背景图（bg_ov.jpg 等）。
   - .plc 控件（label/image/chart/table）整块隐藏
   - input 型参数框只清空 value，保留边框底色（PLCUI textarea 无背景属性）
   - 表格开关单元格文字透明保留底色，按钮图自带文字
3. 逐个组件按包围盒裁剪截图 -> 按钮/开关/机台选择/导航状态图（normal/pressed/checked）。
   pressed 态通过注入 CSS filter 加亮；checked 态切换 .on 类或单元格文字。
4. 工艺阶段条 anim_phase_0..6 逐态整条截图；温压条形动画帧 bar<宽>_<色>_0..9 共享帧；
   传送带动画帧 anim_belt_0..7 用 PIL 几何作图（透明流光点）。
5. 读取每个组件的位置与 data-* 元数据，生成 main.xml（5 page，entry=ov）。

用法
----
    python tools/export_assets.py            # 导出全部页面
    python tools/export_assets.py mc         # 只导出指定页面（XML 仍输出全部）
"""

import os
import re
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WEB = os.path.join(ROOT, "web")
OUT = os.path.join(ROOT, "code", "res")  # 图片 + main.xml 与真机 /res/ 一致

WIDTH, HEIGHT = 1024, 600

# 文件名 / 资源 id 上限（字节）。Air8607 的 luadb 与 VFS 要求 <= 23 字节
NAME_MAX = 23

STATE_SHORT = {"normal": "n", "pressed": "p", "checked": "c"}

# page id -> (html 文件, 短码, 是否入口页)
PAGES = [
    ("ov", "index.html", "ov", True),
    ("mc", "mc.html", "mc", False),
    ("ctl", "ctl.html", "ctl", False),
    ("pr", "pr.html", "pr", False),
    ("rc", "rc.html", "rc", False),
]

SHORT = {pid: short for pid, _, short, _ in PAGES}

# 传送带动画帧几何（透明 PNG，8 帧由 Lua 定时器轮播）
ANIM_W, ANIM_H = 756, 36
ANIM_FRAMES = 8
ANIM_DOT_GAP = 189.0

# 温压/输出条形动画帧：(组名, 槽宽, 用于截图的 HTML 元素 id)
# 帧 i 表示 fill 档位 i（0~9 对应 4%~94%），同组的所有 bar 控件共享这 10 帧
BAR_GROUPS = [
    ("bar230_g", 230, "bar-t1"),
    ("bar230_y", 230, "bar-t4"),
    ("bar230_o", 230, "bar-p1"),
    ("bar170_g", 170, "bar-ao1"),
    ("bar170_o", 170, "bar-ao2"),
]
BAR_LEVELS = 10

# bar 元素 id -> 帧组（由 BAR_GROUPS 推导，导出后回填）
BAR_OF = {}

# data-sw 单元格顺序（生成 sw_1..sw_10 控件与 Lua 侧业务键）
SW_KEYS = ["im1", "im2", "im3", "rob", "belt", "dryer", "chiller", "moldtemp", "packer", "gran"]

# ---------------------------------------------------------------- 图表初始数据
# key = "page:widget"，value = {series_id: [数值...]}（与 XML point-count 一致）
CHARTS = {
    "mc:chart_t": {
        "t1": [210, 211, 209, 210, 212, 211, 210, 209, 211, 212, 210, 211, 209,
               210, 211, 212, 210, 209, 210, 211, 210, 209, 211, 210, 210],
        "t2": [215, 216, 214, 215, 217, 216, 215, 214, 216, 217, 215, 216, 214,
               215, 216, 217, 215, 214, 215, 216, 215, 214, 216, 215, 215],
        "t5": [225, 226, 224, 225, 227, 226, 225, 224, 226, 227, 225, 226, 224,
               225, 226, 227, 225, 224, 225, 226, 225, 224, 226, 225, 225],
    },
    "mc:chart_p": {
        "p1": [125, 128, 122, 126, 130, 127, 124, 121, 125, 129, 126, 123, 120,
               124, 128, 127, 125, 122, 126, 129, 125, 123, 127, 126, 125],
        "p2": [85, 87, 83, 86, 88, 86, 84, 82, 85, 87, 86, 84, 82,
               85, 87, 86, 85, 83, 86, 87, 85, 84, 86, 85, 85],
    },
}

# chart 控件属性：page:widget -> (point-count, y-min, y-max, [(series, color)...])
CHART_SPEC = {
    "mc:chart_t": (25, 180, 240, [("t1", "#29d8f0"), ("t2", "#2ee6a0"), ("t5", "#ffa62b")]),
    "mc:chart_p": (25, 0, 200, [("p1", "#ffa62b"), ("p2", "#ff6b81")]),
}

# ---------------------------------------------------------------- 表格初始数据
# 由 HTML 表格 DOM 收集，此处只存样式常量（注入产线深青主题）
TABLE_STYLE = {
    "background": "#0a1c28", "border-color": "#1e4a5e", "header-color": "#123a4c",
    "alternate-color": "#0d2534", "border-width": "1", "cell-padding": "5",
    "row-height": "30", "font_size": "13", "color": "#cfe9f5",
}
# table 列宽/对齐（page:widget -> (widths, aligns)）
TABLE_SPEC = {
    "rc:tb_shift": ("56,90,80,80,72,64,72,74", "center,center,center,center,center,center,center,center"),
    "rc:tb_alarm": ("92,64,96,276,72", "center,center,center,left,center"),
    "rc:tb_oper": ("80,194", "center,left"),
}


def norm_color(c):
    """computed style 的 rgb(r,g,b) 转 #rrggbb；#rrggbb 原样返回。"""
    c = (c or "").strip()
    if not c:
        return ""
    if c.startswith("#"):
        return c
    m = re.match(r"rgba?\((\d+),\s*(\d+),\s*(\d+)", c)
    if m:
        return "#{:02x}{:02x}{:02x}".format(*[int(v) for v in m.groups()])
    return ""


def norm_align(a):
    a = (a or "").strip().lower()
    return a if a in ("left", "center", "right") else "left"

ASSET_MAP = {}


def res_name(page_id, key, state):
    """资源名：<页面短码>_<组件短名>_<状态首字母>，例如 ctl_btn_start_n（14 字节）。
    nav_ 前缀的导航按钮图全局共享（5 页同图），不带页前缀。"""
    if key.startswith("nav_"):
        name = f"{key}_{STATE_SHORT[state]}"
    else:
        name = f"{SHORT[page_id]}_{key}_{STATE_SHORT[state]}"
    if len(name.encode("utf-8")) > NAME_MAX:
        raise SystemExit(f"资源名超长（{len(name.encode())} 字节 > {NAME_MAX}）: {name}")
    return name


def esc(text):
    return (str(text)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;"))


def collect_script():
    """在页面里找出所有可导出组件（.plc + 导航/开关/机台选择/阶段条/条形）。"""
    return """
() => {
  const out = {widgets: [], bars: [], phase: null};
  const rect = (el) => {
    const r = el.getBoundingClientRect();
    return {x: Math.round(r.x), y: Math.round(r.y),
            w: Math.round(r.width), h: Math.round(r.height)};
  };
  // 导航 tab：injectNav 动态生成，补上 plc 标记导出为 image 按钮
  document.querySelectorAll('.nav .nb').forEach((el, i) => {
    const code = ['ov','mc','ctl','pr','rc'][i] || ('n' + i);
    el.dataset.type = 'image'; el.dataset.id = 'nav_' + code;
    el.dataset.states = 'normal,checked'; el.dataset.handler = 'show_' + code;
  });
  // 机台选择按钮
  document.querySelectorAll('.btn[data-sel]').forEach((el) => {
    const n = el.dataset.sel;
    el.dataset.type = 'image'; el.dataset.id = 'sel_m' + n;
    el.dataset.states = 'normal,checked'; el.dataset.handler = 'sel_m' + n;
  });
  // 单机开关（表格单元格）：n 态“启动”绿，c 态“停止”黄
  document.querySelectorAll('td[data-sw]').forEach((el, i) => {
    el.dataset.type = 'image'; el.dataset.id = 'sw_' + (i + 1);
    el.dataset.states = 'normal,checked'; el.dataset.handler = 'sw_' + el.dataset.sw;
    el.dataset.swtext = '1';
  });
  document.querySelectorAll('.plc, .nav .nb, .btn[data-sel], td[data-sw]').forEach((el) => {
    const d = el.dataset;
    const cs = getComputedStyle(el);
    const r = rect(el);
    const item = {
      id: d.id, type: d.type,
      x: r.x, y: r.y, w: r.w, h: r.h,
      text: (el.tagName === 'INPUT' ? el.value : (el.textContent || '')).trim(),
      fontsize: parseInt(d.fontsize || cs.fontSize || '12', 10),
      color: d.color || cs.color || '',
      align: d.align || cs.textAlign || '',
      handler: d.handler || '',
      states: d.states || '',
      keyboard: d.kb || '',
      swtext: d.swtext || '',
      chart: d.chart || 'line',
      series: d.series || ''
    };
    if (el.tagName === 'TABLE') {
      item.rows = [];
      el.querySelectorAll('tr').forEach((tr) => {
        const row = [];
        tr.querySelectorAll('th,td').forEach((c) => row.push((c.textContent || '').trim()));
        item.rows.push(row);
      });
      const r0 = el.querySelectorAll('tr');
      item.nrows = r0.length;
      item.ncols = r0.length ? r0[0].children.length : 1;
    }
    if (d.type === 'textarea') {
      const r2 = rect(el);
      item.w = r2.w; item.h = Math.max(r2.h, 24);
    }
    out.widgets.push(item);
  });
  // 条形槽（.bar 的子 .fill）：导出共享动画帧用
  document.querySelectorAll('.bar .fill').forEach((el) => {
    const bar = el.parentElement;
    const r = rect(bar);
    out.bars.push({id: el.id, x: r.x, y: r.y, w: r.w, h: r.h,
                   cls: el.className.replace('fill', '').trim()});
  });
  // 工艺阶段条
  const ph = document.getElementById('phase-bar');
  if (ph) out.phase = rect(ph);
  return out;
}
"""


def hide_style(css):
    return """(sel) => {
      let s = document.getElementById('__export_style');
      if (!s) { s = document.createElement('style'); s.id = '__export_style'; document.head.appendChild(s); }
      s.textContent = sel;
    }"""


HIDE_ALL = """
.plc:not([data-anim]):not(input), .nav .nb, .btn[data-sel], #phase-bar {visibility:hidden !important;}
input.plc {visibility:visible !important; color:transparent !important; caret-color:transparent !important;}
td[data-sw] {color:transparent !important;}
"""

# 按钮态截图的基础样式：全部隐藏（显示单个元素走行内 !important，
# CSS 的 [data-id] 选择器特异性(0,1,0)打不过 .plc:not(...)(0,2,1)/.nav .nb(0,2,0)）
HIDE_BTNS = """
.plc:not([data-anim]), .nav .nb, .btn[data-sel], #phase-bar {visibility:hidden !important;}
.st-pressed {filter:brightness(1.55) saturate(1.15) !important;}
"""

CLEAR_INPUTS = """() => {
  document.querySelectorAll('input.plc').forEach((el) => {
    el.dataset.savedValue = el.value; el.value = '';
  });
}"""

SET_INPUTS_BACK = """() => {
  document.querySelectorAll('input.plc').forEach((el) => {
    if (el.dataset.savedValue !== undefined) el.value = el.dataset.savedValue;
  });
}"""


def launch(playwright):
    last = None
    for kwargs in ({"channel": "msedge"}, {"channel": "chrome"}, {}):
        try:
            return playwright.chromium.launch(**kwargs)
        except Exception as exc:  # noqa: BLE001
            last = exc
    raise last
def write_belt_frames(out_dir):
    """传送带光点帧：透明底，青绿光点沿带面中心线流动。"""
    names = []
    for frame in range(ANIM_FRAMES):
        im = Image.new("RGBA", (ANIM_W, ANIM_H), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        cy = ANIM_H // 2
        phase = frame * ANIM_DOT_GAP / ANIM_FRAMES
        g = (43, 255, 158)
        i = -1
        while i * ANIM_DOT_GAP + phase < ANIM_W + 14:
            x = i * ANIM_DOT_GAP + phase
            if x > -14:
                for r, a in ((10, 24), (6, 70), (3, 235)):
                    d.ellipse([x - r, cy - r, x + r, cy + r], fill=g + (a,))
            i += 1
        name = f"anim_belt_{frame}"
        im.save(os.path.join(out_dir, f"{name}.png"))
        names.append(name)
    return names


def shot(page, path, x, y, w, h):
    page.screenshot(path=path, clip={"x": x, "y": y, "width": w, "height": h})


def export_page(browser, page_id, html, exported, verbose):
    url = "file:///" + os.path.join(WEB, html).replace(os.sep, "/")
    page = browser.new_page(viewport={"width": WIDTH, "height": HEIGHT},
                            device_scale_factor=1)
    page.goto(url)
    page.wait_for_timeout(500)   # 等 injectNav / render 完成
    data = page.evaluate(collect_script())

    os.makedirs(OUT, exist_ok=True)

    # ---- 背景（隐藏全部动态组件，参数框清空保留边框）----
    page.evaluate(CLEAR_INPUTS)
    page.evaluate(hide_style(""), HIDE_ALL)
    page.wait_for_timeout(120)
    bg_png = os.path.join(OUT, "_bg_tmp.png")
    shot(page, bg_png, 0, 0, WIDTH, HEIGHT)
    bg_id = f"bg_{SHORT[page_id]}"
    Image.open(bg_png).convert("RGB").save(
        os.path.join(OUT, f"{bg_id}.jpg"), "JPEG", quality=88, subsampling=0,
        progressive=False)
    os.remove(bg_png)

    assets = [(bg_id, f"{bg_id}.jpg")]

    # ---- 按钮/开关/机台选择/导航 状态图 ----
    def show_only(wid):
        page.evaluate(hide_style(""), HIDE_BTNS)
        page.evaluate("""(id) => {
          document.querySelectorAll('[data-id]').forEach((el) => {
            el.style.removeProperty('visibility');
          });
          document.querySelectorAll(`[data-id="${id}"]`).forEach((el) => {
            el.style.setProperty('visibility', 'visible', 'important');
          });
        }""", wid)

    def set_state(wid, state, is_sw):
        """切换元素到指定态：pressed 加亮 / checked 切 .on 或单元格文字。"""
        page.evaluate("""([id, state, isSw]) => {
          const el = document.querySelector(`[data-id="${id}"]`);
          el.classList.remove('st-pressed');
          if (isSw) {
            if (state === 'checked') { el.textContent = '停止'; el.className = 'st-y'; }
            else { el.textContent = '启动'; el.className = 'st-g'; }
            return;
          }
          if (state === 'checked') el.classList.add('on');
          else el.classList.remove('on');
          if (state === 'pressed') el.classList.add('st-pressed');
        }""", [wid, state, is_sw])

    for w in data["widgets"]:
        if w["type"] != "image" or not w["states"]:
            continue   # anim_belt 等无态图元走动画帧流程
        key = w["id"]
        states = [s for s in w["states"].split(",") if s] or ["normal"]
        is_sw = w.get("swtext") == "1"
        for state in states:
            name = res_name(page_id, key, state)
            ASSET_MAP.setdefault(name, f"{page_id} {w['id']} {state}")
            if name in exported:
                assets.append((name, f"{name}.png"))
                continue
            exported.add(name)
            show_only(w["id"])
            set_state(w["id"], state, is_sw)
            page.wait_for_timeout(50)
            shot(page, os.path.join(OUT, f"{name}.png"),
                 w["x"], w["y"], w["w"], w["h"])
            assets.append((name, f"{name}.png"))
        # 复位
        page.evaluate("""(id) => {
          const el = document.querySelector(`[data-id="${id}"]`);
          el.classList.remove('st-pressed', 'on');
          if (el.dataset.swtext) { el.textContent = '停止'; el.className = 'st-y'; }
        }""", w["id"])

    # ---- 工艺阶段条整条多态帧 ----
    if data.get("phase"):
        pr_ = data["phase"]
        page.evaluate(hide_style(""), HIDE_BTNS)
        page.evaluate("""() => {
          let s = document.getElementById('__export_style');
          s.textContent += '\\n#phase-bar{visibility:visible !important;}';
        }""")
        for k in range(7):
            name = f"anim_phase_{k}"
            if name in exported:
                assets.append((name, f"{name}.png"))
                continue
            exported.add(name)
            page.evaluate("""(k) => {
              const phs = document.querySelectorAll('#phase-bar .ph');
              phs.forEach((p, i) => {
                p.className = 'ph' + (i < k ? ' done' : i === k ? ' act' : '');
              });
            }""", k)
            page.wait_for_timeout(40)
            shot(page, os.path.join(OUT, f"{name}.png"),
                 pr_["x"], pr_["y"], pr_["w"], pr_["h"])
            assets.append((name, f"{name}.png"))

    # ---- 温压/输出条形共享动画帧 ----
    bar_by_id = {b["id"]: b for b in data["bars"] if b["id"]}
    for group, width, sample in BAR_GROUPS:
        b = bar_by_id.get(sample)
        if not b:
            continue
        for lvl in range(BAR_LEVELS):
            name = f"{group}_{lvl}"
            if name in exported:
                assets.append((name, f"{name}.png"))
                continue
            exported.add(name)
            page.evaluate(hide_style(""), HIDE_BTNS)
            page.evaluate("""([id, pct]) => {
              let s = document.getElementById('__export_style');
              s.textContent += '\\n#' + id + ' {visibility:visible !important;}';
              const el = document.getElementById(id);
              if (el) el.style.width = pct + '%';
            }""", [sample, max(4, min(98, lvl * 10 + 5))])
            page.wait_for_timeout(40)
            shot(page, os.path.join(OUT, f"{name}.png"),
                 b["x"], b["y"], b["w"], b["h"])
            assets.append((name, f"{name}.png"))

    page.evaluate(SET_INPUTS_BACK)
    page.close()
    if verbose:
        print(f"  {page_id}: {len(data['widgets'])} 组件, {len(assets)} 张资源")
    return data, assets
def bar_group_of(b):
    """条形 fill 元素 -> 共享帧组名 bar<宽>_<色>。"""
    cls = b.get("cls", "g") or "g"
    return f"bar{b['w']}_{cls}"


def bar_init_level(b):
    return 5   # 初始 55% 档，Lua tick 会立刻按实测值刷新


def widget_xml(page_id, w, resources):
    wid = w["id"].replace("-", "_")
    attrs = [f'id="{wid}"', f'x="{w["x"]}"', f'y="{w["y"]}"',
             f'w="{w["w"]}"', f'h="{w["h"]}"']
    if w["type"] == "label":
        attrs += ['font="hzfont"', f'font_size="{w["fontsize"]}"',
                  f'color="{norm_color(w["color"]) or "#ffffff"}"',
                  f'align="{norm_align(w["align"])}"',
                  f'text="{esc(w["text"])}"']
        return "      <label " + " ".join(attrs) + "/>"

    if w["type"] == "textarea":
        attrs += ['font="hzfont"', f'font_size="{w["fontsize"] or 15}"',
                  f'color="{norm_color(w["color"]) or "#ffd479"}"',
                  f'align="{norm_align(w["align"])}"',
                  'one-line="true"', 'max-length="7"',
                  'accepted-chars="0123456789."', 'keyboard="kb_num"',
                  'on-submit="par_submit"', 'on-cancel="par_cancel"',
                  f'text="{esc(w["text"])}"']
        return "      <textarea " + " ".join(attrs) + "/>"

    if w["type"] == "image":
        states = [s for s in w["states"].split(",") if s] or ["normal"]
        if wid == "anim_belt":
            return '      <image id="anim_belt" x="%d" y="%d" w="%d" h="%d" src="anim_belt_0"/>' % (
                w["x"], w["y"], w["w"], w["h"])
        attrs.append(f'src="{res_name(page_id, w["id"], "normal")}"')
        for state, attr in (("pressed", "src-pressed"), ("checked", "src-checked")):
            if state in states:
                attrs.append(f'{attr}="{res_name(page_id, w["id"], state)}"')
        if w["handler"]:
            attrs += ['clickable="true"', f'on-click="{w["handler"]}"']
        return "      <image " + " ".join(attrs) + "/>"

    if w["type"] == "chart":
        pts, ymin, ymax, series = CHART_SPEC[f"{page_id}:{w['id']}"]
        attrs += [f'type="{w["chart"]}"', f'point-count="{pts}"',
                  f'y-min="{ymin}"', f'y-max="{ymax}"',
                  'hdiv="4"', 'vdiv="0"', 'bg-opacity="0"', 'line-width="2"',
                  'grid-color="#1d5871"']
        head = "      <chart " + " ".join(attrs) + ">\n"
        values = CHARTS.get(f'{page_id}:{w["id"]}', {})
        body = ""
        for sid, color in series:
            vals = values.get(sid, [0] * pts)
            body += (f'        <series id="{sid}" color="{color}" values="'
                     + ",".join(str(v) for v in vals) + '"/>\n')
        return head + body + "      </chart>"

    if w["type"] == "table":
        rows = w.get("rows", [])
        nrows = w.get("nrows") or len(rows)
        ncols = w.get("ncols") or (len(rows[0]) if rows else 1)
        widths, aligns = TABLE_SPEC.get(f"{page_id}:{w['id']}", ("", ""))
        attrs += [f'rows="{nrows}"', f'columns="{ncols}"', 'font="hzfont"',
                  f'font_size="{TABLE_STYLE["font_size"]}"',
                  f'color="{TABLE_STYLE["color"]}"',
                  f'background="{TABLE_STYLE["background"]}"',
                  f'border-color="{TABLE_STYLE["border-color"]}"',
                  f'header-color="{TABLE_STYLE["header-color"]}"',
                  f'alternate-color="{TABLE_STYLE["alternate-color"]}"',
                  f'border-width="{TABLE_STYLE["border-width"]}"',
                  f'cell-padding="{TABLE_STYLE["cell-padding"]}"',
                  f'row-height="{TABLE_STYLE["row-height"]}"',
                  'header="true"', 'grid="false"', 'header-align="center"']
        if widths:
            attrs.append(f'col-widths="{widths}"')
        if aligns:
            attrs.append(f'col-aligns="{aligns}"')
        head = "      <table " + " ".join(attrs) + ">\n"
        body = ""
        for r, row in enumerate(rows, start=1):
            for c, cell in enumerate(row, start=1):
                body += (f'        <cell row="{r}" column="{c}" '
                         f'text="{esc(cell)}"/>\n')
        return head + body + "      </table>"

    raise ValueError(f"unsupported type {w['type']}")


def gen_page_xml(page_id, data, resources):
    lines = [f'    <page id="{page_id}" background="#0a1622">',
             f'      <image id="bg" x="0" y="0" w="{WIDTH}" h="{HEIGHT}" '
             f'src="bg_{SHORT[page_id]}"/>']
    for w in data["widgets"]:
        if w["type"] == "image" and w["id"] == "anim_belt":
            lines.append(widget_xml(page_id, w, resources))
    if data.get("phase"):
        p = data["phase"]
        lines.append(f'      <image id="anim_phase" x="{p["x"]}" y="{p["y"]}" '
                     f'w="{p["w"]}" h="{p["h"]}" src="anim_phase_0"/>')
    for b in data["bars"]:
        if not b["id"]:
            continue
        bid = b["id"].replace("-", "_")
        group = bar_group_of(b)
        lines.append(f'      <image id="{bid}" x="{b["x"]}" y="{b["y"]}" '
                     f'w="{b["w"]}" h="{b["h"]}" src="{group}_{bar_init_level(b)}"/>')
    for w in data["widgets"]:
        if w["type"] == "image" and w["id"] == "anim_belt":
            continue
        lines.append(widget_xml(page_id, w, resources))
    if page_id == "pr":
        lines.append('      <keyboard id="kb_num" x="214" y="330" w="596" h="180" '
                     'layout="number" font="hzfont" font_size="18" hidden="true"/>')
    lines.append("    </page>")
    return "\n".join(lines)


def collect_resources(all_assets):
    seen = {}
    for name, fn in all_assets:
        seen.setdefault(name, fn)
    return seen


def gen_xml(pages_data):
    resources = collect_resources([a for _, assets in pages_data.values() for a in assets])
    # 共享动画帧/条形帧全部注册（belt/phase/bar 由导出流程产出）
    out = []
    out.append('<?xml version="1.0" encoding="UTF-8"?>')
    out.append(f'<ui version="0.1" width="{WIDTH}" height="{HEIGHT}" entry="ov">')
    out.append("  <resources>")
    for name, fn in resources.items():
        out.append(f'    <image id="{name}" src="{fn}"/>')
    out.append("  </resources>")
    out.append("  <pages>")
    for pid, _, short, _ in PAGES:
        out.append(gen_page_xml(pid, pages_data[pid][0], resources))
    out.append("  </pages>")
    out.append("</ui>")
    return "\n".join(out) + "\n"


def validate(pages_data, xml_text):
    n_widgets = sum(len(d[0]["widgets"]) for d in pages_data.values())
    n_widgets += sum(2 for d in pages_data.values() if d[0].get("phase"))   # phase+bars 之外粗算
    ids = set()
    for pid, (data, assets) in pages_data.items():
        for w in data["widgets"]:
            wid = w["id"]
            if len(wid.encode()) > NAME_MAX:
                raise SystemExit(f"组件 id 超长: {wid}")
            key = (pid, wid)
            if key in ids:
                raise SystemExit(f"组件 id 重复: {pid} {wid}")
            ids.add(key)
        for name, _ in assets:
            if len(name.encode()) > NAME_MAX:
                raise SystemExit(f"资源名超长: {name}")
    n_res = xml_text.count("<image id=")
    print(f"控件约 {n_widgets} 个（上限 512），资源 {n_res} 个（上限 256）")
    if n_res > 256:
        raise SystemExit("资源数超限")


def main():
    only = set(sys.argv[1:])
    from playwright.sync_api import sync_playwright

    pages_data = {}
    exported = set()
    with sync_playwright() as pw:
        browser = launch(pw)
        for pid, html, short, entry in PAGES:
            if only and pid not in only:
                continue
            pages_data[pid] = export_page(browser, pid, html, exported, verbose=True)
        browser.close()

    # 未重导的页面用旧数据补全 XML（仅部分导出时）
    if only:
        print("注意：只导出了部分页面，XML 需全量导出后生成")
        return

    belt = write_belt_frames(OUT)
    all_assets = [a for _, assets in pages_data.values() for a in assets]
    for n in belt:
        all_assets.append((n, f"{n}.png"))
        pages_data["ov"][1].append((n, f"{n}.png"))   # 共享动画帧随 ov 页注册进 XML

    xml_text = gen_xml(pages_data)
    with open(os.path.join(OUT, "main.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write(xml_text)

    validate(pages_data, xml_text)
    total = sum(os.path.getsize(os.path.join(OUT, f)) for _, f in
                collect_resources(all_assets).items())
    print(f"main.xml 已生成，图片资源 {len(collect_resources(all_assets))} 个，共 {total/1024:.0f} KB")


if __name__ == "__main__":
    main()
