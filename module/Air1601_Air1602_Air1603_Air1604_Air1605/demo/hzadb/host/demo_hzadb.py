#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hzadb 上位机演示脚本（配合 ../main.lua + ../hzadb_app.lua 使用）

跑完会依次验证：
    1. 握手 + 分片协商（HELLO）
    2. 可选鉴权（AUTH）
    3. 挂载点枚举（LSMOUNT）、根分区空间（FSSTAT）
    4. 写文件 → 读回校验 → 列目录 → stat → exists
    5. 内存状态（MEMINFO）、网络状态（NETSTAT）
    6. 删除测试文件

依赖：pyserial（pip install pyserial）

用法：
    python demo_hzadb.py --port COM6
    python demo_hzadb.py --port COM6 --baud 6000000 --dir /ram
    python demo_hzadb.py --port COM6 --token 0123456789abcdef      # 设备端配了 token 时

提示：
    - 端口被 Luatools 占用时先关掉 Luatools 里的串口，否则打不开；
    - 默认 6M 波特率是 Air1601/Air1602 的日志口速率，改过 log 波特率时用 --baud 指定；
    - 协议细节见 ../PROTOCOL.md。
"""
import argparse
import os
import struct
import sys
import time

# 允许直接在当前目录运行（不装包）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from luat_usercmd import UserCmd, UserCmdError  # noqa: E402

# hzadb 子指令号（与 script/libs/hzadb.lua 的 SUB_NAMES 对齐）
SUB_FILE_SHA1 = 14
SUB_MEMINFO = 15
SUB_NETSTAT = 16

E_NOENT = 1
E_NOSYS = 8
ERR_NAME = {
    0: "E_OK", 1: "E_NOENT", 2: "E_DENIED", 3: "E_IO", 4: "E_BADREQ",
    5: "E_BADFD", 6: "E_TOOLONG", 7: "E_BUSY", 8: "E_NOSYS",
}


def step(title):
    """打印步骤分隔，方便对照日志看进度。"""
    print("\n===== %s =====" % title)


def fmt_size(n):
    """字节数转成人类可读，方便看分区大小。"""
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return ("%d%s" % (n, unit)) if unit == "B" else ("%.1f%s" % (n, unit))
        n /= 1024.0
    return "%dB" % n


def dump_meminfo(dev):
    """MEMINFO：9 个 u32（小端）—— sys/lua/psram 各自的 total/used/max，单位字节。"""
    errno, _flags, body = dev.request(SUB_MEMINFO, b"")
    if errno == E_NOSYS:
        print("  设备未安装 MEMINFO 指令（hzadb.mem() 没调用？）")
        return
    if errno != 0:
        print("  MEMINFO 失败：%s" % ERR_NAME.get(errno, errno))
        return
    if len(body) < 36:
        print("  MEMINFO 回应长度异常：%d 字节（期望 36）" % len(body))
        return
    vals = struct.unpack("<9I", body[:36])
    for i, name in enumerate(("sys", "lua", "psram")):
        total, used, peak = vals[i * 3:i * 3 + 3]
        print(("  %-5s 总 %-10s 已用 %-10s 峰值 %s"
               % (name, fmt_size(total), fmt_size(used), fmt_size(peak))).rstrip())


def dump_netstat(dev):
    """NETSTAT：首字节适配器数量，之后每个适配器 6 字节（u8 id + u8 flags + u32 ipv4）。"""
    errno, _flags, body = dev.request(SUB_NETSTAT, b"")
    if errno == E_NOSYS:
        print("  设备未安装 NETSTAT 指令（hzadb.netdrv() 没调用？）")
        return
    if errno != 0:
        print("  NETSTAT 失败：%s" % ERR_NAME.get(errno, errno))
        return
    if not body:
        print("  无适配器")
        return
    count = body[0]
    print("  适配器数量：%d" % count)
    for i in range(count):
        off = 1 + i * 6
        if off + 6 > len(body):
            break
        aid, flags, ip = struct.unpack("<BBI", body[off:off + 6])
        ip_str = ".".join(str(b) for b in struct.pack("<I", ip)) if ip else "未配置"
        print("    id=%-3d link=%d ready=%d napt=%d ip=%s"
              % (aid, flags & 1, (flags >> 1) & 1, (flags >> 2) & 1, ip_str))


def main():
    ap = argparse.ArgumentParser(description="hzadb 上位机演示")
    ap.add_argument("--port", required=True, help="串口号，如 COM6 或 /dev/ttyUSB0")
    ap.add_argument("--baud", type=int, default=6000000, help="日志口波特率，默认 6000000")
    ap.add_argument("--token", default="", help="设备端开启了鉴权时填同款 token")
    ap.add_argument("--dir", default="/ram", help="测试文件所在目录，默认 /ram（掉电清空，不占 flash）")
    args = ap.parse_args()

    print("打开 %s @ %d ..." % (args.port, args.baud))
    dev = None
    try:
        # 串口被占用 / 驱动没装，都会在这一步抛异常
        dev = UserCmd(args.port, baud=args.baud)

        # ---------- 1. 握手 ----------
        step("1. 握手（HELLO）")
        dev.wait_ready()
        print("  握手完成：协商写片长 %d 字节，caps=0x%04x" % (dev.chunk, dev.caps))

        # ---------- 2. 鉴权（可选）----------
        step("2. 鉴权（AUTH）")
        if args.token:
            if dev.auth(args.token):
                print("  鉴权通过")
            else:
                print("  设备未开启鉴权，跳过（token 只有在设备端 set_auth 后才需要）")
        else:
            print("  未传 --token；若设备端开启了鉴权，后续指令会回 E_DENIED")

        # ---------- 3. 挂载点与空间 ----------
        step("3. 挂载点 / 分区空间")
        mounts = dev.lsmount()
        for m in mounts:
            print("  %-14s %s" % (m["path"], m["fs"]))
        stat_root = dev.fsstat("/")
        print("  根分区：%s 总 %s / 已用 %s（块 %d）"
              % (stat_root["fs"], fmt_size(stat_root["total"]),
                 fmt_size(stat_root["used"]), stat_root["block_size"]))

        # 先确认测试目录存在，避免第 4 步写文件才报错
        try:
            dev.lsdir(args.dir)
        except UserCmdError as e:
            if e.errno != E_NOENT:
                raise
            print("\n  测试目录 %s 不存在，可用目录：" % args.dir)
            for m in mounts:
                print("    %s" % m["path"])
            print("  用 --dir 指定其中一个后重跑，例如 --dir /")
            sys.exit(2)

        # ---------- 4. 写文件 → 读回校验 ----------
        step("4. 文件读写（WRITE/READ/CLOSE）")
        path = args.dir.rstrip("/") + "/hzadb_demo.txt"
        payload = ("hzadb demo @ %s\n" % time.strftime("%Y-%m-%d %H:%M:%S")).encode() * 50
        t0 = time.time()
        written = dev.write_file(path, payload)
        cost = time.time() - t0
        print("  写入 %s：%d 字节，耗时 %.2fs（%.1f KB/s）"
              % (path, written, cost, written / 1024.0 / cost if cost > 0 else 0))

        got = dev.read_file(path)
        if got == payload:
            print("  读回 %d 字节，内容校验一致" % len(got))
        else:
            print("  读回 %d 字节，内容不一致！请检查传输稳定性" % len(got))

        # ---------- 5. 目录 / stat / exists ----------
        step("5. 列目录（LSDIR）/ STAT / EXISTS")
        entries = dev.lsdir(args.dir)
        for e in entries[:10]:
            print("  %-24s type=%d size=%d" % (e["name"], e["type"], e["size"]))
        if len(entries) > 10:
            print("  ……共 %d 项，只显示前 10 项" % len(entries))
        ftype, fsize = dev.stat(path)
        print("  stat  %s：type=%d size=%d" % (path, ftype, fsize))
        print("  exists：%s" % ("是" if dev.exists(path) else "否"))

        # ---------- 6. 设备状态 ----------
        step("6. 内存状态（MEMINFO）/ 网络状态（NETSTAT）")
        dump_meminfo(dev)
        dump_netstat(dev)

        # ---------- 7. 清理 ----------
        step("7. 删除测试文件")
        dev.remove(path)
        print("  已删除 %s（exists=%s）" % (path, "是" if dev.exists(path) else "否"))

        print("\n全部步骤执行完成。若中途出现 E_DENIED，看设备端是否开了 READ_ONLY 或鉴权。")
    except UserCmdError as e:
        print("\n设备返回错误：errno=%s(%s) %s"
              % (getattr(e, "errno", "?"),
                 ERR_NAME.get(getattr(e, "errno", -1), "?"), e))
        print("排查方向：")
        print("  E_DENIED —— 设备端 READ_ONLY=true，或开启了鉴权但没传 --token")
        print("  E_NOENT  —— 路径不存在，先用 lsdir 看目录")
        print("  E_NOSYS  —— 该指令没安装（hzadb.mem()/netdrv() 没调用）或固件太老")
        print("  超时     —— 设备端 hzadb.start() 没成功（固件未开 LUAT_USE_LOG_USER_CMD）")
        sys.exit(1)
    except Exception as e:  # 端口打不开等情况
        print("\n发生异常：%s" % e)
        sys.exit(1)
    finally:
        # 串口没打开成功时 dev 还是 None，这里不能直接调
        if dev is not None:
            dev.close_port()


if __name__ == "__main__":
    main()
