# -*- coding: utf-8 -*-
"""usercmd v2.2 payload 帧格式纯软件往返测试(无需串口/设备)

v2.2 起 payload 不含 MAGIC, 固定头 5 字节:
  u8 version + u8 subcmd + u8 flags + u16 seq(LE) + body
"""
import struct
import threading
import time

import pytest

import luat_usercmd
from luat_usercmd import (
    E_DENIED,
    E_IO,
    FLAG_ERR,
    SOC_CMD_USER_CMD,
    SUB_CLOSE,
    SUB_OPEN,
    SUB_READ,
    SUB_STAT,
    SUB_WRITE,
    UC_VERSION,
    FrameParser,
    UserCmd,
    UserCmdError,
    build_frame,
    pack_payload,
    parse_payload,
    write_ack_offset,
)


def test_pack_parse_payload_roundtrip():
    body = bytes(range(256)) * 2          # 512 字节, 覆盖各种取值
    p = pack_payload(4, FLAG_ERR, 0x1234, body)
    assert p[:5] == bytes([UC_VERSION, 4, FLAG_ERR]) + struct.pack("<H", 0x1234)
    ver, subcmd, flags, seq, pb = parse_payload(p)
    assert (ver, subcmd, flags, seq) == (UC_VERSION, 4, FLAG_ERR, 0x1234)
    assert pb == body


def test_pack_parse_payload_seq_boundary():
    """seq 边界值 0xFFFF 往返"""
    body = b"boundary"
    p = pack_payload(13, 0, 0xFFFF, body)
    assert p[3:5] == b"\xff\xff"
    ver, subcmd, flags, seq, pb = parse_payload(p)
    assert (ver, subcmd, flags, seq) == (UC_VERSION, 13, 0, 0xFFFF)
    assert pb == body


def test_parse_payload_too_short():
    with pytest.raises(ValueError):
        parse_payload(b"\x01\x02")


def test_usercmd_frame_roundtrip_over_a5():
    """usercmd 帧经 A5 组帧 -> 流式解包后仍保留 cmd 码与完整 payload(含转义字节)"""
    body = b"\xa5\xa6\x00\xff" * 30       # 120 字节, 含链路层特殊字节
    p = pack_payload(0, 0, 7, body)
    pkt = build_frame(SOC_CMD_USER_CMD, 0, p)
    parser = FrameParser()
    for i in range(0, len(pkt), 7):       # 小步喂入, 验证流式重组
        parser.feed(pkt[i:i + 7])
    frames = parser.poll()
    assert len(frames) == 1
    cmd, addr, payload = frames[0]
    assert cmd == SOC_CMD_USER_CMD        # 设备上行帧经此 cmd 码识别
    assert addr == 0
    assert payload == p


def test_usercmd_frame_split_across_polls():
    """同一字节流分两次 poll: 半帧不产出, 完整后产出恰好一帧"""
    p = pack_payload(13, 0, 0xBEEF, b"/")
    pkt = build_frame(SOC_CMD_USER_CMD, 0, p)
    cut = len(pkt) // 2
    parser = FrameParser()
    parser.feed(pkt[:cut])
    assert parser.poll() == []
    parser.feed(pkt[cut:])
    frames = parser.poll()
    assert len(frames) == 1
    assert frames[0][0] == SOC_CMD_USER_CMD
    assert frames[0][2] == p


class _FakeSerial:
    """假串口: read 从注入队列取字节, 无数据时 sleep 0.05 返回 b"" (与真 Serial timeout 行为一致)"""

    def __init__(self, port, baud, timeout=None):
        self.dtr = True
        self.rts = True
        self._rx = bytearray()
        self._lock = threading.Lock()

    def reset_input_buffer(self):
        with self._lock:
            self._rx.clear()

    def read(self, n=1):
        with self._lock:
            if self._rx:
                out = bytes(self._rx[:n])
                del self._rx[:n]
                return out
        time.sleep(0.05)
        return b""

    @property
    def in_waiting(self):
        with self._lock:
            return len(self._rx)

    def write(self, data):
        return len(data)

    def flush(self):
        pass

    def close(self):
        pass

    def feed(self, data):
        """测试侧: 向 reader 注入接收字节流"""
        with self._lock:
            self._rx += data


