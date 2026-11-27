#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 480×320 的原始片 fruit.hzv 重新封装成目标屏幕能播的尺寸。

为什么需要这个：
  原始片是 480×320 / 14.5 秒 / 10fps / 带 MP3 音轨，要同时喂给两种屏：
  1. 尺寸：4.3 寸工装屏只有 480×272，高 320 超一截，得缩成 336×224；
     7 寸 1024×600 反而能放原片尺寸，缩了浪费。airui.videoplayer 不支持缩放，
     控件尺寸必须等于素材帧尺寸，所以只能按屏分别出素材。
  2. 音轨：8801 只有蜂鸣器、没有功放和喇叭，MP3 轨播不出来，留着纯占空间。

脚本区容量的实测值以 Luatools「下载成功 脚本区总空间:xxxxKB,已使用xxxxKB」为准，
本机 Air8801 + Air1601_A10 底包报的是 4096KB，不是 512KB —— 两份素材加代码约 3.7 MiB，
放得下，不需要激进压缩。

HZV v1 容器（与固件 components/hzv/src/luat_hzv.c 对齐）：
  文件头 128 字节（u32 索引 → 字节偏移 = 索引 × 4）
      0    "HZV1"
      4    u16 version_major = 1
      8    u32 header_size = 128
      12   u32 flags（1 视频 / 2 音频 / 8 包 CRC32 / 16 定帧率 / 64 循环）
      16   u32 timescale（非 0）
      20   u32 stream_count
      24   u64 duration
      32   u64 packet_data_offset
      40   u64 index_offset
      48   u64 index_size
      56   u32 packet_count
      60   u32 video_frame_count（必须 > 0，否则 open 失败）
      64   u32 video_codec（1 = MJPEG）
      68   u16 width / 70 u16 height
      72   u32 fps_num / 76 u32 fps_den
      80   u32 video_output_format
      84   u32 audio_codec（0 = NONE）
      88   u32 audio_sample_rate
      92   u16 channels / 94 u16 bits
      96   u32 audio_frame_samples
      100  u32 max_video_packet
      104  u32 max_audio_packet
      108  u32 header_crc32（对 108..111 清零后的 128 字节头算）
  块序列，每块 32 字节头：
      0    "HZPK"
      4    u16 头长 = 32
      6    u8  stream_id（0 = 视频，1 = 音频）
      7    u8  flags
      8    u64 pts
      16   u32 duration
      20   u32 payload 长度
      24   u32 payload crc32
      28   u32 sequence（按流各自递增）
      32   payload，补 0 对齐到 4 字节
  索引区 "HZIX"：顺序播放不需要，本脚本整段丢掉（index_size = 0）
  文件尾 "HZTL" 32 字节：块区结束偏移 + 索引长度

三条硬要求（少一条固件就 open 失败或一个视频帧都读不到）：
  1. video_frame_count 必须等于实际视频包数，写 0 会被 luat_hzv_open 直接拒绝；
  2. 改过任何头字段都必须重算 108 处的 CRC32；
  3. 视频包必须 stream_id = 0，写成 1 会被当成音频包跳过。
  本脚本末尾的 verify() 复刻了上述判据，输出 PASS 才算可用。

用法：
  python tools/hzv_mini.py                      # 默认 both：小屏小份 + 7 寸原片尺寸大份
  python tools/hzv_mini.py --preset small       # 只出 fruit.hzv（4/5 寸）
  python tools/hzv_mini.py --preset hd          # 只出 fruit_hd.hzv（7 寸以上）
  python tools/hzv_mini.py --fit-to 800x432     # 临时按某个可用区算尺寸，单份输出
  python tools/hzv_mini.py --quality 70         # 提高画质（体积会涨）
  python tools/hzv_mini.py --target-kb 600      # 限制单份输出体积
