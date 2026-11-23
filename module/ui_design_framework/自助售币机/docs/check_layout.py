# -*- coding: utf-8 -*-
"""
效果稿机械校验：几何越界 + 真机能力黑名单 + 最小字号。
用法: python check_layout.py 自助售币机UI效果稿-light.html
判定基准见 .codebuddy/skills/airui-ui-flow/references/html-spec.md
"""
import os
import re
import sys
from html.parser import HTMLParser

VOID = {"img", "br", "hr", "input", "meta", "link", "path", "circle", "rect", "polyline", "line", "use"}

STYLE_RE = re.compile(r"(left|top|width|height)\s*:\s*(-?\d+(?:\.\d+)?)\s*(?:px)?")
FS_RE = re.compile(r"font-size\s*:\s*(\d+)\s*px")

BLACKLIST = [
    (r"linear-gradient|radial-gradient|conic-gradient", "渐变（真机无对应能力）"),
    (r"blur\(|backdrop-filter", "模糊（真机无对应能力）"),
    (r"font-weight", "字体粗细（airui.label 无此参数）"),
    (r"box-shadow", "阴影（真机只有实偏移块）"),
    (r":hover", "hover 态（触摸屏不存在）"),
    (r"transition\s*:", "过渡（真机无过渡）"),
    (r"transform\s*:\s*(rotate|scale)", "旋转/缩放变换（只允许展示外壳的 scale）"),
]

# 最小字号（AGENTS.md F2：中文最小 16）
FS_MIN = 16

# ===== 令牌对比度（AGENTS.md F6：块的轮廓 >= 1.4:1；填充也要能看出"面"）=====
TOKEN_BLOCK = re.compile(r"(:root|body\.light)\s*\{([^}]*)\}")
TOKEN_RE = re.compile(r"--([a-z_0-9]+)\s*:\s*#([0-9A-Fa-f]{6})")

# key, 中文名, 下限, 基准键
TOKEN_CHECKS = [
    ("card", "卡片填充", 1.40, "bg"),
    ("tile", "内嵌块填充", 1.20, "bg"),
    ("edge", "描边", 1.40, "bg"),
    ("divider", "分隔线", 1.15, "bg"),
    ("text", "正文", 4.50, "bg"),
    ("text_dim", "次要文字", 4.50, "bg"),
]


