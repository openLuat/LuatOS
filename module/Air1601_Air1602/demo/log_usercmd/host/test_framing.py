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
    FLAG_ERR,
    SOC_CMD_USER_CMD,
    UC_VERSION,
    FrameParser,
    UserCmd,
    build_frame,
    pack_payload,
    parse_payload,
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
