# -*- coding: utf-8 -*-
"""
日志口用户自定义指令 上位机测试脚本
配合 demo/log_usercmd/main.lua 使用

测试项: 写4K文件/读回比对/枚举根目录/建目录/删目录
依赖: pyserial   (pip install pyserial)
"""
import argparse
import struct
import sys
import threading
import queue
import time

import serial

SOC_PACK_FLAG = 0xA5
SOC_PACK_CODE = 0xA6
SOC_CMD_USER_CMD = 19
CMD_GET_BASE_INFO = 1  # 仅用于触发设备flush日志,不用等回复

# ---------------- CRC16 (反射, poly 0xA001, init 0, 低字节在前) ----------------
_CRC_TABLE = []
for _i in range(256):
    _c = _i
    for _ in range(8):
        _c = (_c >> 1) ^ 0xA001 if _c & 1 else _c >> 1
    _CRC_TABLE.append(_c)


def crc16(data: bytes) -> int:
    crc = 0
    for b in data:
        crc = (crc >> 8) ^ _CRC_TABLE[(crc ^ b) & 0xFF]
    return crc


def escape(data: bytes) -> bytes:
    out = bytearray()
    for b in data:
        if b == SOC_PACK_FLAG:
            out += b"\xA6\x01"
        elif b == SOC_PACK_CODE:
            out += b"\xA6\x02"
        else:
            out.append(b)
    return bytes(out)


def build_frame(cmd: int, address: int, payload: bytes, sn: int = 0) -> bytes:
    """A5 + escaped(24B头 + payload + CRC16-LE) + A5, 头小端"""
    head = struct.pack("<QIIIHBB", 0, address, len(payload), cmd, sn, 0, 0)
    body = head + payload
    crc = crc16(body)
    body += struct.pack("<H", crc)  # 低字节在前
    return bytes([SOC_PACK_FLAG]) + escape(body) + bytes([SOC_PACK_FLAG])


class FrameParser:
    """流式解包: 按A5帧界重组 -> 解转义 -> CRC -> 24B头+payload"""

    def __init__(self):
        self.raw = bytearray()
        self.in_frame = False

    def feed(self, data: bytes):
        self.raw += data

    def _next_frame(self):
        """取出一个完整原始帧(含首尾A5), 无则返回None"""
        while True:
            if not self.in_frame:
                idx = self.raw.find(SOC_PACK_FLAG)
                if idx < 0:
                    self.raw.clear()
                    return None
                del self.raw[:idx]
                del self.raw[0]
                self.in_frame = True
            end = self.raw.find(SOC_PACK_FLAG)
            if end < 0:
                return None
            frame = bytes(self.raw[:end])
            del self.raw[:end + 1]
            self.in_frame = False
            if frame:  # 连续两个A5 -> 空帧丢弃
                return frame

    @staticmethod
    def _unescape(data: bytes):
        out = bytearray()
        i = 0
        while i < len(data):
            if data[i] == SOC_PACK_CODE and i + 1 < len(data):
                code = data[i + 1]
                if code == 0x01:
                    out.append(SOC_PACK_FLAG)
                elif code == 0x02:
                    out.append(SOC_PACK_CODE)
                else:
                    return None  # 非法转义
                i += 2
            else:
                out.append(data[i])
                i += 1
        return bytes(out)

    def poll(self):
        """解出所有完整帧, 返回 [(cmd, address, payload), ...]"""
        frames = []
        while True:
            raw = self._next_frame()
            if raw is None:
                break
            body = self._unescape(raw)
            if body is None or len(body) < 24 + 2:
                continue
            if crc16(body[:-2]) != struct.unpack("<H", body[-2:])[0]:
                continue  # CRC错误丢弃
            head = struct.unpack("<QIIIHBB", body[:24])
            frames.append((head[3], head[1], body[24:-2]))  # (cmd, address, payload)
        return frames


class UserCmdClient:
    """发 cmd=19 用户指令, 收取 UC| 回复行"""

    def __init__(self, port: str, baud: int):
        self.ser = serial.Serial(port, baud, timeout=0.1)
        # 运行模式要求 DTR/RTS 均为低(luatos-cli 刷机复位后的状态,见 ccm4211.rs)
        self.ser.dtr = False
        self.ser.rts = False
        self.parser = FrameParser()
        self.uc_lines = queue.Queue()
        self.other_logs = queue.Queue()
        self.lock = threading.Lock()
        self.alive = True
        self.t = threading.Thread(target=self._reader, daemon=True)
        self.t.start()

    def _reader(self):
        tail = b""
        while self.alive:
            try:
                data = self.ser.read(4096)
            except serial.SerialException:
                break
            if not data:
                continue
            self.parser.feed(data)
            for cmd, addr, payload in self.parser.poll():
                # 日志帧(cmd==0, LTOS): parser 已去掉 24B 头, payload 即原始数据
                if cmd != 0:
                    continue
                text = payload
                # 按行切, 处理跨帧/粘包
                buf = tail + text
                lines = buf.split(b"\n")
                tail = lines.pop()  # 最后一段可能不完整
                for ln in lines:
                    ln = ln.rstrip(b"\r").decode("utf-8", "ignore")
                    # LTOS帧按4对齐填充, padding残留在行尾, 跨帧拼接会污染下一行行首,
                    # 故按行内 "UC|" 位置截断, 而非简单 startswith
                    pos = ln.find("UC|")
                    if pos >= 0:
                        self.uc_lines.put(ln[pos:])
                    elif ln:
                        self.other_logs.put(ln)

    def close(self):
        self.alive = False
        try:
            self.ser.close()
        except Exception:
            pass

    def send_cmd(self, addr: int, payload: bytes = b""):
        with self.lock:
            self.ser.write(build_frame(SOC_CMD_USER_CMD, addr, payload))
            self.ser.flush()

    def wait_uc(self, expect_prefix: str, timeout: float = 2.0) -> str:
        """等到一条以 expect_prefix 开头的 UC 行(如 'UC|2|'), 返回完整行"""
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = self.uc_lines.get(timeout=deadline - time.time())
            except queue.Empty:
                break
            if line.startswith(expect_prefix):
                return line
            # 不是期望的回复(可能残留), 丢弃继续等
        return ""


