#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LuatOS rfa com0com 端到端回归脚本
==================================

通过 com0com 虚拟串口对(COM5 ↔ COM6)向 LuatOS 模拟器发送 AT 命令,
验证 rfa AT server 响应是否与合宙 EC718 模组校准工具兼容。

使用前准备:
  1. 安装 com0com: https://sourceforge.net/projects/com0com/
  2. 配对虚拟串口:CNCA0 <-> CNCB0 (或 COM5 <-> COM6)
     setupc.exe install 5 COM6 5
  3. 安装 pyserial: pip install pyserial
  4. 启动 LuatOS AT server (用新 rfa 模块):
     cd bsp/pc/build/out
     luatos-lua.exe ../../../../testcase/common/scripts/ \\
                    ../../../../tools/rfa_com0com/at_server_main/

使用:
  python test_rfa_com0com.py [--port COM5] [--baud 115200] [--suite basic|full]

退出码:
  0 = 全部通过
  1 = 有 case 失败
  2 = 环境错误(com0com 未配 / 串口忙 / pyserial 未装)
"""

import argparse
import sys
import time

try:
    import serial  # pyserial
except ImportError:
    print("[FATAL] pyserial 未安装,请运行: pip install pyserial", file=sys.stderr)
    sys.exit(2)


# 基础套件:对应 7 段校准流程的关键命令
# 真实校准日志 (F:\hardware\calrf\864317081553409_UartComm_Log_Port14.txt) 的顺序:
#   AT / ATE0 / AT+CPIN? / AT+CFUN=0 / AT+ECCHIPVER? / AT+ECGMDATA? / AT+CGSN=1
#   / AT+ECNPICFG=rfCaliDone,0 / AT+ECRFNST=... (校准在此飞行模式下跑)
#   / AT+ECNPICFG=rfCaliDone,1 / AT+ECNPICFG?
BASIC_CASES = [
    # (发送, 期望包含的响应片段, 描述)
    (b"AT\r\n",                              b"OK",                "AT 握手"),
    (b"ATE0\r\n",                            b"OK",                "关回显"),
    (b"AT+CPIN?\r\n",                        b"CME ERROR",         "无 SIM,工具忽略"),
    (b"AT+CFUN=0\r\n",                       b"OK",                "关射频 (校准前硬前置)"),
    (b"AT+CFUN=1\r\n",                       b"OK",                "开射频 (退出飞行模式)"),
    (b"AT+ECCHIPVER?\r\n",                   b"ERROR",             "未实现,工具忽略"),
    (b"AT+ECGMDATA?\r\n",                    b"OK",                "空操作"),
    (b"AT+CGSN=1\r\n",                       b"864317081553409",   "读 IMEI (默认)"),
    (b"AT+ECNPICFG=rfCaliDone,0\r\n",        b"OK",                "清校准标志"),
    (b"AT+ECNPICFG=rfCaliDone,1\r\n",        b"OK",                "置校准完成"),
    (b"AT+ECNPICFG?\r\n",                    b"rfCaliDone",        "回读 NPI 配置"),
    (b"AT+ECNPICFG=rfNSTDone,1\r\n",         b"OK",                "置 NST 完成"),
]

# 完整套件:在 BASIC 基础上加 RFNST 私有协议 (校准就是要在 CFUN=0 之后跑)
FULL_CASES = [
    (b"AT\r\n",                              b"OK",                "AT 握手"),
    (b"ATE0\r\n",                            b"OK",                "关回显"),
    (b"AT+CFUN=0\r\n",                       b"OK",                "关射频 (校准前硬前置)"),
    (b"AT+ECNPICFG=rfCaliDone,0\r\n",        b"OK",                "清校准标志"),
    (b"AT+CGSN=1\r\n",                       b"864317081553409",   "读 IMEI (默认)"),
    (b"AT+ECRFNST=02040800000000000000000000000000\r\n",
     b"MT0204",                              "RFNST cmdId=0x04 (飞行模式下跑)"),
    (b"AT+ECRFNST=02030000000000000000000000000000\r\n",
     b"MT0203",                              "RFNST cmdId=0x03 (飞行模式下跑)"),
    (b"AT+CFUN=1\r\n",                       b"OK",                "退出飞行模式"),
    (b"AT+ECNPICFG=rfCaliDone,1\r\n",        b"OK",                "置校准完成"),
    (b"AT+ECNPICFG?\r\n",                    b"rfCaliDone",        "回读 NPI 配置"),
    (b"AT+BOGUS\r\n",                        b"ERROR",             "未知命令应返 ERROR"),
]


def run_case(ser, tx, expect, desc, timeout=2.0):
    """发送一条 AT 命令,验证响应包含 expect 片段。返回 (passed, response_text)"""
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    ser.write(tx)
    # 真实 AT 响应通常 < 200ms,给一点裕量
    time.sleep(0.05)
    deadline = time.time() + timeout
    chunks = []
    while time.time() < deadline:
        n = ser.in_waiting
        if n > 0:
            chunks.append(ser.read(n))
            # 若已含 OK 或 ERROR 可提前结束
            joined = b"".join(chunks)
            if b"OK" in joined or b"ERROR" in joined:
                # 多读 50ms 收尾
                time.sleep(0.05)
                rest = ser.read(ser.in_waiting or 1)
                if rest:
                    chunks.append(rest)
                break
        else:
            time.sleep(0.02)
    rx = b"".join(chunks)
    try:
        rx_text = rx.decode(errors="replace")
    except Exception:
        rx_text = repr(rx)
    passed = expect in rx
    tag = "PASS" if passed else "FAIL"
    print(f"  [{tag}] {desc}")
    print(f"        TX: {tx!r}")
    print(f"        RX: {rx_text!r}")
    if not passed:
        print(f"        期望包含: {expect!r}")
    return passed, rx_text


def run_suite(port, baud, cases):
    print(f"打开串口: {port} @ {baud} 8N1 ...")
    try:
        ser = serial.Serial(port, baud, timeout=0.5, bytesize=8,
                            parity="N", stopbits=1)
    except serial.SerialException as e:
        print(f"[FATAL] 无法打开 {port}: {e}", file=sys.stderr)
        print("  检查 com0com 是否已配对该端口,或端口被其他程序占用",
              file=sys.stderr)
        return 2

    passed = 0
    failed = 0
    try:
        print(f"运行 {len(cases)} 个 case:")
        for tx, expect, desc in cases:
            ok, _ = run_case(ser, tx, expect, desc)
            if ok:
                passed += 1
            else:
                failed += 1
    finally:
        ser.close()

    print()
    print(f"=== 结果: {passed} 通过, {failed} 失败 ===")
    return 0 if failed == 0 else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", default="COM5",
                        help="com0com 客户端端口(默认 COM5)")
    parser.add_argument("--baud", type=int, default=115200,
                        help="波特率(默认 115200)")
    parser.add_argument("--suite", choices=["basic", "full"], default="basic",
                        help="测试套件:basic(8)=关键流程, full(11)=含 RFNST + ERROR 路径")
    args = parser.parse_args()

    cases = BASIC_CASES if args.suite == "basic" else FULL_CASES
    print(f"LuatOS rfa com0com 回归 - {args.suite} 套件 ({len(cases)} cases)")
    print(f"  Port={args.port} Baud={args.baud}")
    print()
    return run_suite(args.port, args.baud, cases)


if __name__ == "__main__":
    sys.exit(main())
