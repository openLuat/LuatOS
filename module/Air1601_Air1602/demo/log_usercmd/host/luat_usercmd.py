# -*- coding: utf-8 -*-
"""
日志口用户指令协议 v2 上位机库
配合 demo/log_usercmd/log_usercmd.lua 使用, 协议见 PROTOCOL.md

依赖: pyserial   (pip install pyserial)

示例:
    from luat_usercmd import UserCmd
    dev = UserCmd("COM6")
    dev.wait_ready()                  # 等启动 + 握手 + 分片协商
    if not dev.auth("your-token"):    # 可选: 设备配置 token 时才需要
        print("device does not require auth")
    dev.write_file("/abc.txt", data)
    data = dev.read_file("/abc.txt")
    for e in dev.lsdir("/"):
        print(e["name"], e["type"], e["size"])
    print(dev.lsmount())              # [{'path': '/', 'fs': 'soc'}, ...]
    print(dev.fsstat("/"))            # {'total':.., 'used':.., 'block_size':.., 'fs':..}
"""
import hashlib
import hmac
import random
import struct
import threading
import time

import serial

SOC_PACK_FLAG = 0xA5
SOC_PACK_CODE = 0xA6
SOC_CMD_USER_CMD = 19

UC_VERSION = 0x01

SUB_HELLO = 0
SUB_OPEN = 1
SUB_CLOSE = 2
SUB_WRITE = 3
SUB_READ = 4
SUB_LSDIR = 5
SUB_MKDIR = 6
SUB_RMDIR = 7
SUB_REMOVE = 8
SUB_STAT = 9
SUB_EXISTS = 10
SUB_AUTH = 11
SUB_LSMOUNT = 12
SUB_FSSTAT = 13

FLAG_ERR = 0x01
FLAG_MORE = 0x02

# HELLO 回应 caps 位
CAP_AUTH_REQUIRED = 0x0001

# 错误码, 与 PROTOCOL.md §2 一致
E_OK, E_NOENT, E_DENIED, E_IO, E_BADREQ, E_BADFD, E_TOOLONG, E_BUSY, E_NOSYS = range(9)

_MODE = {"r": 0, "w": 1, "a": 2, "r+": 3}


class UserCmdError(Exception):
    def __init__(self, errno, msg=""):
        self.errno = errno
        super().__init__(msg or f"usercmd errno={errno}")


# ---------------- A5 传输层 (CRC/转义/组帧, 与设备 am_log.c 对应) ----------------
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
    """A5 + escaped(24B头小端 + payload + CRC16-LE) + A5"""
    head = struct.pack("<QIIIHBB", 0, address, len(payload), cmd, sn, 0, 0)
    body = head + payload
    body += struct.pack("<H", crc16(body))
    return bytes([SOC_PACK_FLAG]) + escape(body) + bytes([SOC_PACK_FLAG])


def pack_payload(subcmd: int, flags: int, seq: int, body: bytes) -> bytes:
    """usercmd v2.2 payload 组包: version+subcmd+flags+seq(LE)+body (无 MAGIC)"""
    return bytes([UC_VERSION, subcmd, flags]) + struct.pack("<H", seq) + body


def parse_payload(payload: bytes):
    """解析 payload 固定头, 返回 (version, subcmd, flags, seq, body); 不足 5 字节抛 ValueError"""
    if len(payload) < 5:
        raise ValueError("usercmd payload too short")
    return payload[0], payload[1], payload[2], struct.unpack("<H", payload[3:5])[0], payload[5:]


class FrameParser:
    """流式解包: 按A5帧界重组 -> 解转义 -> CRC -> (cmd, address, payload)"""

    def __init__(self):
        self.raw = bytearray()
        self.in_frame = False

    def feed(self, data: bytes):
        self.raw += data

    def _next_frame(self):
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
            if frame:
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
                    return None
                i += 2
            else:
                out.append(data[i])
                i += 1
        return bytes(out)

    def poll(self):
        frames = []
        while True:
            raw = self._next_frame()
            if raw is None:
                break
            body = self._unescape(raw)
            if body is None or len(body) < 24 + 2:
                continue
            if crc16(body[:-2]) != struct.unpack("<H", body[-2:])[0]:
                continue
            head = struct.unpack("<QIIIHBB", body[:24])
            frames.append((head[3], head[1], body[24:-2]))
        return frames


