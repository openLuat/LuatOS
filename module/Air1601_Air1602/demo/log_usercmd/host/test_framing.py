# -*- coding: utf-8 -*-
"""usercmd v2.2 payload 帧格式纯软件往返测试(无需串口/设备)

v2.2 起 payload 不含 MAGIC, 固定头 5 字节:
  u8 version + u8 subcmd + u8 flags + u16 seq(LE) + body
"""
import struct

from luat_usercmd import (
    FrameParser,
    build_frame,
    pack_payload,
    parse_payload,
    SOC_CMD_USER_CMD,
    UC_VERSION,
    FLAG_ERR,
)


def test_pack_parse_payload_roundtrip():
    body = bytes(range(256)) * 2          # 512 字节, 覆盖各种取值
    p = pack_payload(4, FLAG_ERR, 0x1234, body)
    assert p[:5] == bytes([UC_VERSION, 4, FLAG_ERR]) + struct.pack("<H", 0x1234)
    ver, subcmd, flags, seq, pb = parse_payload(p)
    assert (ver, subcmd, flags, seq) == (UC_VERSION, 4, FLAG_ERR, 0x1234)
    assert pb == body


def test_parse_payload_too_short():
    try:
        parse_payload(b"\x01\x02")
    except ValueError:
        pass
    else:
        raise AssertionError("短帧未抛 ValueError")


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
