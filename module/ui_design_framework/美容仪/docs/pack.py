# -*- coding: utf-8 -*-
"""把 img/mode_*.png 内联进 HTML（base64），产出单文件设计稿。

解决的是「双击 HTML 看不到图」：内联后不再依赖 img 目录与相对路径，
拷到任何机器、任何浏览器都直接显示。幂等——已内联过的不会再处理。

用法： python pack.py
"""
import base64
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
HTML = os.path.join(HERE, "美容仪UI效果稿.html")
PAT = re.compile(r'<img[^>]*data-k="(\w+)"[^>]*>')
SRC = re.compile(r'src="[^"]*"')


def repl(m):
    """把带 data-k 的 img 的 src 换成对应 PNG 的 base64。

    已内联过的也照样替换，改图后直接重跑即可，不必先还原占位符。
    """
    tag, k = m.group(0), m.group(1)
    p = os.path.join(HERE, "img", "mode_%s.png" % k)
    with open(p, "rb") as f:
        b = base64.b64encode(f.read()).decode("ascii")
    return SRC.sub('src="data:image/png;base64,%s"' % b, tag, count=1)


def main():
    with open(HTML, "r", encoding="utf-8") as f:
        src = f.read()
    out, n = PAT.subn(repl, src)
    if not n:
        print("已内联过，无需处理；当前大小 %.1f KB" % (len(src.encode()) / 1024))
        return
    with open(HTML, "w", encoding="utf-8") as f:
        f.write(out)
    print("内联 %d 张图，文件 %.1f KB -> %.1f KB"
          % (n, len(src.encode()) / 1024, len(out.encode()) / 1024))


if __name__ == "__main__":
    main()