def _wait_until(cond, timeout=2.0):
    """带截止时间的条件轮询, 超时返回 False"""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if cond():
            return True
        time.sleep(0.005)
    return cond()


def test_reader_frame_classification(monkeypatch):
    """_reader 按 cmd 码分类帧:
    usercmd ERR 回包唤醒 waiter(含 errno 提取), 日志帧走 log_handler 不唤醒 waiter,
    version 字节错误的 usercmd 帧被静默丢弃"""
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    logs = []
    dev = UserCmd("COM_FAKE", log_handler=logs.append)
    try:
        ser = dev.ser

        # usercmd ERR 回包: 唤醒对应 seq 的 waiter, item = (errno, flags, body)
        seq = 0x1234
        w = dev._register(seq)
        body = bytes([E_DENIED, 0xAA, 0xBB])        # FLAG_ERR 时 body[0] 为 errno
        ser.feed(build_frame(SOC_CMD_USER_CMD, 0, pack_payload(4, FLAG_ERR, seq, body)))
        assert w[0].wait(2.0), "usercmd ERR 回包未唤醒 waiter"
        assert w[1] == (E_DENIED, FLAG_ERR, body)
        dev._unregister(seq)

        # 日志帧(cmd==0): 进 log_handler, 不唤醒任何 waiter
        seq2 = 0x2222
        w2 = dev._register(seq2)
        log_payload = b"log line \xa5\xa6\x00"
        ser.feed(build_frame(0, 0, log_payload))
        assert _wait_until(lambda: logs == [log_payload]), "日志帧未进 log_handler"
        assert not w2[0].is_set(), "日志帧误唤醒 waiter"
        dev._unregister(seq2)

        # cmd==SOC_CMD_USER_CMD 但 version 字节错误: 静默丢弃
        seq3 = 0x3333
        w3 = dev._register(seq3)
        bad = bytes([0xEE, 0, 0]) + struct.pack("<H", seq3) + b"x"
        ser.feed(build_frame(SOC_CMD_USER_CMD, 0, bad))
        # 再喂 marker 日志帧: reader 顺序处理, marker 出现即证明 bad 帧已被处理, 无需裸 sleep
        marker = b"marker-log"
        ser.feed(build_frame(0, 0, marker))
        assert _wait_until(lambda: logs[-1:] == [marker]), "marker 日志帧未被处理"
        assert not w3[0].is_set(), "version 错误的帧唤醒了 waiter"
        assert w3[1] is None
        dev._unregister(seq3)
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


def test_write_ack_offset_parse():
    """WRITE_DATA 成功回应 body = u8 fd + u32 offset; 截断的 body 返回 None"""
    assert write_ack_offset(bytes([1]) + struct.pack("<I", 476)) == 476
    assert write_ack_offset(bytes([1]) + struct.pack("<I", 0)) == 0
    assert write_ack_offset(b"\x01\x02") is None
    assert write_ack_offset(b"") is None


class _ScriptedDevice:
    """最小设备桩: 解析下行 usercmd 请求, 按 responder 回包(纯软件, 无需真机)

    responder(subcmd, seq, body) -> (flags, resp_body)
    """

    def __init__(self, ser, responder):
        self.ser = ser
        self.responder = responder
        self.parser = FrameParser()
        self.calls = []

    def on_downlink(self, data):
        self.parser.feed(data)
        for cmd, _addr, payload in self.parser.poll():
            if cmd != SOC_CMD_USER_CMD or len(payload) < 5:
                continue
            _v, sub, _fl, seq, body = parse_payload(payload)
            self.calls.append((sub, seq, body))
            flags, rbody = self.responder(sub, seq, body)
            self.ser.feed(build_frame(SOC_CMD_USER_CMD, 0, pack_payload(sub, flags, seq, rbody)))


def _attach_scripted_device(dev, responder):
    """把设备桩挂到假串口的 write 上: _send 写入的帧被解析并就地产生回应"""
    dev_stub = _ScriptedDevice(dev.ser, responder)
    real_write = dev.ser.write

    def hooked_write(data, _real=real_write, _stub=dev_stub):
        _stub.on_downlink(data)
        return _real(data)

    dev.ser.write = hooked_write
    return dev_stub


