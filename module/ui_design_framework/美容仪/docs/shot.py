# -*- coding: utf-8 -*-
"""设计稿截图 + 几何自检（本机无真机时用）

起一个本地 http 服务（中文文件名走 URL 编码），再用无头 Chrome 截图，
把每个页面的 getBoundingClientRect 越界情况写进 body[data-audit]，方便核对。

用法： python shot.py [页面名]
      python shot.py                        # 亮色稿 → preview.png
      python shot.py 美容仪UI深蓝科技稿.html  # 深蓝稿 → preview_blue.png
"""
import os
import re
import sys
import subprocess
import threading
import urllib.parse
import http.server
import socketserver

HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
PAGE = sys.argv[1] if len(sys.argv) > 1 else "美容仪UI效果稿.html"
OUTNAME = {
    "美容仪UI效果稿.html": "preview.png",
    "美容仪UI深蓝科技稿.html": "preview_blue.png",
}
PORT = 8765
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


def serve():
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), Quiet)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def shot(url, out):
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=1024,600",
                    "--virtual-time-budget=4000", "--screenshot=" + out, url],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def audit(url):
    """dump-dom 取 <pre id="AUDIT"> 里的越界清单。"""
    p = subprocess.run([CHROME, "--headless=new", "--disable-gpu",
                        "--virtual-time-budget=3000", "--dump-dom", url],
                       capture_output=True)
    html = p.stdout.decode("utf-8", "ignore")
    m = re.search(r'<pre id="AUDIT">(.*?)</pre>', html, re.S)
    return m.group(1).strip() if m else "(audit 块未找到)"


def main():
    serve()
    base = "http://127.0.0.1:%d/%s" % (PORT, urllib.parse.quote(PAGE))
    print("--- 越界自检 ---")
    print(audit(base + "?audit=1"))
    print("--- 截图 ---")
    out = os.path.join(HERE, OUTNAME.get(PAGE, "preview.png"))
    shot(base, out)
    print("saved", os.path.basename(out), os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main()
