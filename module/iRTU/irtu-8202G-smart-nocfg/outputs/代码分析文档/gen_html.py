# -*- coding: utf-8 -*-
"""将合并后的 md 转为适合打印/转 PDF 的 HTML（工业风浅色，A4 友好）。"""
import re, os
import markdown

BASE = r"D:\dev\LuatOS\module\iRTU\irtu-8202G-smart-nocfg\outputs\代码分析文档"
MD = os.path.join(BASE, "Air8202G固件代码分析文档.md")
HTML = os.path.join(BASE, "Air8202G固件代码分析文档.html")

with open(MD, encoding="utf-8") as f:
    text = f.read()

# markdown → html
body = markdown.markdown(
    text,
    extensions=["tables", "fenced_code", "sane_lists", "toc"],
    output_format="html5",
)

CSS = """
:root { color-scheme: light; }
* { box-sizing: border-box; }
body {
  font-family: "Microsoft YaHei", "PingFang SC", "Segoe UI", sans-serif;
  font-size: 11pt; line-height: 1.75; color: #26323b;
  background: #ffffff; margin: 0 auto; max-width: 960px; padding: 32px 40px;
}
h1 { font-size: 21pt; color: #0f3550; border-bottom: 3px solid #d9a441;
     padding-bottom: 8px; margin: 36px 0 18px; page-break-after: avoid; }
h2 { font-size: 16pt; color: #0f3550; border-left: 6px solid #d9a441;
     padding-left: 10px; margin: 30px 0 12px; page-break-after: avoid; }
h3 { font-size: 13pt; color: #17506e; margin: 24px 0 8px; page-break-after: avoid; }
h4 { font-size: 11.5pt; color: #17506e; margin: 18px 0 6px; page-break-after: avoid; }
p { margin: 8px 0; }
a { color: #1565c0; text-decoration: none; }
blockquote { margin: 12px 8px; padding: 8px 14px; background: #fdf6e3;
             border-left: 5px solid #d9a441; color: #5a5343; }
blockquote p { margin: 2px 0; }
hr { border: none; border-top: 1px dashed #b9c4cc; margin: 26px 0; }
table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 10pt;
        page-break-inside: auto; }
th { background: #0f3550; color: #fff; font-weight: 600; }
th, td { border: 1px solid #b9c4cc; padding: 5px 9px; text-align: left; vertical-align: top; }
tr:nth-child(even) td { background: #f4f7f9; }
pre { background: #f2f4f6; border: 1px solid #d4dae0; border-radius: 4px;
      padding: 10px 14px; font-size: 9.5pt; line-height: 1.55; overflow-x: auto;
      font-family: Consolas, "Courier New", monospace; page-break-inside: avoid; }
code { font-family: Consolas, "Courier New", monospace; background: #eef1f4;
       padding: 1px 4px; border-radius: 3px; font-size: 9.5pt; }
pre code { background: none; padding: 0; }
img { max-width: 100%; height: auto; display: block; margin: 10px auto; }
strong { color: #0f3550; }
"""

page = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>LuatOS iRTU-8202G 车辆/宠物定位器固件代码分析文档</title>
<style>{CSS}</style>
</head>
<body>
{body}
</body>
</html>
"""

with open(HTML, "w", encoding="utf-8") as f:
    f.write(page)

print("HTML written:", HTML, len(page), "chars")