def _open_close_responder(close_size, write_off_shift=0, seen_writes=None):
    """open 恒成功(fd=1); close 回固定 size; write 回显 offset(+可注入偏移)"""

    def responder(sub, seq, body):
        if sub == SUB_OPEN:
            return 0, bytes([1])
        if sub == SUB_CLOSE:
            return 0, struct.pack("<I", close_size)
        if sub == SUB_WRITE:
            off = struct.unpack("<I", body[1:5])[0]
            if seen_writes is not None:
                seen_writes[off] = seen_writes.get(off, 0) + 1
            return 0, bytes([1]) + struct.pack("<I", off + write_off_shift)
        return 0, b""

    return responder


def test_write_window_retransmits_on_mismatched_ack(monkeypatch):
    """设备回显偏移与请求不符时, host 拒绝该确认并重传同 seq, 而不是当作成功"""
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE", window=2, data_timeout=0.3, data_retries=8)
    try:
        dev.chunk = 476          # 未经 HELLO 协商, 手工设为真实片长
        seen = {}
        stub = _attach_scripted_device(dev, _open_close_responder(0, 0, seen))
        # 首个非 0 偏移的片故意回错偏移, 之后回正确值(片长由内容自适应决定, 不写死偏移)
        real_responder = stub.responder
        state = {"bogus": True}

        def responder(sub, seq, body):
            if sub == SUB_WRITE:
                off = struct.unpack("<I", body[1:5])[0]
                if off != 0 and state["bogus"]:
                    state["bogus"] = False
                    seen[off] = seen.get(off, 0) + 1
                    return 0, bytes([1]) + struct.pack("<I", 0)
            return real_responder(sub, seq, body)

        stub.responder = responder
        dev._write_window(1, b"x" * (476 * 2), 0)
        assert max(seen.values()) >= 2, f"回显偏移不符时未重传: {seen}"
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


def _split_frags(dev, data, fd=1):
    """按 host 的自适应分片逻辑切分, 返回 [(offset, frag), ...]"""
    frags = []
    off = 0
    while off < len(data):
        n = dev._frag_len(fd, off, data[off:], min(dev.chunk, len(data) - off))
        frags.append((off, data[off:off + n]))
        off += n
    return frags


@pytest.mark.parametrize("fill", [0x00, 0x5A, 0x7F, 0xA5, 0xA6, 0xFF])
def test_write_fragments_fit_wire_budget(monkeypatch, fill):
    """内容自适应分片: 任意内容下每片生成的 A5 帧线上长都不超过 wire_budget

    这是设备端 ISR 512B 抽帧缓冲的硬约束 —— 超一字节就会被拆到两次中断里, 连发时丢帧
    (实测 chunk=476 线上 518B 时 64K 写要重传 8 次、吞吐掉 15 倍)。
    """
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE")
    try:
        dev.chunk = 476
        data = bytes([fill]) * 4096
        frags = _split_frags(dev, data)
        assert sum(len(f) for _, f in frags) == len(data), "分片未覆盖全部数据"
        assert [o for o, _ in frags] == sorted(o for o, _ in frags), "分片偏移非递增"
        for off, frag in frags:
            wire = len(dev._build_write_frame(1, off, frag))
            assert wire <= dev.wire_budget, f"fill={fill:#x} off={off} wire={wire}"
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


@pytest.mark.parametrize("fill,lo,hi", [(0x5A, 470, 476), (0xA5, 200, 250), (0xA6, 200, 250)])
def test_write_frag_len_adapts_to_escaping(monkeypatch, fill, lo, hi):
    """无转义内容取满片长, 全 0xA5/0xA6(最坏 1->2 膨胀)自动收窄到理论极限附近

    全转义时: 线上长 = 2 + 26 + 2n + 少量表头转义 <= wire_budget, 故 n 约 240
    (固定 chunk 若按"整帧最坏 2 倍"保守估算只能取 219, 自适应按真实字节算得更准)
    """
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE")
    try:
        dev.chunk = 476
        frags = _split_frags(dev, bytes([fill]) * 1024)
        longest = max(len(f) for _, f in frags)
        assert lo <= longest <= hi, f"fill={fill:#x} 最长片={longest}"
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


