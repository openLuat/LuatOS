# -*- coding: utf-8 -*-
r"""在 PC 模拟器上跑首帧 + 关键交互，并把每一步截图存到 docs/local_artifacts/shots/。

原理：bsp/pc 的 luatos-lua.exe 支持 `--headless=1 --agent-ctl=127.0.0.1:PORT`，
起一个 JSON-RPC over TCP 的控制口（hello / screenshot / pointer / wait），
所以不需要人工看窗口，也能核对「首帧是否按期出现、点下去是否真的变了」。

覆盖范围（5 主题 / 角色 / 键盘 / 四页）：
  1 首帧（我的房间，主题 1/5）
  2 点大角色换人（房间名跟着变）
  3 点弧形小角色直接选
  4 点名字弹出键盘（改名弹层）
  5 页2 换色点 + 亮度 +
  6 页3 选曲 + 播放/暂停 + 点进度条
  7 页4 勾任务
  8 回页1 空调 +、关星空投影
  9 连续切主题（重建后保留当前页与设备状态）

用法： python verify_sim.py [--port 18877] [--keep-kv]
依赖： d:\Air\Git_Project\LuatOS\bsp\pc\build\out\luatos-lua.exe（GUI 构建）
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
PROJ = os.path.dirname(HERE)
CODE = os.path.join(PROJ, "code")
EXE = r"d:\Air\Git_Project\LuatOS\bsp\pc\build\out\luatos-lua.exe"
PORT = 18877
if "--port" in sys.argv:
    PORT = int(sys.argv[sys.argv.index("--port") + 1])

# 本地运行产物（模拟器日志 / 截图）统一落在 docs/local_artifacts/，该目录已整体 gitignore
ART = os.path.join(HERE, "local_artifacts")
SHOTS = os.path.join(ART, "shots")
LOG = os.path.join(ART, "sim_run.log")
LOGDIR = os.path.join(ART, "logs")
KV = os.path.join(LOGDIR, "fskv.bin")

# 日志里必须出现的交互标记（证明点击真的走到了业务逻辑，而不是只改画面）
EXPECT = [
    ("界面已创建", "首帧创建"),
    ("切角色", "点角色换人"),
    ("打开改名弹层", "点名字弹键盘"),
    ("改名 ", "键盘提交改名"),
    ("切页", "底部 Tab 切页"),
    ("切换主题", "顶栏切主题重建"),
]


def latest_log():
    files = [os.path.join(LOGDIR, f) for f in os.listdir(LOGDIR)] if os.path.isdir(LOGDIR) else []
    files = [f for f in files if f.endswith(".log")]
    if not files:
        return None
    return max(files, key=os.path.getmtime)


class Ctl:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        self.sock.settimeout(10)
        self.buf = b""
        self.n = 0

    def call(self, method, params=None):
        self.n += 1
        msg = {"jsonrpc": "2.0", "id": self.n, "method": method}
        if params is not None:
            msg["params"] = params
        self.sock.sendall((json.dumps(msg) + "\n").encode("utf-8"))
        while True:
            if b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                if not line.strip():
                    continue
                return json.loads(line.decode("utf-8"))
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("ctl 连接被关闭")
            self.buf += chunk

    def shot(self, name):
        r = self.call("screenshot")
        if "error" in r:
            print("  screenshot FAIL", r["error"])
            return None
        data = base64.b64decode(r["result"]["data"])
        path = os.path.join(SHOTS, name)
        with open(path, "wb") as f:
            f.write(data)
        print("  saved %-22s %dx%d %d bytes" % (name, r["result"]["width"],
                                                r["result"]["height"], len(data)))
        return path

    def click(self, x, y, gap=0.4):
        self.call("pointer", {"type": "click", "x": x, "y": y, "button": "left"})
        time.sleep(gap)   # 连点太快 LVGL 会丢事件（实测 0 间隔的第二下必丢）


def wait_ctl(timeout=25.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            c = Ctl(PORT)
            for _ in range(20):
                try:
                    r = c.call("hello")
                    if r.get("result", {}).get("ready"):
                        return c
                except Exception:
                    pass
                time.sleep(0.4)
            c.sock.close()
        except OSError:
            time.sleep(0.4)
    return None


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def main():
    global PORT
    if not os.path.isfile(EXE):
        print("找不到模拟器：", EXE)
        return
    # 上一次没退干净的模拟器会占着控制口，导致本轮连到旧进程（点不动、画面不刷新）
    subprocess.run(["taskkill", "/F", "/IM", "luatos-lua.exe"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.6)
    if "--port" not in sys.argv:
        PORT = free_port()
    os.makedirs(LOGDIR, exist_ok=True)
    os.makedirs(SHOTS, exist_ok=True)
    # 默认清掉 fskv 记忆，让每轮从「玩具总动员 1/5 + 小星星」开始，截图可对比
    if "--keep-kv" not in sys.argv and os.path.isfile(KV):
        os.remove(KV)
        print("已清空 fskv 记忆（--keep-kv 可保留）")
    # 模拟器偶尔在音频子系统初始化阶段崩一次（与工程脚本无关，崩溃日志停在 airui 启动前），
    # 这里最多重试 3 次，并每次换端口，避免把环境抖动误判成工程问题。
    ctl, proc, logf = None, None, None
    for attempt in range(1, 4):
        subprocess.run(["taskkill", "/F", "/IM", "luatos-lua.exe"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2.0)
        PORT = free_port()
        logf = open(LOG, "wb")
        proc = subprocess.Popen(
            [EXE, CODE, "--headless=1", "--agent-ctl=127.0.0.1:%d" % PORT,
             "--log-dir=" + LOGDIR],
            stdout=logf, stderr=subprocess.STDOUT,
            cwd=LOGDIR,     # 模拟器会在 cwd 落 pcconf/pclogs/fskv.bin，别污染工程目录
        )
        print("第 %d 次启动模拟器 pid=%d，控制口 127.0.0.1:%d ..."
              % (attempt, proc.pid, PORT))
        ctl = wait_ctl()
        if ctl is not None:
            break
        print("  控制口未就绪（模拟器可能启动期崩溃），重试…")
        proc.kill()
        logf.close()
    if ctl is None:
        print("三次启动都没起来，最后一段输出：")
        print(open(LOG, "rb").read()[-1500:].decode("gbk", "replace"))
        return

    try:
        time.sleep(1.2)
        print("[1] 首页首帧（我的房间 / 玩具总动员 1/5）")
        ctl.shot("sim_1_room.png")

        print("[2] 点大角色 → 换下一个角色，房间名跟着变")
        ctl.click(240, 204)         # 大角色：卡 x16+166..314，内容区 y+42..190
        time.sleep(0.5)
        ctl.shot("sim_2_cast.png")

        print("[3] 点右侧弧形小角色 → 直接选他")
        ctl.click(340, 126)         # 弧位3（298,12）+52/2
        time.sleep(0.5)
        ctl.shot("sim_3_arc.png")

        print("[4] 点名字 → 弹出改名键盘；点遮罩空白取消")
        ctl.click(200, 30)          # 名字热区 130..288 / 12..46
        time.sleep(1.2)
        ctl.shot("sim_4_keyboard.png")
        ctl.click(512, 120)         # 遮罩空白（0..340 高）= 取消
        time.sleep(0.8)

        print("[5] 页2 灯光乐园：换色点（第 3 行左＝黄）+ 亮度 +")
        ctl.click(381, 556)         # 底部 Tab 2
        time.sleep(0.8)
        ctl.click(76, 272)          # 色点 3：卡 x16+32，内容区 y+156
        ctl.click(604, 432)         # 亮度 +：卡 x328+238，内容区 y+316
        time.sleep(0.6)
        ctl.shot("sim_5_light.png")

        print("[6] 页3 故事时间：选第 3 首 + 播放/暂停 + 点进度条")
        ctl.click(627, 556)         # 底部 Tab 3
        time.sleep(0.8)
        ctl.click(190, 322)         # 第 3 首
        ctl.click(582, 480)         # 播放/暂停圆钮
        ctl.click(582, 408)         # 进度条 +10%
        time.sleep(1.2)             # 让进度推进几跳
        ctl.shot("sim_6_story.png")

        print("[7] 页4 星星奖励：勾第 3 条任务 + 睡觉闹钟 −15 分")
        ctl.click(873, 556)         # 底部 Tab 4
        time.sleep(0.8)
        ctl.click(250, 352)         # 第 3 条任务
        ctl.click(828, 400)         # 睡觉 −（卡 x496+24+290，内容区 y+290）
        time.sleep(0.6)
        ctl.shot("sim_7_star.png")

        print("[8] 回首页：空调 +1、关星空投影磁贴")
        ctl.click(136, 556)         # 底部 Tab 1
        time.sleep(0.8)
        ctl.click(390, 410)         # 空调 +
        ctl.click(858, 190)         # 星空投影磁贴（整卡即热区）
        time.sleep(0.6)
        ctl.shot("sim_8_tile.png")

        print("[9] 连点顶栏主题按钮 → 逐套重建，且保留当前页与设备状态")
        ctl.click(933, 44)
        time.sleep(2.0)
        ctl.shot("sim_9_theme_bear.png")
        ctl.click(933, 44)
        time.sleep(2.0)
        ctl.shot("sim_10_theme_hero.png")
        ctl.click(933, 44)
        time.sleep(2.0)
        ctl.shot("sim_11_theme_pocket.png")
        ctl.click(933, 44)
        time.sleep(2.0)
        ctl.shot("sim_12_theme_sheep.png")

        # 改名放在最后：用「1# 数字层 + 退格」改成 123，证明预览/输入/提交/记忆整条链路都通，
        # 又不会把前面所有截图的问候语弄成乱码名字。
        print("[10] 改名：退格清空 + 数字层输入 123 + 键盘确认键提交")
        ctl.click(200, 30)
        time.sleep(1.2)
        ctl.click(56, 383)          # 1# 数字/符号层
        for _ in range(3):
            ctl.click(930, 383)     # 退格 ×3（清掉「小星星」）
        ctl.click(48, 383)          # 1
        ctl.click(137, 383)         # 2
        ctl.click(226, 383)         # 3
        time.sleep(0.6)
        ctl.shot("sim_13_rename_typing.png")
        ctl.click(940, 569)         # 键盘右下角 ✓ = 提交
        time.sleep(1.2)
        ctl.shot("sim_14_renamed.png")
    finally:
        time.sleep(0.3)
        proc.kill()
        logf.close()

    # 日志走 --log-dir 落盘（stdout 被重定向时 C 运行库是块缓冲，kill 会丢）
    lf = latest_log()
    if not lf:
        print("\n没有找到日志文件")
        return
    # 日志是「C 层 Windows 路径 GBK + Lua log.info UTF-8」混排：
    # 先按 UTF-8 解（交互标记都是 Lua 打的），坏了再退回 GBK。
    raw = open(lf, "rb").read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("utf-8", "replace")
    lines = text.splitlines()
    bad = [ln for ln in lines if "E/" in ln]
    warn = [ln for ln in lines if "W/user" in ln]
    print("\n--- 日志：E/ 行 ---")
    for ln in bad[-20:]:
        print(ln)
    if not bad:
        print("（无）")
    print("--- 日志：W/user 降级行（应只有贴图/TF 卡相关）---")
    for ln in warn[:10]:
        print(ln)
    if not warn:
        print("（无）")

    print("--- 交互标记核对 ---")
    miss = 0
    for key, desc in EXPECT:
        if key in text:
            print("  OK   %s（%s）" % (desc, key))
        else:
            miss += 1
            print("  MISS %s（日志里没有「%s」）" % (desc, key))
    print("\n控制口截图与点击全部完成；完整日志：", lf)
    if bad or miss:
        print("结论：有错误或交互未触发，见上方清单")
    else:
        print("结论：无 E/ 日志，交互标记齐全")


if __name__ == "__main__":
    main()