def _lum(hex6):
    def ch(v):
        c = v / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r = int(hex6[0:2], 16)
    g = int(hex6[2:4], 16)
    b = int(hex6[4:6], 16)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def ratio(hex_a, hex_b):
    la, lb = _lum(hex_a), _lum(hex_b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def check_tokens(html):
    table, bad = [], []
    for m in TOKEN_BLOCK.finditer(html):
        scope = "暗色" if m.group(1) == ":root" else "亮色"
        tok = dict((k.lower(), v) for k, v in TOKEN_RE.findall(m.group(2)))
        if "bg" not in tok:
            continue
        for key, name, need, base in TOKEN_CHECKS:
            if key not in tok or base not in tok:
                continue
            r = ratio(tok[key], tok[base])
            ok = r >= need
            table.append("  %s --%-9s %-10s %5.2f:1 (>= %.2f) %s"
                         % (scope, key, name, r, need, "OK" if ok else "LOW"))
            if not ok:
                bad.append("%s 的 --%s（%s）对 --%s 仅 %.2f:1 < %.2f"
                           % (scope, key, name, base, r, need))
    return table, bad


class Node:
    def __init__(self, tag, attrs, line):
        self.tag = tag
        self.attrs = attrs
        self.line = line
        self.kind = attrs.get("data-k")
        self.bw = int(attrs.get("data-bw") or 0)
        self.style = attrs.get("style") or ""
        m = dict(STYLE_RE.findall(self.style))
        self.x = int(float(m["left"])) if "left" in m else None
        self.y = int(float(m["top"])) if "top" in m else None
        self.w = int(float(m["width"])) if "width" in m else None
        self.h = int(float(m["height"])) if "height" in m else None
        fs = FS_RE.search(self.style)
        self.fs = int(fs.group(1)) if fs else None

    @property
    def label(self):
        tag = self.kind or self.tag
        return "%s%s" % (tag, ("#%s" % self.attrs["id"]) if "id" in self.attrs else "")


class P(HTMLParser):
    def __init__(self):
        HTMLParser.__init__(self)
        self.stack = []
        self.nodes = []

    def handle_starttag(self, tag, attrs):
        if tag in VOID:
            return
        a = dict(attrs)
        n = Node(tag, a, self.getpos()[0])
        self.nodes.append((n, list(self.stack)))
        self.stack.append(n)

    def handle_startendtag(self, tag, attrs):
        a = dict(attrs)
        n = Node(tag, a, self.getpos()[0])
        self.nodes.append((n, list(self.stack)))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return


def main(path):
    html = open(path, encoding="utf-8").read()
    # 去掉 script 内容（JS 生成的控件单独人工验算）
    body = re.sub(r"<script[\s\S]*?</script>", "", html)

    p = P()
    p.feed(body)

    violations = []
    warnings = []
    checked = 0

    def content_box(n):
        if n.w is None or n.h is None:
            return None
        return (n.w - 2 * n.bw, n.h - 2 * n.bw)

    for node, parents in p.nodes:
        if node.kind is None:
            continue
        if node.x is None or node.y is None or node.w is None or node.h is None:
            warnings.append("L%d %s 缺显式 left/top/width/height | style=%r"
                            % (node.line, node.label, node.style))
            continue
        # 找最近的、有尺寸的祖先
        parent = None
        for pt in reversed(parents):
            if pt.w is not None and pt.h is not None:
                parent = pt
                break
        if parent is None:
            cw, ch = 1024, 600
            pname = "stage"
        else:
            cw, ch = content_box(parent)
            pname = parent.label

        checked += 1
        problems = []
        if node.x < 0:
            problems.append("x=%d < 0" % node.x)
        if node.y < 0:
            problems.append("y=%d < 0" % node.y)
        if node.x + node.w > cw:
            problems.append("right=%d > cw=%d" % (node.x + node.w, cw))
        if node.y + node.h > ch:
            problems.append("bottom=%d > ch=%d" % (node.y + node.h, ch))
        if problems:
            violations.append("L%d  %-16s 父[%s %dx%d]  x=%d y=%d w=%d h=%d  ->  %s"
                              % (node.line, node.label, pname, cw, ch,
                                 node.x, node.y, node.w, node.h, "; ".join(problems)))

        for pat, why in BLACKLIST:
            if re.search(pat, node.style):
                violations.append("L%d %s 使用 %s" % (node.line, node.label, why))

        if node.kind in ("label", "num") and node.fs is not None and node.fs < FS_MIN:
            violations.append("L%d %s 字号 %d < %d"
                              % (node.line, node.label, node.fs, FS_MIN))

    # 全局黑名单
    for pat, why in BLACKLIST:
        found = re.findall(pat, body)
        if found:
            violations.append("全局出现 %s 共 %d 处" % (why, len(found)))

    # 统计热区重叠（同层）
    hits = {}
    for node, parents in p.nodes:
        if node.kind != "hit" or node.x is None:
            continue
        key = id(parents[-1]) if parents else 0
        hits.setdefault(key, []).append(node)
    for group in hits.values():
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                a, b = group[i], group[j]
                if (a.x < b.x + b.w and b.x < a.x + a.w and
                        a.y < b.y + b.h and b.y < a.y + a.h):
                    violations.append("热区重叠 L%d 与 L%d" % (a.line, b.line))

    # 令牌对比度 + CSS 里的小字号
    token_table, token_bad = check_tokens(html)
    violations.extend(token_bad)
    for m in FS_RE.finditer(body):
        if int(m.group(1)) < FS_MIN:
            violations.append("CSS 中出现字号 %s < %d" % (m.group(1), FS_MIN))

    print("CHECKED_ELEMENTS: %d" % checked)
    print("TOKENS:")
    for row in token_table:
        print(row)
    print("WARNINGS: %d" % len(warnings))
    for w in warnings:
        print("  " + w)
    print("VIOLATIONS: %d" % len(violations))
    for v in violations:
        print("  " + v)
    return 0 if not violations else 1


if __name__ == "__main__":
    if len(sys.argv) > 1:
        html_path = sys.argv[1]
    else:
        # 默认自动发现本目录下的「效果稿」html。文件名带中文，Windows 控制台代码页
        # 不对时传参会被转成乱码路径（FileNotFoundError），自动发现比传参可靠。
        here = os.path.dirname(os.path.abspath(__file__))
        cand = sorted(n for n in os.listdir(here) if n.endswith(".html") and "效果稿" in n)
        html_path = os.path.join(here, cand[0]) if cand else "自助售币机UI效果稿.html"
    sys.exit(main(html_path))
