# -*- coding: utf-8 -*-
"""
日志口用户指令协议 v2 上位机测试脚本
配合 demo/log_usercmd/main.lua 使用, 协议见 PROTOCOL.md

测试项:
  hello分片协商 / 4K写读校验 / 64K大文件(窗口+重传) / lsdir翻页 /
  mkdir/rmdir / remove / stat / exists / 错误路径

依赖: pyserial   (pip install pyserial)
"""
import argparse
import sys
import time

from luat_usercmd import (UserCmd, UserCmdError, E_NOENT, E_BADFD)

DATA4K = bytes([(i * 7 + 3) & 0xFF for i in range(4096)])
DATA64K = bytes([(i * 131 + 17) & 0xFF for i in range(64 * 1024)])

results = []


def check(name: str, ok: bool, detail: str = ""):
    results.append((name, ok))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" -- {detail}" if detail else ""))


def expect_errno(name, fn, errno):
    try:
        fn()
    except UserCmdError as e:
        check(name, e.errno == errno, f"errno={e.errno}")
        return
    check(name, False, "no error raised")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM6")
    ap.add_argument("--baud", type=int, default=6000000)
    args = ap.parse_args()

    dev = UserCmd(args.port, args.baud)
    print(f"open {args.port} @ {args.baud}")
    try:
        # 1. 等设备启动完成 + 握手 + 分片协商 (新固件 rx 512/1056 -> 474)
        t0 = time.time()
        chunk = dev.wait_ready()
        dt = time.time() - t0
        fw_ok = chunk == 474
        check("hello.chunk", fw_ok,
              f"chunk={chunk} (期望474, 若=90说明固件未更新)" if not fw_ok else f"chunk={chunk}, ready {dt:.1f}s")

        # 2. 4K 写读校验
        t0 = time.time()
        size = dev.write_file("/abc.txt", DATA4K)
        dt = time.time() - t0
        check("write.4k", size == len(DATA4K), f"{size}B {dt:.2f}s {len(DATA4K)/dt/1024:.0f}KB/s")
        t0 = time.time()
        data = dev.read_file("/abc.txt")
        dt = time.time() - t0
        check("read.4k", data == DATA4K, f"{len(data)}B {dt:.2f}s {len(data)/dt/1024:.0f}KB/s")

        # 3. 64K 大文件(滑动窗口压测, 期间有心跳日志共存)
        t0 = time.time()
        size = dev.write_file("/big.bin", DATA64K)
        dt = time.time() - t0
        check("write.64k", size == len(DATA64K), f"{size}B {dt:.2f}s {len(DATA64K)/dt/1024:.0f}KB/s")
        t0 = time.time()
        data = dev.read_file("/big.bin")
        dt = time.time() - t0
        check("read.64k", data == DATA64K, f"{len(data)}B {dt:.2f}s {len(data)/dt/1024:.0f}KB/s")

        # 4. lsdir 翻页: /ucpage 下放 25 个文件, 用 page_size=10 强制 3 页
        if dev.exists("/ucpage"):   # 上次中断的残留清理
            for e in dev.lsdir("/ucpage"):
                dev.remove("/ucpage/" + e["name"])
            dev.rmdir("/ucpage")
        dev.mkdir("/ucpage")
        for i in range(25):
            dev.write_file(f"/ucpage/f{i:02d}.txt", b"x" * i)
        names = {e["name"] for e in dev.lsdir("/ucpage", page_size=10)}
        check("lsdir.paged", len(names) == 25, f"{len(names)}/25 entries")
        root_names = {e["name"] for e in dev.lsdir("/")}
        check("lsdir.root", "abc.txt" in root_names, ",".join(sorted(root_names)))

        # 5. mkdir/rmdir
        dev.mkdir("/uctest")
        root_names = {e["name"] for e in dev.lsdir("/")}
        check("mkdir.verify", "uctest" in root_names)
        dev.rmdir("/uctest")
        root_names = {e["name"] for e in dev.lsdir("/")}
        check("rmdir.verify", "uctest" not in root_names)

        # 6. remove
        dev.remove("/ucpage/f00.txt")
        check("remove.verify", not dev.exists("/ucpage/f00.txt"))
        names = {e["name"] for e in dev.lsdir("/ucpage", page_size=100)}
        check("remove.lsdir", len(names) == 24, f"{len(names)}/24 entries")

        # 7. stat
        t, sz = dev.stat("/abc.txt")
        check("stat.file", t == 0 and sz == len(DATA4K), f"type={t} size={sz}")
        t, _sz = dev.stat("/ucpage")
        check("stat.dir", t == 1, f"type={t}")
        expect_errno("stat.missing", lambda: dev.stat("/no_such"), E_NOENT)

        # 8. exists
        check("exists.yes", dev.exists("/abc.txt"))
        check("exists.no", not dev.exists("/no_such"))

        # 9. 错误路径
        expect_errno("open.missing", lambda: dev.open("/no_such", "r"), E_NOENT)
        expect_errno("read.missing", lambda: dev.read_file("/no_such"), E_NOENT)
        expect_errno("close.badfd", lambda: dev.close(99), E_BADFD)

        # 10. 追加模式(host 侧经 stat 定位尾部, 设备 r+ 随机写)
        if dev.exists("/append.txt"):
            dev.remove("/append.txt")
        dev.write_file("/append.txt", b"hello ")
        dev.write_file("/append.txt", b"world", append=True)
        data = dev.read_file("/append.txt")
        check("append", data == b"hello world", repr(data))

        # 清理
        for i in range(1, 25):
            dev.remove(f"/ucpage/f{i:02d}.txt")
        dev.rmdir("/ucpage")
        dev.remove("/big.bin")
    finally:
        dev.close_port()
    print("=" * 40)
    for name, ok in results:
        print(f"  [{'x' if ok else ' '}] {name}")
    passed = sum(1 for _, ok in results if ok)
    print(f"total: {passed}/{len(results)} passed")
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
