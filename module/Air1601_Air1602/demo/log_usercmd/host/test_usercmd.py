# -*- coding: utf-8 -*-
"""
日志口用户指令协议 v2 上位机测试脚本
配合 demo/log_usercmd/main.lua 使用, 协议见 PROTOCOL.md

测试项:
  hello分片协商 / 4K写读校验 / 64K大文件(窗口+重传) / lsdir翻页 /
  mkdir/rmdir / remove / stat / exists / 错误路径 / 追加写 /
  lsmount / fsstat / auth(可选, --auth-token 模式) / nosys

依赖: pyserial   (pip install pyserial)

用法:
  python test_usercmd.py --port COM6                    # 设备未配置 token
  python test_usercmd.py --port COM6 --auth-token XXX   # 设备已配置同款 token
"""
import argparse
import sys
import time

from luat_usercmd import (UserCmd, UserCmdError, E_NOENT, E_BADFD, E_DENIED, E_NOSYS)

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
    ap.add_argument("--auth-token", default=None,
                    help="设备端 main.lua 配置的鉴权 token; 设置后先跑门控/失败/成功鉴权用例")
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

        # 2. 鉴权: caps 协商 + 门控 + HMAC 应答 (可选)
        if args.auth_token:
            check("auth.caps", bool(dev.caps & 1), f"caps={dev.caps:#x} (期望bit0=1)")
            expect_errno("auth.gate", lambda: dev.exists("/abc.txt"), E_DENIED)
            expect_errno("auth.wrong", lambda: dev.auth("wrong-token-0123"), E_DENIED)
            check("auth.ok", dev.auth(args.auth_token))
        else:
            check("auth.caps_off", not (dev.caps & 1), f"caps={dev.caps:#x} (期望0)")
            check("auth.noop", dev.auth("not-needed-token-0") is False)

        # 3. lsmount / fsstat
        mounts = dev.lsmount()
        fs_types = {m["fs"] for m in mounts}
        paths = {m["path"] for m in mounts}
        check("lsmount", len(mounts) >= 2 and "soc" in fs_types and "/" in paths,
              ",".join(f"{m['path']}:{m['fs']}" for m in mounts))
        st = dev.fsstat("/")
        check("fsstat.root",
              st["total"] > 0 and st["block_size"] > 0 and st["used"] <= st["total"] and st["fs"] == "soc",
              f"{st['fs']} total={st['total']} used={st['used']} bs={st['block_size']}")
        st = dev.fsstat("/luadb/")
        check("fsstat.luadb", st["fs"] == "luadb", f"{st['fs']} total={st['total']} used={st['used']}")
        # 根挂载兜底: 未匹配路径返回根分区信息(ccm42xx 挂载 "" 捕获所有路径), 不应报错
        st = dev.fsstat("/nope/")
        check("fsstat.fallback", st["fs"] == "soc", f"fallback fs={st['fs']}")
        st = dev.fsstat("/ram/")
        check("fsstat.ram", st["fs"] == "ram" and st["block_size"] > 0, f"{st['fs']} bs={st['block_size']}")
        errno, _f, _b = dev.request(200, b"")
        check("nosys.unknown", errno == E_NOSYS, f"errno={errno}")

        # 4. 4K 写读校验
        t0 = time.time()
        size = dev.write_file("/abc.txt", DATA4K)
        dt = time.time() - t0
        check("write.4k", size == len(DATA4K), f"{size}B {dt:.2f}s {len(DATA4K)/dt/1024:.0f}KB/s")
        t0 = time.time()
        data = dev.read_file("/abc.txt")
        dt = time.time() - t0
        check("read.4k", data == DATA4K, f"{len(data)}B {dt:.2f}s {len(data)/dt/1024:.0f}KB/s")

        # 5. 64K 大文件(滑动窗口压测, 期间有心跳日志共存)
        t0 = time.time()
        size = dev.write_file("/big.bin", DATA64K)
        dt = time.time() - t0
        check("write.64k", size == len(DATA64K), f"{size}B {dt:.2f}s {len(DATA64K)/dt/1024:.0f}KB/s")
        t0 = time.time()
        data = dev.read_file("/big.bin")
        dt = time.time() - t0
        check("read.64k", data == DATA64K, f"{len(data)}B {dt:.2f}s {len(data)/dt/1024:.0f}KB/s")

        # 6. lsdir 翻页: /ucpage 下放 25 个文件, 用 page_size=10 强制 3 页
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

        # 7. mkdir/rmdir
        dev.mkdir("/uctest")
        root_names = {e["name"] for e in dev.lsdir("/")}
        check("mkdir.verify", "uctest" in root_names)
        dev.rmdir("/uctest")
        root_names = {e["name"] for e in dev.lsdir("/")}
        check("rmdir.verify", "uctest" not in root_names)

        # 8. remove
        dev.remove("/ucpage/f00.txt")
        check("remove.verify", not dev.exists("/ucpage/f00.txt"))
        names = {e["name"] for e in dev.lsdir("/ucpage", page_size=100)}
        check("remove.lsdir", len(names) == 24, f"{len(names)}/24 entries")

        # 9. stat
        t, sz = dev.stat("/abc.txt")
        check("stat.file", t == 0 and sz == len(DATA4K), f"type={t} size={sz}")
        t, _sz = dev.stat("/ucpage")
        check("stat.dir", t == 1, f"type={t}")
        expect_errno("stat.missing", lambda: dev.stat("/no_such"), E_NOENT)

        # 10. exists
        check("exists.yes", dev.exists("/abc.txt"))
        check("exists.no", not dev.exists("/no_such"))

        # 11. 错误路径
        expect_errno("open.missing", lambda: dev.open("/no_such", "r"), E_NOENT)
        expect_errno("read.missing", lambda: dev.read_file("/no_such"), E_NOENT)
        expect_errno("close.badfd", lambda: dev.close(99), E_BADFD)

        # 12. 追加模式(host 侧经 stat 定位尾部, 设备 r+ 随机写)
        if dev.exists("/append.txt"):
            dev.remove("/append.txt")
        dev.write_file("/append.txt", b"hello ")
        dev.write_file("/append.txt", b"world", append=True)
        data = dev.read_file("/append.txt")
        check("append", data == b"hello world", repr(data))

        # 13. HELLO 重置鉴权态(仅鉴权模式): 重握后业务指令再次被拒绝, 须重新鉴权
        if args.auth_token:
            dev.hello()
            expect_errno("auth.reset_by_hello", lambda: dev.exists("/abc.txt"), E_DENIED)
            check("auth.reauth", dev.auth(args.auth_token))

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
