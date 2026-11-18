# -*- coding: utf-8 -*-
"""对 dump-dom 渲染结果做几何验算：每个 .card 的直接子元素必须落在内容区(w-2,h-2)内。
临时脚本，验证完即删。"""
import re, sys, io
from html.parser import HTMLParser

class N:
    __slots__ = ('tag', 'attrs', 'kids', 'text')
    def __init__(self, tag, attrs):
        self.tag = tag
        self.attrs = dict(attrs)
        self.kids = []
        self.text = ''
    @property
    def cls(self):
        return (self.attrs.get('class') or '').split()
    @property
    def st(self):
        d = {}
        for m in re.finditer(r'([a-zA-Z-]+)\s*:\s*([^;]+)', self.attrs.get('style') or ''):
            d[m.group(1).strip()] = m.group(2).strip()
        return d

VOID = {'br', 'img', 'meta', 'link', 'input', 'hr', 'area', 'col'}

class P(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = N('root', [])
        self.stack = [self.root]
        self.depth_max = 0
    def handle_starttag(self, tag, attrs):
        n = N(tag, attrs)
        self.stack[-1].kids.append(n)
        if tag not in VOID:
            self.stack.append(n)
            self.depth_max = max(self.depth_max, len(self.stack))
    def handle_startendtag(self, tag, attrs):
        self.stack[-1].kids.append(N(tag, attrs))
    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return
    def handle_data(self, data):
        if data.strip():
            self.stack[-1].text += data.strip()

def px(v):
    if not v:
        return None
    m = re.match(r'^(-?\d+(?:\.\d+)?)px$', v.strip())
    return float(m.group(1)) if m else None

def walk(n, out):
    out.append(n)
    for k in n.kids:
        walk(k, out)

src = io.open(sys.argv[1], encoding='utf-8', errors='replace').read()
p = P()
p.feed(src)
all_nodes = []
walk(p.root, all_nodes)

# ---- 基础结构断言 ----
def count(tag):
    return sum(1 for n in all_nodes if n.tag == tag)

cards = [n for n in all_nodes if 'card' in n.cls]
rows = [n for n in all_nodes if 'row' in n.cls]
pills = [n for n in all_nodes if 'pill' in n.cls]
segs = [n for n in all_nodes if 'seg' in n.cls]
nums = [n for n in all_nodes if 'num' in n.cls and 'lb' in n.cls and 'height:22px' in (n.attrs.get('style') or '')]

print('cards=%d rows=%d pills=%d segs=%d numlabels=%d' % (len(cards), len(rows), len(pills), len(segs), len(nums)))
print('svg line=%d path=%d circle=%d rect=%d polyline=%d' % (
    count('line'), count('path'), count('circle'), count('rect'), count('polyline')))

bad = []
checked = 0
for c in cards:
    cs = c.st
    cw, ch = px(cs.get('width')), px(cs.get('height'))
    if cw is None or ch is None:
        continue
    bw = 1.0  # 卡片 border:1px
    icw, ich = cw - 2 * bw, ch - 2 * bw
    for k in c.kids:
        ks = k.st
        x, y = px(ks.get('left')), px(ks.get('top'))
        w, h = px(ks.get('width')), px(ks.get('height'))
        if x is None or y is None or w is None or h is None:
            continue
        checked += 1
        r, b = x + w, y + h
        if x < 0 or y < 0 or r > icw + 0.01 or b > ich + 0.01:
            bad.append((c.cls, int(cw), int(ch), k.cls, x, y, w, h, round(r, 1), round(b, 1), icw, ich))

print('checked=%d violations=%d' % (checked, len(bad)))
for v in bad:
    print('  VIOLATION card=%s %dx%d child=%s x=%s y=%s w=%s h=%s right=%s bottom=%s (限 %sx%s)' % v)

# ---- 内容健全性 ----
nan = src.count('NaN') + src.count('undefined') + src.count('Infinity')
print('NaN/undefined occurrences=', nan)
spd = re.search(r'id="dSpeed"[^>]*>([^<]*)<', src)
print('dSpeed=', spd.group(1) if spd else 'MISSING')
odo = re.search(r'id="dOdo"[^>]*>([^<]*)<', src)
print('dOdo=', odo.group(1) if odo else 'MISSING')
for i in ('prog', 'progRed', 'nMain'):
    m = re.search(r'id="%s"[^>]*' % i, src)
    print(i, 'attr=', (m.group(0)[:110] + '...') if m else 'MISSING')
print('stack depth left=', len(p.stack), 'max=', p.depth_max)
