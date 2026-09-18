# -*- coding: utf-8 -*-
"""固件侧日志口 RX/TX 可靠性 A/B 度量

配套设计文档 2026-09-17-soc-log-rx-tx-fix-design.md(SDK 仓库)。三个缺陷各一条用例,
主指标是"WRITE_DATA 重传帧数" —— 每丢一帧要等一个 data_timeout, 重传次数直接反映链路是否完整。

  A  ISR 抽帧/解包缓冲边界: 满档 chunk=1024 -> 线上帧最坏 ~2112B(随机内容 ~1070B),
     厂商新固件 rx_cache1[1064] + 一次中断内循环抽干, 应零重传
     (旧固件对应缺陷: chunk=476 -> 线上帧 ~518B > 512B 抽帧缓冲, 尾字节留在 16B 硬件 FIFO)
  B  dev_rx_buffer 的 ISR/任务竞态(历史描述): 该竞态已被证实在 write_window=1 下不可达并归档。
     用例保留为"累计重传"的常规健康指标(多轮小文件写, 偶发丢帧会体现为重传), 
     但**不要用 --expect before 断言它复现**, 也不要为此去改它。
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


def retrans_count(dev, fn):
    """执行 fn, 返回期间的 WRITE_DATA 重传帧数

    _write_window 重传时复用同一 seq, 所以"seq 已经出现过"就是一次重传。
    直接数重传, 而不是算"实发帧数 - 估算帧数": 后者要假设片长等于 chunk, 但 wire_budget
    会让片长按内容收缩(实测 chunk=476 时收缩到 ~465), 会算出与实际无关的假重传。
    """
    seen = set()
    dup = [0]
    real = dev._send

    def hook(subcmd, body, seq):
        if subcmd == SUB_WRITE:
            if seq in seen:
                dup[0] += 1
            else:
                seen.add(seq)
        return real(subcmd, body, seq)

    dev._send = hook
    try:
        fn()
    finally:
        dev._send = real
    return dup[0]


def _drop(dev, path):
    """尽力清理设备上的临时文件, 不影响主流程判定"""
    try:
        dev.remove(path)
    except Exception:
        pass


def case_a(dev, size=65536):
    """满档 chunk=1024(线上最坏 ~2112B) 写 64K: 把 wire_budget 抬高以关掉上位机的内容自适应收缩"""
    path = "/ram/ab_a.bin"
    try:
        dev.propose_chunk = 2048   # 让设备报出真实上界(新固件 1024)
        dev.hello()
        dev.wire_budget = 4096
        data = bytes(random.randrange(256) for _ in range(size))
        t0 = time.perf_counter()
        retrans = retrans_count(dev, lambda: dev.write_file(path, data))
        dt = time.perf_counter() - t0
        ok = dev.read_file(path) == data
        return retrans, dt, ok
    finally:
        _drop(dev, path)


def case_b(dev, rounds=10, size=16384):
    """多轮小文件写(默认参数 = 修复后应有的正确行为), 累计重传"""
    path = "/ram/ab_b.bin"
    try:
        dev.wire_budget = 508
        dev.propose_chunk = 2048   # 让设备报出真实上界(新固件 1024)
        dev.hello()
        total, dt, ok = 0, 0.0, True
        for _ in range(rounds):
            data = bytes(random.randrange(256) for _ in range(size))
            t0 = time.perf_counter()
            total += retrans_count(dev, lambda: dev.write_file(path, data))
            dt += time.perf_counter() - t0
            ok = ok and (dev.read_file(path) == data)
        return total, dt, ok
    finally:
        _drop(dev, path)


def case_c(dev, size=131072, big_chunk=32768):
    """超大响应必须"要么读全、要么显式报错", 绝不能静默返回残缺内容

    厂商新固件(2026-09-18 起)命令响应走 16KB 专用 response_fifo, 不再受 1600B log record
    截断; 但 32768B 的响应仍远超 fifo, 主机侧靠 _read_window 的 rlen 校验 + read_file 的
    stat 校验把任何截断变成显式错误。
    返回 (kind, 错误文本, 耗时, 内容是否一致), kind ∈ {"ok","truncated","timeout","other"}。
    """
    path = "/ram/ab_c.bin"
    kind, err, got = "ok", None, None
    try:
        dev.read_chunk = 4096
        data = bytes(random.randrange(256) for _ in range(size))
        dev.write_file(path, data)
        dev.read_chunk = big_chunk
        t0 = time.perf_counter()
        try:
            got = dev.read_file(path)
        except UserCmdError as e:
            err = str(e)
            if "timeout" in err:
                kind = "timeout"
            elif "截断" in err or "stat 为" in err:
                kind = "truncated"
            else:
                kind = "other"
        dt = time.perf_counter() - t0
        return kind, err, dt, (got == data)
    finally:
        dev.read_chunk = 4096
        _drop(dev, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM6")
    ap.add_argument("--expect", choices=("before", "after"), required=True)
    args = ap.parse_args()

    random.seed(20260917)
    dev = UserCmd(args.port)
    fails = []
    try:
        print("hello ->", dev.wait_ready())

        ra, ta, oa = case_a(dev)
        print(f"A chunk=1024(线上最坏~2112B) 64K 写: 重传 {ra} 次, {ta * 1000:.0f}ms, 内容一致={oa}")
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
        # B 是偶发竞态, before 模式不作断言 —— 它能到 0 也可能到 0, 单独看没有信息量;
        # 需要能说明问题的信号时, 用 /tmp/uc_stress(2ms 心跳)刷机后再跑本脚本(见计划 Task 4)
        if args.expect == "after" and rb != 0:
            fails.append(f"B 修复后重传应为 0, 实际 {rb}")

        kc, ec, tc, oc = case_c(dev)
        print(f"C 超大响应(read_chunk=32768) 读 128K: {kc}"
              + (f" ({ec})" if ec else "") + f", {tc * 1000:.0f}ms, 内容一致={oc}")
        # 允许: ok(读全) / truncated(显式报错) / timeout(老固件行为)。
        # 绝不允许的是"看起来读全了但内容不对" —— 那就是静默数据损坏。
        if kc == "ok" and not oc:
            fails.append("C 回归成了静默损坏: 返回成功但内容不一致")
        elif kc == "other":
            fails.append(f"C 报了预期之外的错误: {ec}")
    finally:
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
