# -*- coding: utf-8 -*-
"""使用 Edge headless print-to-pdf 将 HTML 转为 PDF。"""
import os
import subprocess
import time
from pathlib import Path

BASE = Path(__file__).resolve().parent
HTML = BASE / "Air8202G固件代码分析文档.html"
PDF = BASE / "Air8202G固件代码分析文档.pdf"
EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")

html_url = HTML.as_uri()
cmd = [
    str(EDGE),
    "--headless",
    "--disable-gpu",
    "--run-all-compositor-stages-before-draw",
    "--print-to-pdf={}".format(PDF),
    html_url,
]

print("running:", " ".join(cmd))
proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
print("returncode:", proc.returncode)
print("stdout:", proc.stdout)
print("stderr:", proc.stderr)

# 等待文件落地
for _ in range(20):
    if PDF.exists() and PDF.stat().st_size > 4096:
        break
    time.sleep(0.5)

if PDF.exists():
    print("saved", PDF, "size", PDF.stat().st_size)
else:
    print("PDF not created")
