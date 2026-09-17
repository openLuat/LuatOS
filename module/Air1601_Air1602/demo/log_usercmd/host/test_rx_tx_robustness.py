# -*- coding: utf-8 -*-
"""固件侧日志口 RX/TX 可靠性 A/B 度量

配套设计文档 2026-09-17-soc-log-rx-tx-fix-design.md(SDK 仓库)。三个缺陷各一条用例,
主指标是"WRITE_DATA 重传帧数" —— 每丢一帧要等一个 data_timeout, 重传次数直接反映链路是否完整。

  A  ISR 抽帧不完整: chunk=476 -> 线上帧 ~518B > 512B 抽帧缓冲, 尾字节留在 16B 硬件 FIFO
  B  dev_rx_buffer 的 ISR/任务竞态: 多轮小文件写, 累计重传(偶发, 所以只作参考)
  C  soc_cmd_response 余量不足静默丢弃: read_chunk=32768 -> 响应 32780B

--expect before : 断言"缺陷存在"(用于确认用例真能复现)
--expect after  : 断言"缺陷已修"

用法:
  python test_rx_tx_robustness.py --port COM6 --expect before
  python test_rx_tx_robustness.py --port COM6 --expect after
"""
import argparse
import random
import sys
import time

from luat_usercmd import SUB_WRITE, UserCmd, UserCmdError


def send_count(dev, fn):
    """执行 fn, 返回期间发出的 WRITE_DATA 帧数(含重传)"""
    n = [0]
    real = dev._send

    def hook(subcmd, body, seq):
        if subcmd == SUB_WRITE:
            n[0] += 1
        return real(subcmd, body, seq)

    dev._send = hook
    try:
        fn()
    finally:
        dev._send = real
    return n[0]


def case_a(dev, size=65536):
    """chunk=476(线上 ~518B) 写 64K: 把 wire_budget 抬高以关掉上位机的内容自适应收缩"""
    dev.propose_chunk = 512
    dev.hello()
    dev.wire_budget = 4096
    data = bytes(random.randrange(256) for _ in range(size))
    expect = (size + dev.chunk - 1) // dev.chunk
    t0 = time.perf_counter()
    sent = send_count(dev, lambda: dev.write_file("/ram/ab_a.bin", data))
    dt = time.perf_counter() - t0
    ok = dev.read_file("/ram/ab_a.bin") == data
    dev.remove("/ram/ab_a.bin")
    return sent - expect, dt, ok


def case_b(dev, rounds=10, size=16384):
    """多轮小文件写(默认参数 = 修复后应有的正确行为), 累计重传"""
    dev.wire_budget = 508
    dev.propose_chunk = 512
    dev.hello()
    total, dt, ok = 0, 0.0, True
    for _ in range(rounds):
        data = bytes(random.randrange(256) for _ in range(size))
        expect = (size + dev.chunk - 1) // dev.chunk
        t0 = time.perf_counter()
        total += send_count(dev, lambda: dev.write_file("/ram/ab_b.bin", data)) - expect
        dt += time.perf_counter() - t0
        ok = ok and (dev.read_file("/ram/ab_b.bin") == data)
    dev.remove("/ram/ab_b.bin")
    return total, dt, ok


def case_c(dev, size=131072):
    """read_chunk=32768: 响应 32780B, 命中 soc_cmd_response 的"余量不足静默丢弃"分支"""
    dev.read_chunk = 4096
    data = bytes(random.randrange(256) for _ in range(size))
    dev.write_file("/ram/ab_c.bin", data)
    dev.read_chunk = 32768
    t0 = time.perf_counter()
    try:
        got, err = dev.read_file("/ram/ab_c.bin"), None
    except UserCmdError as e:
        got, err = None, str(e)
    dt = time.perf_counter() - t0
    dev.remove("/ram/ab_c.bin")
    return err, dt, (got == data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM6")
    ap.add_argument("--expect", choices=("before", "after"), required=True)
    args = ap.parse_args()

    random.seed(20260917)
    dev = UserCmd(args.port)
    print("hello ->", dev.wait_ready())
    fails = []

    ra, ta, oa = case_a(dev)
    print(f"A chunk=476(线上~518B) 64K 写: 重传 {ra} 次, {ta * 1000:.0f}ms, 内容一致={oa}")
    if args.expect == "before":
        if ra < 3:
            fails.append(f"A 应能复现丢帧(重传>=3), 实际 {ra}")
    elif ra != 0:
        fails.append(f"A 修复后重传应为 0, 实际 {ra}")
    if not oa:
        fails.append("A 内容不一致")

    rb, tb, ob = case_b(dev)
    print(f"B 10x16K 写(默认参数): 累计重传 {rb} 次, {tb * 1000:.0f}ms, 内容一致={ob}")
    if not ob:
        fails.append("B 内容不一致")
    if args.expect == "after" and rb != 0:
        fails.append(f"B 修复后重传应为 0, 实际 {rb}")

    ec, tc, oc = case_c(dev)
    print(f"C read_chunk=32768 读 128K: {ec or 'OK'}, {tc * 1000:.0f}ms, 内容一致={oc}")
    if args.expect == "before":
        if ec is None:
            fails.append("C 应能复现静默丢弃(超时), 实际成功")
    elif ec is not None:
        fails.append(f"C 修复后应正常返回, 实际 {ec}")
    elif not oc:
        fails.append("C 内容不一致")

    dev.close_port()
    print("=" * 50)
    if fails:
        for f in fails:
            print("  [x] " + f)
        print(f"结果: FAIL ({len(fails)} 项)")
        sys.exit(1)
    print(f"结果: PASS (--expect {args.expect} 的期望全部满足)")


if __name__ == "__main__":
    main()
