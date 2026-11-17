"""由 ui_spec.py 生成 code/main.xml 与 design/spec.md。

用法（在工程根目录）：
    python tools/gen_xml.py

main.xml 是产物，不许手改：要改布局就改 ui_spec.py 再重新生成，
否则坐标、素材、事件三样必然和清单漂移（SKILL.md 环节④）。
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CODE = os.path.join(ROOT, "code")
DESIGN = os.path.join(ROOT, "design")
sys.path.insert(0, HERE)

import ui_spec as S  # noqa: E402

ORDER = ("id", "x", "y", "w", "h")


def attrs(w):
    out = []
    for k in ORDER:
        if k in w:
            out.append('%s="%s"' % (k, w[k]))
    for k, v in w.items():
        if k in ORDER or k in ("tag", "series", "cells", "frames"):
            continue
        out.append('%s="%s"' % (k, v))
    return " ".join(out)


def used_resources():
    """全部生成素材都要在 <resources> 里声明。

    set_src 只能引用已声明的资源 ID，而阀门指示灯、步骤条三态、状态灯三态
    是运行时切换的，XML 里只出现其中一个初态，漏声明就会在真机上 E_RESOURCE。
    """
    ids = []
    seen = set()
    for rid, _size, _note in S.ASSETS:
        if rid not in seen:
            seen.add(rid)
            ids.append(rid)
    return ids


def build_xml():
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<ui version="0.1" width="%d" height="%d" entry="%s">' % (S.W, S.H, S.ENTRY),
             '  <resources>',
             '    <font id="hzfont" builtin="hzfont"/>']
    for rid in used_resources():
        lines.append('    <image id="%s" src="%s"/>' % (rid, S.filename(rid)))
    lines.append('  </resources>')
    lines.append('  <pages>')
    for page in S.PAGES:
        lines.append('    <page id="%s" background="%s">' % (page["id"], page["background"]))
        for w in page["widgets"]:
            tag = w["tag"]
            a = attrs(w)
            series = w.get("series")
            cells = w.get("cells")
            frames = w.get("frames")
            if series is None and cells is None and frames is None:
                lines.append('      <%s %s/>' % (tag, a))
                continue
            lines.append('      <%s %s>' % (tag, a))
            if series:
                for s in series:
                    lines.append('        <series id="%s" color="%s" values="%s"/>'
                                 % (s["id"], s["color"], s["values"]))
            if cells:
                for (r, c, text) in cells:
                    lines.append('        <cell row="%d" column="%d" text="%s"/>'
                                 % (r, c, text))
            if frames:
                for src in frames:
                    lines.append('        <frame src="%s"/>' % src)
            lines.append('      </%s>' % tag)
        lines.append('    </page>')
    lines.append('  </pages>')
    lines.append('</ui>')
    return "\n".join(lines) + "\n"


def build_spec_md():
    total = sum(len(p["widgets"]) for p in S.PAGES)
    out = ["# 版面与素材清单（制品，由 tools/gen_xml.py 从 ui_spec.py 生成）", "",
           "目标机型 Air8607（Air1603）+ 10 寸 RGB 1024×600 + GT911 电容触摸；",
           "画布 1024×600 固定分辨率，绝对定位，坐标全部落在 4px 栅格。", "",
           "| 项 | 值 |", "| --- | --- |",
           "| 页面数 | %d（%s） |" % (len(S.PAGES), " / ".join(p["id"] for p in S.PAGES)),
           "| 组件累计 | %d / 512（整份文档跨页相加） |" % total,
           "| 资源数 | 图片 %d + 字体 1 / 256 |" % len(used_resources()),
           "| 事件处理函数 | %d 个 |" % len(S.EVENTS), ""]
    out += ["## 素材清单", "", "| 资源 ID | 尺寸 | 像素占用 | 用途 |", "| --- | --- | --- | --- |"]
    for rid, size, note in S.ASSETS:
        if rid in S.BTN_TEXT:
            out.append("| `%s` / `%s_p` | %d×%d | %d KB | %s |"
                       % (rid, rid, size[0], size[1],
                          size[0] * size[1] * 4 // 1024, note))
        else:
            out.append("| `%s` | %d×%d | %d KB | %s |"
                       % (rid, size[0], size[1], size[0] * size[1] * 4 // 1024, note))
    out += ["", "## 页面元素", ""]
    for page in S.PAGES:
        out += ["### %s（%d 个组件）" % (page["id"], len(page["widgets"])), "",
                "| 组件 | ID | x | y | w | h | 说明 |", "| --- | --- | --- | --- | --- | --- | --- |"]
        for w in page["widgets"]:
            note = w.get("text") or w.get("src") or ""
            out.append("| %s | `%s` | %d | %d | %d | %d | %s |"
                       % (w["tag"], w["id"], w["x"], w["y"], w["w"], w["h"], note))
        out.append("")
    return "\n".join(out) + "\n"


def main():
    os.makedirs(CODE, exist_ok=True)
    os.makedirs(DESIGN, exist_ok=True)
    xml = build_xml()
    with open(os.path.join(CODE, "main.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write(xml)
    with open(os.path.join(DESIGN, "spec.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(build_spec_md())
    print("main.xml %d 字节；组件 %d 个；资源 %d 个"
          % (len(xml.encode("utf-8")),
             sum(len(p["widgets"]) for p in S.PAGES), len(used_resources())))


if __name__ == "__main__":
    main()