"""

import argparse
import io
import struct
import sys
import zlib
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow: pip install pillow")

HDR_LEN = 128
BLK_HDR = 32
TAIL_LEN = 32
MAGIC_FILE = b"HZV1"
MAGIC_BLK = b"HZPK"
MAGIC_TAIL = b"HZTL"

# 本文件在 Air8801/tools/，产物写到 Air8801/project/factory/（那才是烧录目录）。
# 原始片留在 tools/ 是刻意的：Luatools 按整个 factory 目录打包，1.9MB 的原片放进去必超 4MB 脚本区。
DEFAULT_SRC = Path(__file__).resolve().parent / "fruit_full.hzv"
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "project" / "factory" / "fruit.hzv"


def parse_blocks(data, end):
    """按块链切分到 end 为止。

    块头布局（与固件 luat_hzv.c 一致）：
        +0  "HZPK"
        +4  u16 块头长度 = 32
        +6  u8  stream_id（0=视频 1=音频）
        +7  u8  flags
        +8  u64 pts（毫秒）
        +16 u32 duration
        +20 u32 payload 长度
        +24 u32 payload crc32
        +28 u32 sequence（按流各自递增）
    返回 [(offset, total_len, stream_id, pts, duration, datalen)]
    """
    blocks = []
    p = HDR_LEN
    while p + BLK_HDR <= end:
        if data[p:p + 4] != MAGIC_BLK:
            raise ValueError("块魔数不匹配，偏移 %d" % p)
        stream_id = data[p + 6]
        pts = struct.unpack("<Q", data[p + 8:p + 16])[0]
        duration = struct.unpack("<I", data[p + 16:p + 20])[0]
        datalen = struct.unpack("<I", data[p + 20:p + 24])[0]
        total = BLK_HDR + ((datalen + 3) & ~3)
        if p + total > end:
            raise ValueError("块越界，偏移 %d 需要 %d 字节" % (p, total))
        blocks.append((p, total, stream_id, pts, duration, datalen))
        p += total
    if p != end:
        raise ValueError("块链走完停在 %d，声明的块区结束是 %d" % (p, end))
    return blocks


def build_block(pts, duration, sequence, payload):
    """按固件块格式组装视频块（stream_id=0, flags=1, 含 crc32 与 4 字节对齐补零）。"""
    hdr = bytearray(BLK_HDR)
    hdr[0:4] = MAGIC_BLK
    struct.pack_into("<H", hdr, 4, BLK_HDR)
    hdr[6] = 0                                  # stream_id = 视频
    hdr[7] = 1                                  # flags
    struct.pack_into("<Q", hdr, 8, pts)         # u64 pts
    struct.pack_into("<I", hdr, 16, duration)
    struct.pack_into("<I", hdr, 20, len(payload))
    struct.pack_into("<I", hdr, 24, zlib.crc32(payload) & 0xFFFFFFFF)
    struct.pack_into("<I", hdr, 28, sequence)
    pad = (-len(payload)) % 4
    return bytes(hdr) + payload + b"\x00" * pad


def reencode_videos(data, blocks, size, quality):
    """把视频块解出来缩放重编码，返回 [(pts, duration, jpeg_bytes)]。

    音频块（stream_id=1）直接跳过：8801 没有功放，音轨播不出来。
    pts / duration 沿用原块，所以播放节奏和原片一致。
    """
    out = []
    for off, _total, stream_id, pts, duration, datalen in blocks:
        if stream_id != 0:
            continue
        raw = data[off + BLK_HDR:off + BLK_HDR + datalen]
        try:
            im = Image.open(io.BytesIO(raw)).convert("RGB")
        except Exception as exc:
            print("跳过一帧（解码失败）: %s" % exc)
            continue
        if size:
            im = im.resize(size, Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=quality, optimize=True)
        out.append((pts, duration, buf.getvalue()))
    return out


# 两种预设：小屏与大屏各出一份，按屏宽选播哪一支。
#
#   small  4.3 寸 480×272 与 5 寸 800×480 屏用：原片按比例缩到 336×224，
#          105 帧约 1.17 MiB，视频区 480×224 正好放得下。
#   hd     7 / 9 / 10 寸 1024×600 屏用：铺满视频区，按 3:2 取 828×552，
#          占屏宽 81%，68 帧约 2.04 MiB。
#
# 7 寸为什么不保持原片尺寸 480×320：那在 1024 宽的屏上只占 47%，两侧各留 272px 空白，
# 看上去就是中间一小块。视频组件不支持缩放（luat_airui_video.c 里写死
# "scaling is not supported yet" 并把控件尺寸强行改回素材尺寸），想让画面变大只能
# 把素材本身放大后重编码 —— 同样的体积只能装更少的帧，68 帧约 6.8 秒一循环。
#
# 两份合计 + 代码约 3.65 MiB，脚本区 4 MiB 放得下，余 400KB 左右。
# 屏宽 ≥ 1024 走 hd，否则走 small —— 判据在 ui/video_win.lua 的 asset_names()，两处口径必须一致。
PRESETS = {
    "small": {"size": (336, 224), "target_kb": 1200, "quality": 65, "name": "fruit.hzv"},
    "hd":    {"size": (828, 552), "target_kb": 2100, "quality": 45, "name": "fruit_hd.hzv"},
}


def pack_one(data, blocks, size, quality, target_kb, out):
    """按给定尺寸重编码并封装，返回 True 表示固件校验通过。"""
    frames = reencode_videos(data, blocks, size, quality)
    if not frames:
        sys.exit("没有解出任何视频帧")

    # 按目标大小取前缀
    target = target_kb * 1024
    kept, used = [], HDR_LEN + TAIL_LEN
    for seq, (pts, duration, jpeg) in enumerate(frames):
        blk = build_block(pts, duration, seq, jpeg)
        if used + len(blk) > target:
            break
        kept.append(blk)
        used += len(blk)
    if not kept:
        sys.exit("目标太小，一帧都放不下")

    hdr = list(struct.unpack("<32I", data[:HDR_LEN]))

    # 改头：块区结束、索引清零、包数、帧数、宽高、最大包长、头 CRC
    new_end = HDR_LEN + sum(len(b) for b in kept)
    last_pts, last_dur, _ = frames[len(kept) - 1]
    max_packet = max(len(f[2]) for f in frames[:len(kept)])
    hdr[3] = 1 | 8 | 16 | 64        # HAS_VIDEO | PACKET_CRC32 | FIXED_FPS | LOOP_HINT
    hdr[5] = 1                      # stream_count（只剩视频流）
    hdr[6] = last_pts + last_dur     # duration 低 32 位
    hdr[7] = 0                      # duration 高 32 位
    hdr[8] = HDR_LEN                # packet_data_offset
    hdr[9] = 0
    hdr[10] = new_end               # index_offset（索引区长度为 0，紧贴块区末尾）
    hdr[11] = 0
    hdr[12] = 0                     # index_size
    hdr[13] = 0
    hdr[14] = len(kept)             # packet_count
    hdr[15] = len(kept)             # video_frame_count（必须 > 0）
    hdr[16] = 1                     # video_codec = MJPEG
    hdr[17] = (size[1] << 16) | size[0]
    hdr[21] = 0                     # audio_codec = NONE
    hdr[22] = 0                     # audio_sample_rate
    hdr[23] = 0                     # channels / bits
    hdr[24] = 0                     # audio_frame_samples
    hdr[25] = max_packet            # max_video_packet
    hdr[26] = 0                     # max_audio_packet

    head = bytearray(struct.pack("<32I", *hdr))
    head[108:112] = b"\x00\x00\x00\x00"
    struct.pack_into("<I", head, 108, zlib.crc32(bytes(head)) & 0xFFFFFFFF)

    tail = MAGIC_TAIL + struct.pack("<7I", 1, new_end, 0, 0, 0, 0, 0)
    blob = bytes(head) + b"".join(kept) + tail
    out.write_bytes(blob)

    fw, fh = struct.unpack("<HH", bytes(head[68:72]))
    print("输出   : %s  %d 字节 (%.1f KiB)" % (out.name, len(blob), len(blob) / 1024.0))
    print("画面   : %d×%d  q=%d" % (fw, fh, quality))
    print("保留帧 : %d / %d（音轨已丢弃）" % (len(kept), len(frames)))
    if len(kept) < 2:
        print("警告: 只有 1 帧，看起来像静止图不是视频")

    ok = verify(blob)
    print("固件校验: %s" % ("PASS" if ok else "FAIL"))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(DEFAULT_SRC))
    ap.add_argument("--preset", default="both", choices=["small", "hd", "both"],
                    help="small=4/5 寸一份，hd=7 寸以上一份，both=两份都生成（默认）")
    ap.add_argument("--out", default=None,
                    help="输出路径；只生成一份时有效，默认按 preset 命名")
    ap.add_argument("--target-kb", type=int, default=None,
                    help="输出体积上限（KiB），默认 small=1200 / hd=2400")
    ap.add_argument("--scale", default=None,
                    help="直接指定画面 WxH；填 none 表示不缩放。给了就不看 preset 尺寸")
    ap.add_argument("--fit-to", default=None,
                    help="按可用区 WxH 自动算等比尺寸，如 480x224；给了就覆盖 preset 尺寸")
    ap.add_argument("--quality", type=int, default=None, help="JPEG 质量；不填时按预设（small=65, hd=45）")
    args = ap.parse_args()

    src = Path(args.src)
    if not src.exists():
        sys.exit("找不到源文件: %s" % src)

    data = src.read_bytes()
    if data[:4] != MAGIC_FILE:
        sys.exit("源文件不是 HZV1: %s" % data[:4])

    blocks = parse_blocks(data, struct.unpack("<32I", data[:HDR_LEN])[10])
    src_w, src_h = struct.unpack("<HH", data[68:72])

    # 显式 --scale / --fit-to 时只出一份，走 --out
    if args.scale is not None or args.fit_to is not None:
        size = None
        if args.scale and args.scale.lower() != "none":
            try:
                w, h = args.scale.lower().split("x")
                size = (int(w), int(h))
            except Exception:
                sys.exit("--scale 格式应为 WxH，例如 336x224")
            print("尺寸   : --scale 指定 %dx%d" % size)
        elif args.scale is None:
            try:
                aw, ah = args.fit_to.lower().split("x")
                aw, ah = int(aw), int(ah)
            except Exception:
                sys.exit("--fit-to 格式应为 WxH，例如 480x224")
            k = min(aw / src_w, ah / src_h)
            size = (max(2, int(src_w * k)), max(2, int(src_h * k)))
            print("尺寸   : 原片 %dx%d 等比适配可用区 %dx%d → %dx%d"
                  % (src_w, src_h, aw, ah, size[0], size[1]))
        else:
            print("尺寸   : 保持原片 %dx%d（--scale none）" % (src_w, src_h))

        out = Path(args.out) if args.out else DEFAULT_OUT
        target_kb = args.target_kb if args.target_kb is not None else 2400
        print("源文件 : %s  %d 字节 (%.1f KiB)" % (src.name, len(data), len(data) / 1024))
        ok = pack_one(data, blocks, size, args.quality or 65, target_kb, out)
        sys.exit(0 if ok else 1)

    # 预设模式：一份或两份
    names = ["small", "hd"] if args.preset == "both" else [args.preset]
    all_ok = True
    total = 0
    for name in names:
        p = PRESETS[name]
        out = Path(args.out) if (args.out and len(names) == 1) else DEFAULT_OUT.parent / p["name"]
        target_kb = args.target_kb if args.target_kb is not None else p["target_kb"]
        quality = args.quality if args.quality is not None else p["quality"]
        print("=" * 56)
        print("预设   : %s → %s（%dx%d）" % (name, out.name, p["size"][0], p["size"][1]))
        print("源文件 : %s  %d 字节 (%.1f KiB)" % (src.name, len(data), len(data) / 1024))
        ok = pack_one(data, blocks, p["size"], quality, target_kb, out)
        all_ok = all_ok and ok
        total += out.stat().st_size
    print("=" * 56)
    print("合计输出: %.1f KiB" % (total / 1024.0))
    sys.exit(0 if all_ok else 1)


def verify(blob):
    """按固件 luat_hzv_open + 包扫描的判据自检输出，返回 True/False。

    对应 components/hzv/src/luat_hzv.c：
      · magic "HZV1"、version_major == 1、header_size == 128、timescale != 0
      · offset 108 的 CRC32（先把 108..111 清零）必须匹配
      · packet_count > 0、video_frame_count > 0、video_codec == 1、宽高非 0
      · packet_data_offset < packet_end_offset <= file_size
      · 每个包 "HZPK" + u16 32，payload_size > 0，按 4 字节对齐递进
    """
    errs = []
    if len(blob) < HDR_LEN:
        return False
    if blob[:4] != MAGIC_FILE:
        errs.append("magic 不是 HZV1")
    if struct.unpack("<H", blob[4:6])[0] != 1:
        errs.append("version_major != 1")
    if struct.unpack("<I", blob[8:12])[0] != HDR_LEN:
        errs.append("header_size != 128")
    if struct.unpack("<I", blob[16:20])[0] == 0:
        errs.append("timescale == 0")

    want = struct.unpack("<I", blob[108:112])[0]
    h = bytearray(blob[:HDR_LEN])
    h[108:112] = b"\x00\x00\x00\x00"
    if (zlib.crc32(bytes(h)) & 0xFFFFFFFF) != want:
        errs.append("头 CRC 不匹配")

    packet_count = struct.unpack("<I", blob[56:60])[0]
    video_frames = struct.unpack("<I", blob[60:64])[0]
    codec = struct.unpack("<I", blob[64:68])[0]
    w, hh = struct.unpack("<HH", blob[68:72])
    data_off = struct.unpack("<Q", blob[32:40])[0]
    index_off = struct.unpack("<Q", blob[40:48])[0]
    index_size = struct.unpack("<Q", blob[48:56])[0]
    end = index_off if index_off else len(blob)
    if packet_count == 0:
        errs.append("packet_count == 0")
    if video_frames == 0:
        errs.append("video_frame_count == 0")
    if codec != 1:
        errs.append("video_codec != MJPEG")
    if w == 0 or hh == 0:
        errs.append("宽或高为 0")
    if not (HDR_LEN <= data_off < end <= len(blob)):
        errs.append("packet 区间非法")
    if index_off and index_off + index_size > len(blob):
        errs.append("索引区越界")

    p, seen = data_off, 0
    while p + BLK_HDR <= end and seen < packet_count:
        if blob[p:p + 4] != MAGIC_BLK:
            errs.append("第 %d 个包魔数不是 HZPK（偏移 %d）" % (seen, p))
            break
        if struct.unpack("<H", blob[p + 4:p + 6])[0] != BLK_HDR:
            errs.append("第 %d 个包块头长度不是 32" % seen)
            break
        if blob[p + 6] != 0:
            errs.append("第 %d 个包不是视频流（stream_id=%d）" % (seen, blob[p + 6]))
            break
        size = struct.unpack("<I", blob[p + 20:p + 24])[0]
        if size == 0:
            errs.append("第 %d 个包 payload 为 0" % seen)
            break
        p += BLK_HDR + ((size + 3) & ~3)
        seen += 1
    if seen != packet_count:
        errs.append("只走到 %d 个包，头里写的是 %d" % (seen, packet_count))

    for e in errs:
        print("  ! " + e)
    return not errs


if __name__ == "__main__":
    main()
