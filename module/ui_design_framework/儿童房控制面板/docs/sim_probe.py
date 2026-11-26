# -*- coding: utf-8 -*-
"""交互探针：启动模拟器，按命令行给的步骤点击/截图，最后打印 dbg 日志。

用法：
  python sim_probe.py "shot:a.png" "click:60,272" "shot:b.png"
步骤：shot:<文件名> / click:<x,y> / wait:<毫秒>
产物：截图落 docs/local_artifacts/shots/，日志与 probe_stdout.log 落 docs/local_artifacts/
"""
import base64
import json
import os
import socket
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
CODE = os.path.join(os.path.dirname(HERE), "code")
EXE = r"d:\Air\Git_Project\LuatOS\bsp\pc\build\out\luatos-lua.exe"
# 本地运行产物（日志 / 截图）统一落在 docs/local_artifacts/，该目录已整体 gitignore
ART = os.path.join(HERE, "local_artifacts")
SHOTS = os.path.join(ART, "shots")
LOGDIR = os.path.join(ART, "logs")


class Ctl:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        self.sock.settimeout(10)
        self.buf = b""
        self.n = 0

    def call(self, method, params=None):
        self.n += 1
        msg = {"jsonrpc": "2.0", "id": self.n, "method": method}
        if params:
            msg["params"] = params
        self.sock.sendall((json.dumps(msg) + "\n").encode())
        while b"\n" not in self.buf:
            self.buf += self.sock.recv(65536)
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.decode())

    def shot(self, name):
        r = self.call("screenshot")
        with open(os.path.join(SHOTS, name), "wb") as f:
            f.write(base64.b64decode(r["result"]["data"]))
        print("  shot ->", os.path.join(SHOTS, name))

    def click(self, x, y):
        self.call("pointer", {"type": "click", "x": x, "y": y, "button": "left"})
        print("  click", x, y)


def main():
    steps = sys.argv[1:]
    subprocess.run(["taskkill", "/F", "/IM", "luatos-lua.exe"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    os.makedirs(LOGDIR, exist_ok=True)
    os.makedirs(SHOTS, exist_ok=True)
    port = 18899
    logf = open(os.path.join(ART, "probe_stdout.log"), "wb")
    proc = subprocess.Popen([EXE, CODE, "--headless=1",
                             "--agent-ctl=127.0.0.1:%d" % port,
                             "--log-dir=" + LOGDIR],
                            stdout=logf, stderr=subprocess.STDOUT, cwd=LOGDIR)
    ctl = None
    t0 = time.time()
    while time.time() - t0 < 25:
        try:
            c = Ctl(port)
            for _ in range(20):
                if c.call("hello").get("result", {}).get("ready"):
                    ctl = c
                    break
                time.sleep(0.4)
            if ctl:
                break
        except OSError:
            time.sleep(0.4)
    if not ctl:
        print("控制口未就绪")
        proc.kill()
        return
    time.sleep(1.0)
    for st in steps:
        kind, _, arg = st.partition(":")
        if kind == "shot":
            ctl.shot(arg)
        elif kind == "click":
            x, y = arg.split(",")
            ctl.click(int(x), int(y))
            time.sleep(0.45)
        elif kind == "wait":
            time.sleep(int(arg) / 1000.0)
    time.sleep(0.5)
    proc.kill()
    logf.close()

    files = [os.path.join(LOGDIR, f) for f in os.listdir(LOGDIR) if f.endswith(".log")]
    if files:
        newest = max(files, key=os.path.getmtime)
        text = open(newest, "rb").read().decode("gbk", "replace")
        lines = [l for l in text.splitlines()
                 if "dbg" in l or "E/" in l or "切页" in l]
        print("--- 关键日志 ---")
        for l in lines:
            print(l)


if __name__ == "__main__":
    main()