def test_read_window_default_is_one(monkeypatch):
    """实测 W=1 最快(读 235KB/s vs W=8 110KB/s), 默认值不能被改回大窗口"""
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE")
    try:
        assert dev.window == 1 and dev.write_window == 1
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


def test_read_chunk_default_within_response_fifo(monkeypatch):
    """read_chunk 必须在设备端 response_fifo 容量内

    厂商新固件(2026-09-18 起)命令响应走 TX 侧 16KB 专用 response_fifo, 不再受
    1600B log record 截断(旧固件 read_chunk=760 的约束已消除)。
    最坏(每字节都转义)线上长 = 1 + 2*(24帧头 + 7应用头 + n) + 4(CRC) + 1(A5) <= 16384 -> n <= 8159。
    """
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE")
    try:
        fifo_max = 16 * 1024
        worst_safe = (fifo_max - 1 - 4 - 1) // 2 - 24 - 7   # = 8159
        assert dev.read_chunk == 4096, "read_chunk 默认值被改动, 请重新实测后再定"
        assert dev.read_chunk <= worst_safe, \
            f"read_chunk={dev.read_chunk} 超过任意内容安全上限 {worst_safe}"
        assert 1 + 2 * (24 + 7 + dev.read_chunk) + 4 + 1 <= fifo_max, \
            "默认档的最坏线上长必须放得下 response_fifo"
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


def test_read_window_rejects_truncated_response(monkeypatch):
    """设备端响应被截断(声明的 len 大于实到数据)必须显式报错

    放过它就是最坏的一种错: read_file 会把截断当成正常短读/EOF, 静默返回残缺内容。
    """
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE", data_timeout=0.3, data_retries=5)
    try:
        def responder(sub, seq, body):
            if sub == SUB_OPEN:
                return 0, bytes([1])
            if sub == SUB_CLOSE:
                return 0, struct.pack("<I", 0)
            if sub == SUB_READ:
                return 0, bytes([1]) + struct.pack("<IH", 0, 512) + b"x" * 100
            return 0, b""

        _attach_scripted_device(dev, responder)
        with pytest.raises(UserCmdError) as ei:
            dev.read_file("/f.bin")
        assert "截断" in str(ei.value), str(ei.value)
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


def test_read_file_rejects_size_mismatch(monkeypatch):
    """读到多少字节与 stat 报的大小不符时必须报错(兜底, 防任何未察觉的截断)"""
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE", data_timeout=0.3, data_retries=5)
    try:
        def responder(sub, seq, body):
            if sub == SUB_OPEN:
                return 0, bytes([1])
            if sub == SUB_CLOSE:
                return 0, struct.pack("<I", 0)
            if sub == SUB_READ:
                return 0, bytes([1]) + struct.pack("<IH", 0, 10) + b"x" * 10
            if sub == SUB_STAT:
                return 0, bytes([0]) + struct.pack("<I", 99)   # 文件其实有 99 字节
            return 0, b""

        _attach_scripted_device(dev, responder)
        with pytest.raises(UserCmdError) as ei:
            dev.read_file("/f.bin")
        assert "stat 为" in str(ei.value), str(ei.value)
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


def test_write_file_rejects_short_final_size(monkeypatch):
    """close 返回的最终大小与预期不符(设备静默丢弃写)时必须报错, 不能静默成功"""
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE", window=2, data_timeout=0.3, data_retries=8)
    try:
        _attach_scripted_device(dev, _open_close_responder(close_size=476 - 1))
        with pytest.raises(UserCmdError) as ei:
            dev.write_file("/ram/f.bin", b"x" * 476)
        assert ei.value.errno == E_IO
        assert "size" in str(ei.value)
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)


def test_write_file_accepts_exact_final_size(monkeypatch):
    """尺寸一致时正常返回(对照组)"""
    monkeypatch.setattr(luat_usercmd.serial, "Serial", _FakeSerial)
    dev = UserCmd("COM_FAKE", window=2, data_timeout=0.3, data_retries=8)
    try:
        _attach_scripted_device(dev, _open_close_responder(close_size=476 * 2))
        assert dev.write_file("/ram/f.bin", b"x" * (476 * 2)) == 476 * 2
    finally:
        dev._alive = False
        dev._t.join(timeout=2.0)

