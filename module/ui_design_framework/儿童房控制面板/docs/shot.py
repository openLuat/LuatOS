# -*- coding: utf-8 -*-
"""把唯一视觉规格（效果稿 HTML）渲染成一张定稿图，方便和设备截图逐项对比。

为什么不再分别截三张旧主题图：
  效果稿改成了「5 套主题 + 四页」的单一页面，主题/页面的切换是 JS 行为，
  没有 URL 参数入口（旧版的 ?flat=1&theme=&page= 已经不存在）。
  要对比某一套主题，直接打开 HTML 点顶栏按钮即可，这里只负责渲染默认态
  （玩具总动员 / 我的房间），保证有一张不依赖模拟器的基准图。

用法： python shot.py
依赖： Chrome 默认安装路径（见下方 CHROME），或改环境变量 CHROME_PATH。
产物： docs/preview_draft.png（1080x680，留出 body 的 28px 边距，不裁切舞台）
"""

import http.server
import os
import socketserver
import subprocess
import threading
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # 以项目根为 http 根，docs/assets/*.webp 才取得到
os.chdir(ROOT)
PAGE = "docs/儿童房面板效果稿.html"
PORT = 8766
CHROME = os.environ.get("CHROME_PATH", r"C:\Program Files\Google\Chrome\Application\chrome.exe")
OUT = os.path.join(HERE, "preview_draft.png")


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


def serve():
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), Quiet)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def shot(url, out, w=1080, h=680):
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=%d,%d" % (w, h),
                    "--virtual-time-budget=5000", "--screenshot=" + out, url],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    if not os.path.isfile(CHROME):
        print("找不到 Chrome：", CHROME, "（可用 CHROME_PATH 指定）")
        return
    serve()
    url = "http://127.0.0.1:%d/%s" % (PORT, urllib.parse.quote(PAGE))
    shot(url, OUT)
    if os.path.isfile(OUT):
        print("saved", os.path.basename(OUT), os.path.getsize(OUT), "bytes")
    else:
        print("FAIL", OUT)


if __name__ == "__main__":
    main()
