"""Air8801 串口回传上位机：收到什么，原样发回。

配合「功能测试 → TTL 串口 / RS232 串口 → 发 3 字节」使用。
设备先发 3 个字节 A8K，本脚本把它原样回传，设备 10 s 内收到 A8K 即判通过。
也可以不用本脚本，直接在串口助手里手敲发送 A8K（同样 9600 8N1）。

用法：
    pip install pyserial
    python serial_echo.py COM5                 # 9600 8N1
    python serial_echo.py COM5 --baud 9600     # 显式指定波特率
    python serial_echo.py COM5 --hex           # 按十六进制打印收到的字节

按 Ctrl+C 退出。任何普通串口助手的「收到即回发 / 自动应答」都可以替代本脚本。
"""

import argparse
import sys

try:
    import serial
except ImportError:
    sys.exit("缺少 pyserial，先执行：pip install pyserial")


def main():
    ap = argparse.ArgumentParser(description="串口回传（收到即回发）")
    ap.add_argument("port", help="串口号，例如 COM5")
    ap.add_argument("--baud", type=int, default=9600, help="波特率，默认 9600")
    ap.add_argument("--hex", action="store_true", help="按十六进制打印收到的字节")
    args = ap.parse_args()

    with serial.Serial(args.port, args.baud, bytesize=8, parity="N",
                       stopbits=1, timeout=0.2) as sp:
        sp.reset_input_buffer()
        print(f"回传已启动：{args.port} {args.baud} 8N1    Ctrl+C 退出")
        total = 0
        while True:
            data = sp.read(256)
            if not data:
                continue
            sp.write(data)
            sp.flush()
            total += len(data)
            shown = data.hex(" ") if args.hex else repr(data[:40])
            tail = "" if len(data) <= 40 else f" ...（共 {len(data)} 字节）"
            print(f"< {len(data):3d} 字节  {shown}{tail}    累计 {total}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n已退出")
    except serial.SerialException as exc:
        sys.exit(f"串口打不开：{exc}")
