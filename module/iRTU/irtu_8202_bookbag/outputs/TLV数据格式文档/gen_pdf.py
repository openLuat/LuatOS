# -*- coding: utf-8 -*-
"""使用 Edge headless print-to-pdf 将 TLV 文档 HTML 转为 PDF。"""
import subprocess
import time
from pathlib import Path

BASE = Path(__file__).resolve().parent
HTML = BASE / "AirCloud TLV数据格式详解.html"
PDF = BASE / "8202bagV001000002 AirCloud TLV数据格式详解.pdf"
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