# ---------------- 测试项 ----------------
# 块大小受线上帧长限制: escaped(26 + 4 + CHUNK) <= 126 -> CHUNK <= 96, 取80留余量
CHUNK = 80
MAX_RETRY = 8                 # 设备忙时(如擦flash关中断)回复帧可能丢失, 需多试几次
DATA4K = bytes([(i * 7 + 3) & 0xFF for i in range(4096)])
results = []


def check(name: str, ok: bool, detail: str = ""):
    results.append((name, ok))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" -- {detail}" if detail else ""))


def test_write(cli: UserCmdClient) -> bool:
    cli.send_cmd(1, b"/abc.txt")
    r = cli.wait_uc("UC|1|", 2.0)
    if not r.endswith("|ok"):
        cli.send_cmd(3)  # 尝试关闭可能残留的写会话
        cli.wait_uc("UC|3|", 1.0)
        check("write.begin", False, r or "timeout")
        return False
    check("write.begin", True)
    n = 0
    for off in range(0, len(DATA4K), CHUNK):
        chunk = DATA4K[off:off + CHUNK]
        ok = False
        last = ""
        for attempt in range(MAX_RETRY):  # 幂等重发: offset 定位写入, 重发安全
            cli.send_cmd(2, struct.pack("<I", off) + chunk)
            r = cli.wait_uc("UC|2|", 3.0)
            last = r
            if r.endswith("|ok"):
                ok = True
                break
            time.sleep(0.1)
        if not ok:
            cli.send_cmd(3)
            cli.wait_uc("UC|3|", 1.0)
            check(f"write.chunk@{off}", False, last or f"timeout x{MAX_RETRY}")
            return False
        n += 1
        if n % 10 == 0:
            print(f"  ... {n} chunks")
    check("write.chunks", True, f"{n} chunks")
    cli.send_cmd(3)
    r = cli.wait_uc("UC|3|", 2.0)
    ok = r.endswith("|ok|4096")
    check("write.end", ok, r)
    return ok


def test_read(cli: UserCmdClient) -> bool:
    cli.send_cmd(4, b"/abc.txt")
    r = cli.wait_uc("UC|4|b|", 3.0)
    if not r:
        check("read.begin", False, "timeout")
        return False
    total = int(r.split("|")[3])
    hexparts = []
    while True:
        r = cli.wait_uc("UC|4|", 10.0)
        if not r:
            check("read.data", False, "timeout")
            return False
        parts = r.split("|")
        if parts[2] == "h":
            hexparts.append(parts[3])
        elif parts[2] == "e":
            break
    content = bytes.fromhex("".join(hexparts))
    ok = (len(content) == total == len(DATA4K)) and content == DATA4K
    check("read.content", ok,
          f"{len(content)}/{total} bytes" + ("" if ok else ", data mismatch"))
    return ok


def ls_names(cli: UserCmdClient) -> list:
    cli.send_cmd(5, b"/")
    r = cli.wait_uc("UC|5|ok|", 2.0)
    if not r:
        return []
    return r.split("|", 3)[3].split(",")


def test_ls(cli: UserCmdClient) -> bool:
    names = ls_names(cli)
    ok = "abc.txt" in names
    check("ls.root", ok, ",".join(names[:8]) + ("..." if len(names) > 8 else ""))
    return ok


def test_mkdir_rmdir(cli: UserCmdClient) -> bool:
    cli.send_cmd(6, b"/uctest")
    r = cli.wait_uc("UC|6|", 2.0)
    ok = r.endswith("|ok")
    check("mkdir", ok, r)
    if not ok:
        return False
    ok = "uctest" in ls_names(cli)
    check("mkdir.verify", ok, "uctest in ls /")
    cli.send_cmd(7, b"/uctest")
    r = cli.wait_uc("UC|7|", 2.0)
    ok = r.endswith("|ok")
    check("rmdir", ok, r)
    ok = "uctest" not in ls_names(cli)
    check("rmdir.verify", ok, "uctest not in ls /")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM6")
    ap.add_argument("--baud", type=int, default=6000000)
    args = ap.parse_args()

    cli = UserCmdClient(args.port, args.baud)
    print(f"open {args.port} @ {args.baud}")
    # 打开端口会复位设备(Windows DTR/RTS 抖动), 等待启动完成并清空启动日志
    time.sleep(4)
    while not cli.uc_lines.empty():
        cli.uc_lines.get()
    while not cli.other_logs.empty():
        cli.other_logs.get()
    try:
        all_ok = True
        all_ok &= test_write(cli)
        all_ok &= test_read(cli)
        all_ok &= test_ls(cli)
        all_ok &= test_mkdir_rmdir(cli)
    finally:
        cli.close()
    print("=" * 40)
    for name, ok in results:
        print(f"  [{'x' if ok else ' '}] {name}")
    passed = sum(1 for _, ok in results if ok)
    print(f"total: {passed}/{len(results)} passed")
    sys.exit(0 if (all_ok and passed == len(results)) else 1)


if __name__ == "__main__":
    main()
