"""由 ui_spec.py 生成 design/index.html（1024x600 的浏览器可交互原型）。

用法（工程根目录）：
    python tools/gen_html.py

原型与 main.xml 同源（都是 ui_spec.py），所以浏览器里看到的坐标、尺寸、文案
与设备上完全一致。素材直接引用 ../code/*.png（烘图产物），不做二次绘制。

浏览器里可操作的部分：三个页面互切、按钮按下态、点击后顶栏状态文字反馈。
超出 PLCUI 能力的部分见 design/fallback.md。
"""

import html
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DESIGN = os.path.join(ROOT, "design")
sys.path.insert(0, HERE)

import ui_spec as S  # noqa: E402

CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #060C13; font-family: "Microsoft YaHei", "hzfont", sans-serif;
       display: flex; align-items: center; justify-content: center; min-height: 100vh; }
#stage { position: relative; width: 1024px; height: 600px; overflow: hidden;
         box-shadow: 0 18px 60px rgba(0,0,0,.7); }
.page { position: absolute; inset: 0; display: none; }
.page.on { display: block; }
.w { position: absolute; overflow: hidden; }
.w img { width: 100%; height: 100%; display: block; }
.w.btn { cursor: pointer; }
.w.btn:active img { filter: brightness(.72); }
.w.lbl { white-space: nowrap; }
.w.box { }
.w.chart { border: 0; }
.w.chart .grid { position: absolute; inset: 0;
  background-image: repeating-linear-gradient(to bottom, #1B3348 0 1px, transparent 1px 25%),
                    repeating-linear-gradient(to right, #1B3348 0 1px, transparent 1px 20%); }
.w.chart .tip { position: absolute; left: 6px; top: 4px; font-size: 14px; color: #4F7A98; }
.w.tbl { display: grid; }
.w.tbl div { font-size: 20px; color: #E6F1FB; display: flex; align-items: center;
             justify-content: center; border-right: 1px solid #1E3A52;
             border-bottom: 1px solid #1E3A52; }
.w.tbl div.head { background: #16293A; color: #C7DCF0; }
#hint { position: fixed; left: 50%; transform: translateX(-50%); bottom: 14px;
        color: #4F7A98; font-size: 13px; letter-spacing: .5px; }
"""

JS = """
var PAGES = %(pages)s;
function show(id) {
  document.querySelectorAll('.page').forEach(function (p) {
    p.classList.toggle('on', p.id === 'page-' + id);
  });
  window.__page = id;
}
function fire(ev, name, target) {
  if (PAGES[name]) { show(PAGES[name]); return; }
  var badge = document.querySelector('#page-' + window.__page + ' #badge-' + window.__page);
  if (badge) { badge.textContent = '模拟点击 ' + name; }
  console.log('click', ev, name);
}
"""


def esc(text):
    return html.escape(text, quote=True)


def render_widget(w):
    tag = w["tag"]
    style = "left:%dpx;top:%dpx;width:%dpx;height:%dpx;" % (w["x"], w["y"], w["w"], w["h"])
    base = 'class="w '
    if tag == "image":
        cls = base + ('btn" ' if w.get("clickable") else '" ')
        ev = w.get("on-click")
        act = ' onclick="fire(\'%s\', \'%s\', this)"' % (ev, ev) if ev else ""
        pressed = w.get("src-pressed")
        extra = ""
        if pressed:
            extra = ' data-pressed="%s"' % pressed
        return ('<div id="%s" %sstyle="%s" data-plcui="image" data-raster="yes" '
                'data-asset="html" data-asset-src="gen"%s%s>'
                '<img src="../code/%s" alt=""></div>'
                % (w["id"], cls, style, extra, act, S.filename(w["src"])))
    if tag == "animimg":
        frames = w.get("frames") or []
        first = S.filename(frames[0]) if frames else ""
        hidden = "display:none;" if w.get("hidden") == "true" else ""
        return ('<div id="%s" %s" style="%s%s" data-plcui="animimg">'
                '<img src="../code/%s" alt=""></div>'
                % (w["id"], base, style, hidden, first))
    if tag == "label":
        color = w.get("color", "#FFFFFF")
        size = w.get("font_size", 16)
        align = {"left": "left", "center": "center", "right": "right"}[w.get("align", "left")]
        hidden = "display:none;" if w.get("hidden") == "true" else ""
        pad = "padding-top:%dpx;" % max(0, (w["h"] - size) // 2 - 2)
        return ('<div id="%s" %s lbl" style="%s%sfont-size:%dpx;color:%s;text-align:%s;'
                'line-height:1.2;%s" data-plcui="label">%s</div>'
                % (w["id"], base, style, hidden, size, color, align, pad, esc(w.get("text", ""))))
    if tag == "container":
        radius = w.get("radius", 0)
        return ('<div id="%s" %s box" style="%sbackground:%s;border:%dpx solid %s;'
                'border-radius:%dpx;" data-plcui="container"> </div>'
                % (w["id"], base, style, w.get("background", "transparent"),
                   w.get("border-width", 1), w.get("border-color", "transparent"), radius))
    if tag == "chart":
        return ('<div id="%s" %s chart" style="%s" data-plcui="chart">'
                '<div class="grid"></div><div class="tip">chart %s（%s, %d 点）</div></div>'
                % (w["id"], base, style, w["id"], w.get("type"), w.get("point-count")))
    if tag == "table":
        cols = [int(v) for v in w["col-widths"].split(",")]
        rows = w["rows"]
        cells = {}
        for (r, c, text) in w.get("cells", []):
            cells[(r, c)] = text
        parts = ['<div id="%s" class="w tbl" style="%sbackground:%s;border:1px solid %s;'
                 'grid-template-columns:%s;grid-template-rows:repeat(%d,1fr);" '
                 'data-plcui="table">'
                 % (w["id"], style, w.get("background"), w.get("border-color"),
                    " ".join("%dpx" % c for c in cols), rows)]
        for r in range(1, rows + 1):
            for c in range(1, len(cols) + 1):
                cls = ' class="head"' if r == 1 else ""
                parts.append("<div%s>%s</div>" % (cls, esc(cells.get((r, c), ""))))
        parts.append("</div>")
        return "".join(parts)
    return ""


def build():
    pages = {p["id"]: p for p in S.PAGES}
    nav = {"go_run": "run", "go_trend": "trend", "go_man": "man",
           "go_dev": "dev", "go_test": "test"}
    out = ["<!DOCTYPE html>", '<html lang="zh-CN">', "<head>", '<meta charset="utf-8">',
           "<title>蒸气压测定仪 PLCUI 原型 1024x600</title>",
           "<style>%s</style>" % CSS, "</head>", "<body>", '<div id="stage">']
    for page in S.PAGES:
        out.append('<div class="page%s" id="page-%s" style="background:%s">'
                   % (" on" if page["id"] == S.ENTRY else "", page["id"],
                      page["background"]))
        for w in page["widgets"]:
            if w["id"] == "tb_badge":
                badge = dict(w)
                badge["id"] = "badge-" + page["id"]
                out.append(render_widget(badge))
            else:
                out.append(render_widget(w))
        out.append("</div>")
    out.append("</div>")
    out.append('<div id="hint">1024 x 600 原型：按底部按钮切页，'
               '点击其它按钮只做状态反馈（PLCUI 交互由 main.lua 实现）</div>')
    out.append("<script>%s</script>" % (JS % {"pages": str(nav).replace("'", '"')}))
    out.append("</body></html>")
    return "\n".join(out)


def main():
    os.makedirs(DESIGN, exist_ok=True)
    path = os.path.join(DESIGN, "index.html")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(build())
    print("原型已写入 %s（页 %d）" % (path, len(S.PAGES)))


if __name__ == "__main__":
    main()