# ---------------- usercmd v2 协议层 ----------------
class UserCmd:
    def __init__(self, port: str, baud: int = 6000000,
                 window: int = 8, propose_chunk: int = 512, read_chunk: int = 512,
                 control_timeout: float = 1.0, control_retries: int = 5,
                 data_timeout: float = 0.5, data_retries: int = 10,
                 log_handler=None):
        self.ser = serial.Serial(port, baud, timeout=0.05)
        # 运行模式要求 DTR/RTS 均为低, 否则打开端口会复位设备
        self.ser.dtr = False
        self.ser.rts = False
        self.ser.reset_input_buffer()
        self.window = window
        self.propose_chunk = propose_chunk
        self.read_chunk = read_chunk
        self.control_timeout = control_timeout
        self.control_retries = control_retries
        self.data_timeout = data_timeout
        self.data_retries = data_retries
        self.log_handler = log_handler      # 可选: fn(bytes) 处理普通日志帧
        self.chunk = 90                     # hello 协商后更新
        self.caps = 0                       # hello 协商后更新 (bit0=需要鉴权)
        self._nonce = None                  # 最近一次 hello 的挑战 nonce
        self._seq = random.randrange(0, 0x10000)
        self._seq_lock = threading.Lock()
        self._waiters = {}                  # seq -> [Event, (errno, flags, body) | None]
        self._cond = threading.Condition()
        self._tx_lock = threading.Lock()
        self._alive = True
        self._last_frame_at = None      # 最近一次收到任何帧的时间(monotonic)
        self._t = threading.Thread(target=self._reader, daemon=True)
        self._t.start()

    # ---------- 内部 ----------
    def _next_seq(self):
        with self._seq_lock:
            self._seq = (self._seq + 1) & 0xFFFF
            return self._seq

    def _send(self, subcmd, body, seq):
        payload = pack_payload(subcmd, 0, seq, body)
        with self._tx_lock:
            self.ser.write(build_frame(SOC_CMD_USER_CMD, 0, payload))
            self.ser.flush()

    def _reader(self):
        parser = FrameParser()
        while self._alive:
            try:
                data = self.ser.read(4096)
            except (serial.SerialException, TypeError, ValueError, OSError):
                break
            if not data:
                continue
            parser.feed(data)
            for cmd, _addr, payload in parser.poll():
                self._last_frame_at = time.monotonic()
                if cmd == SOC_CMD_USER_CMD and len(payload) >= 5 \
                        and payload[0] == UC_VERSION:
                    flags = payload[2]
                    seq = struct.unpack("<H", payload[3:5])[0]
                    body = payload[5:]
                    errno = body[0] if (flags & FLAG_ERR and len(body) > 0) else 0
                    item = (errno, flags, body)
                    with self._cond:
                        w = self._waiters.get(seq)
                        if w is not None and w[1] is None:
                            w[1] = item
                            w[0].set()
                            self._cond.notify_all()
                elif cmd == 0 and self.log_handler:
                    try:
                        self.log_handler(payload)
                    except Exception:
                        pass

    def _register(self, seq):
        with self._cond:
            w = [threading.Event(), None]
            self._waiters[seq] = w
            return w

    def _unregister(self, seq):
        with self._cond:
            self._waiters.pop(seq, None)

    def _request(self, subcmd, body, timeout, retries, data_class=False):
        """发请求并等回应, 超时重发(同 seq, 设备幂等/去重), 返回 (errno, flags, body)"""
        seq = self._next_seq()
        w = self._register(seq)
        try:
            for attempt in range(retries):
                self._send(subcmd, body, seq)
                if w[0].wait(timeout):
                    errno, flags, resp = w[1]
                    return errno, flags, resp
            raise UserCmdError(-1, f"subcmd={subcmd} seq={seq} timeout x{retries}")
        finally:
            self._unregister(seq)

    def _control(self, subcmd, body):
        return self._request(subcmd, body, self.control_timeout, self.control_retries)

    @staticmethod
    def _check(errno, flags, body, context=""):
        if errno != E_OK:
            raise UserCmdError(errno, context)

    # ---------- 会话 ----------
    def hello(self):
        """握手 + 分片协商, 返回协商后的写片长; 同时更新 self.caps 与 self._nonce"""
        nonce = random.randrange(0, 0x100000000)
        errno, _flags, body = self._control(SUB_HELLO, struct.pack("<IH", nonce, self.propose_chunk))
        self._check(errno, _flags, body, "hello")
        rnonce, chunk, ver = struct.unpack("<IHB", body[:7])
        if rnonce != nonce:
            raise UserCmdError(-1, "hello nonce mismatch")
        self._nonce = rnonce
        # caps 为 v2 扩展字段, 旧固件回应仅 7 字节, 视 caps=0
        self.caps = struct.unpack("<H", body[7:9])[0] if len(body) >= 9 else 0
        self.chunk = min(self.propose_chunk, chunk)
        return self.chunk

    def auth(self, token: str) -> bool:
        """HMAC 挑战应答鉴权(须先 hello)。
        设备未配置 token(caps bit0=0)返回 False; 鉴权成功返回 True;
        mac 不匹配抛 UserCmdError(E_DENIED)"""
        if not (self.caps & CAP_AUTH_REQUIRED):
            return False
        if self._nonce is None:
            raise UserCmdError(-1, "auth: hello first")
        mac = hmac.new(token.encode(), struct.pack("<I", self._nonce),
                       hashlib.sha256).hexdigest().encode()
        errno, _f, body = self._control(SUB_AUTH, bytes([len(mac)]) + mac)
        self._check(errno, _f, body, "auth")
        return body[0] == 1

    def wait_ready(self, timeout: float = 20.0, quiet: float = 0.8, silent_fallback: float = 6.0):
        """等设备启动完成并完成握手。
        打开串口会复位设备; 启动期间下行发帧会破坏启动(实测), 故先等日志流静默再握手。
        设备无日志输出时按 silent_fallback 秒保底。"""
        deadline = time.monotonic() + timeout
        fb = time.monotonic() + silent_fallback
        while time.monotonic() < deadline:
            t = self._last_frame_at
            if t is not None and (time.monotonic() - t) >= quiet:
                break
            if t is None and time.monotonic() >= fb:
                break
            time.sleep(0.05)
        last_err = None
        while time.monotonic() < deadline:
            try:
                return self.hello()
            except UserCmdError as e:
                last_err = e
                time.sleep(0.5)
        if last_err:
            raise last_err
        raise UserCmdError(-1, "wait_ready timeout")

    def close_port(self):
        self._alive = False
        try:
            self.ser.close()
        except Exception:
            pass

    # ---------- 控制类 ----------
    def open(self, path: str, mode: str = "r") -> int:
        if mode not in _MODE:
            raise ValueError(f"mode must be one of {_MODE.keys()}")
        pb = path.encode()
        if len(pb) > 127:
            raise ValueError("path too long")
        errno, _f, body = self._control(SUB_OPEN, bytes([_MODE[mode]]) + pb)
        self._check(errno, _f, body, f"open {path}")
        return body[0]

    def close(self, fd: int) -> int:
        """关闭句柄, 返回文件最终大小"""
        errno, _f, body = self._control(SUB_CLOSE, bytes([fd]))
        self._check(errno, _f, body, f"close fd={fd}")
        return struct.unpack("<I", body[:4])[0]

    def mkdir(self, path: str):
        errno, _f, _b = self._control(SUB_MKDIR, path.encode())
        self._check(errno, _f, _b, f"mkdir {path}")

    def rmdir(self, path: str):
        errno, _f, _b = self._control(SUB_RMDIR, path.encode())
        self._check(errno, _f, _b, f"rmdir {path}")

    def remove(self, path: str):
        errno, _f, _b = self._control(SUB_REMOVE, path.encode())
        self._check(errno, _f, _b, f"remove {path}")

    def stat(self, path: str):
        """返回 (type, size): type 0=file 1=dir; 不存在抛 UserCmdError(E_NOENT)"""
        errno, _f, body = self._control(SUB_STAT, path.encode())
        self._check(errno, _f, body, f"stat {path}")
        t, size = struct.unpack("<BI", body[:5])
        return t, size

    def exists(self, path: str) -> bool:
        errno, _f, body = self._control(SUB_EXISTS, path.encode())
        self._check(errno, _f, body, f"exists {path}")
        return body[0] != 0

    def lsdir(self, path: str, page_size: int = 100):
        """枚举目录, 自动翻页聚合, 返回 [{name, type, size}, ...]
        page_size 为单次请求的条目数(仅影响翻页粒度, 用于测试分页)"""
        pb = path.encode()
        entries = []
        offset = 0
        while True:
            body = bytes([len(pb)]) + pb + struct.pack("<IH", offset, page_size)
            errno, flags, resp = self._control(SUB_LSDIR, body)
            self._check(errno, flags, resp, f"lsdir {path}")
            _remaining, elen = struct.unpack("<IH", resp[:6])
            data = resp[6:6 + elen]     # 尾部可能随带4对齐填充, 必须按 elen 截取
            i = 0
            n = 0
            while i + 6 <= len(data):
                t = data[i]
                size = struct.unpack("<I", data[i + 1:i + 5])[0]
                nl = data[i + 5]
                name = data[i + 6:i + 6 + nl]
                if len(name) < nl:
                    break
                entries.append({"name": name.decode("utf-8", "ignore"), "type": t, "size": size})
                i += 6 + nl
                n += 1
            if not (flags & FLAG_MORE):
                break
            if n == 0:
                raise UserCmdError(-1, "lsdir paginate stuck")
            offset += n
        return entries

    def lsmount(self):
        """枚举挂载点, 返回 [{'path': '/', 'fs': 'soc'}, ...](根挂载归一化为 '/'）"""
        errno, _f, resp = self._control(SUB_LSMOUNT, b"")
        self._check(errno, _f, resp, "lsmount")
        elen = struct.unpack("<H", resp[:2])[0]
        data = resp[2:2 + elen]     # 尾部可能随带4对齐填充, 必须按 elen 截取
        mounts = []
        i = 0
        while i + 2 <= len(data):
            pl = data[i]
            path = data[i + 1:i + 1 + pl]
            i += 1 + pl
            if i + 1 > len(data):
                break
            fl = data[i]
            fst = data[i + 1:i + 1 + fl]
            i += 1 + fl
            if len(path) < pl or len(fst) < fl:
                break
            path = path.decode("utf-8", "ignore")
            mounts.append({"path": path if path else "/", "fs": fst.decode("utf-8", "ignore")})
        return mounts

    def fsstat(self, path: str):
        """查询文件系统空间, 返回 {'total': bytes, 'used': bytes, 'block_size': bytes, 'fs': str}
        path 指向未挂载路径抛 UserCmdError(E_NOENT)"""
        errno, _f, body = self._control(SUB_FSSTAT, path.encode())
        self._check(errno, _f, body, f"fsstat {path}")
        total, used, bs = struct.unpack("<III", body[:12])
        tl = body[12]
        fst = body[13:13 + tl].decode("utf-8", "ignore")
        return {"total": total, "used": used, "block_size": bs, "fs": fst}

    # ---------- 数据类(滑动窗口) ----------
    def _write_window(self, fd: int, data: bytes, base: int = 0):
        """滑动窗口发送, 每片独立超时重传(同seq, 设备幂等), 设备回应按seq匹配
        base 为起始偏移(追加写用)"""
        chunk = self.chunk
        frags = [(base + off, data[off:off + chunk]) for off in range(0, len(data), chunk)]
        pending = {}   # seq -> [offset, frag, attempts, deadline]
        next_i = 0
        acked = 0
        try:
            while acked < len(frags):
                with self._cond:
                    while next_i < len(frags) and len(pending) < self.window:
                        off, frag = frags[next_i]
                        seq = self._next_seq()
                        self._waiters[seq] = [threading.Event(), None]
                        pending[seq] = [off, frag, 1, time.monotonic() + self.data_timeout]
                        self._send(SUB_WRITE, bytes([fd]) + struct.pack("<I", off) + frag, seq)
                        next_i += 1
                    if not pending:
                        break
                    nearest = min(v[3] for v in pending.values())
                    self._cond.wait(max(0.005, nearest - time.monotonic()))
                for seq in list(pending):
                    off, frag, attempts, deadline = pending[seq]
                    w = self._waiters.get(seq)
                    if w is not None and w[0].is_set():
                        errno = w[1][0]
                        self._unregister(seq)
                        del pending[seq]
                        acked += 1
                        if errno != E_OK:
                            raise UserCmdError(errno, f"write offset={off}")
                    elif time.monotonic() >= deadline:
                        if attempts >= self.data_retries:
                            raise UserCmdError(-1, f"write offset={off} timeout x{attempts}")
                        self._send(SUB_WRITE, bytes([fd]) + struct.pack("<I", off) + frag, seq)
                        pending[seq][2] = attempts + 1
                        pending[seq][3] = time.monotonic() + self.data_timeout
        finally:
            for seq in list(pending):
                self._unregister(seq)

    def _read_window(self, fd: int) -> bytes:
        """流水线读, 按 offset 重组; 短读(rlen<chunk)标记 EOF"""
        chunk = self.read_chunk
        buf = bytearray()
        pieces = {}    # offset -> bytes
        next_off = 0   # 已连续拼到的位置
        eof_off = None
        issued = 0
        pending = {}   # seq -> [offset, attempts, deadline]
        try:
            while True:
                with self._cond:
                    while len(pending) < self.window and (eof_off is None or issued < eof_off):
                        off = issued
                        seq = self._next_seq()
                        self._waiters[seq] = [threading.Event(), None]
                        pending[seq] = [off, 1, time.monotonic() + self.data_timeout]
                        self._send(SUB_READ, bytes([fd]) + struct.pack("<IH", off, chunk), seq)
                        issued += chunk
                    if not pending:
                        break
                    nearest = min(v[2] for v in pending.values())
                    self._cond.wait(max(0.005, nearest - time.monotonic()))
                now = time.monotonic()
                for seq in list(pending):
                    off, attempts, deadline = pending[seq]
                    w = self._waiters.get(seq)
                    if w is not None and w[0].is_set():
                        errno, _flags, body = w[1]
                        self._unregister(seq)
                        del pending[seq]
                        if errno != E_OK:
                            raise UserCmdError(errno, f"read offset={off}")
                        roff, rlen = struct.unpack("<IH", body[1:7])
                        pieces[roff] = body[7:7 + rlen]
                        if rlen < chunk and (eof_off is None or roff + rlen < eof_off):
                            eof_off = roff + rlen
                    elif now >= deadline:
                        if attempts >= self.data_retries:
                            raise UserCmdError(-1, f"read offset={off} timeout x{attempts}")
                        self._send(SUB_READ, bytes([fd]) + struct.pack("<IH", off, chunk), seq)
                        pending[seq][1] = attempts + 1
                        pending[seq][2] = now + self.data_timeout
                while next_off in pieces:
                    buf += pieces.pop(next_off)
                    next_off = len(buf)
                if eof_off is not None and next_off >= eof_off:
                    break
        finally:
            for seq in list(pending):
                self._unregister(seq)
        return bytes(buf)

    # ---------- 组合 API ----------
    def write_file(self, path: str, data: bytes, append: bool = False) -> int:
        """写文件(自动分片+窗口+重传), 返回文件大小
        append=True 时接在已有内容后写(经 stat 定位尾部, 不依赖设备a模式的seek语义)"""
        base = 0
        if not append:
            fd = self.open(path, "w")
        else:
            try:
                _t, size = self.stat(path)
            except UserCmdError as e:
                if e.errno != E_NOENT:
                    raise
                fd = self.open(path, "w")
            else:
                fd = self.open(path, "r+")
                base = size
        try:
            if data:
                self._write_window(fd, data, base)
            return self.close(fd)
        except Exception:
            try:
                self.close(fd)
            except Exception:
                pass
            raise

    def read_file(self, path: str) -> bytes:
        fd = self.open(path, "r")
        try:
            return self._read_window(fd)
        finally:
            try:
                self.close(fd)
            except Exception:
                pass

    def request(self, subcmd: int, body: bytes):
        """原始控制类请求, 返回 (errno, flags, body)"""
        return self._control(subcmd, body)
