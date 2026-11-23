# -*- coding: utf-8 -*-
"""从效果稿 HTML 抽取「每屏 / 每容器 → 子元素」的坐标树（handoff 用）。

只做结构解析，不改任何文件。用法：
    python docs/dump_nodes.py docs/自助售币机UI效果稿.html
"""
import io
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "自助售币机UI效果稿.html"

TAG = re.compile(r"<(div|section|svg)([^>]*)>|</(div|section|svg)>")
ATTR = re.compile(r'([\w-]+)="([^"]*)"')
STYLE = re.compile(r"(left|top|width|height)\s*:\s*(-?\d+)(?:px)?")


def parse(attrs):
    a = dict(ATTR.findall(attrs))
    st = {}
    for k, v in STYLE.findall(a.get("style", "")):
        st[k] = int(v)
    return {
        "k": a.get("data-k", ""),
        "bw": a.get("data-bw", ""),
        "id": a.get("id", ""),
        "onclick": a.get("onclick", ""),
        "x": st.get("left"), "y": st.get("top"),
        "w": st.get("width"), "h": st.get("height"),
        "cls": a.get("class", ""),
        "fs": a.get("data-fs", ""),
        "text": re.sub(r"&nbsp;", " ", a.get("text") or "").strip(),
    }


lines = io.open(PATH, encoding="utf-8").read().split("\n")
stack = []          # [(node, depth)]
out = []
screen = "-"


def text_of(idx):
    """取该行标签后的可见文本（单行元素才有意义）"""
    return ""


for ln in lines:
    s = ln.strip()
    if not s:
        continue
    if s.startswith("<section") and "data-screen" in s:
        screen = dict(ATTR.findall(s)).get("data-screen", "?")
        out.append("")
        out.append("=== SCREEN %s ===" % screen)
        stack = []
        continue
    for m in TAG.finditer(s):
        if m.group(3):                      # 闭合
            if stack:
                stack.pop()
            continue
        tag, attrs = m.group(1), m.group(2)
        if tag == "section":
            stack.append((None, len(stack)))
            continue
        n = parse(attrs)
        depth = len([x for x in stack if x[0] is not None])
        # 文本：同一行标签之后的汉字
        tail = s[m.end():]
        txt = re.sub(r"<[^>]+>", "", tail)
        txt = txt.replace("&nbsp;", " ").strip()
        n["text"] = txt[:28]
        parent = next((x[0] for x in reversed(stack) if x[0] is not None), None)
        pl = ("%s[%d,%d %dx%d]" % (parent["k"] or parent["cls"][:10] or "?",
                                   parent["x"] or 0, parent["y"] or 0,
                                   parent["w"] or 0, parent["h"] or 0)) if parent else "root"
        out.append("%s%s | %s | %s,%s %sx%s bw=%s%s | %s | %s | %s" % (
            "  " * depth, n["k"] or "-", pl, n["x"], n["y"], n["w"], n["h"],
            n["bw"] or "0", ("#" + n["id"]) if n["id"] else "",
            n["text"] or "-", n["cls"], n["onclick"] or ""))
        stack.append((n, depth))

io.open(PATH + ".nodes.txt", "w", encoding="utf-8").write("\n".join(out))
print("nodes written:", len(out), "lines ->", PATH + ".nodes.txt")
