#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SIP-VoLTE 音频桥接测试 - PC模拟器 UDP控制脚本
端口: 15002

用法:
    python test_controller.py <command> [args...]

示例:
    python test_controller.py status
    python test_controller.py dial
    python test_controller.py dial 13800138000
    python test_controller.py dial_sip
    python test_controller.py answer
    python test_controller.py answer_mobile
    python test_controller.py hangup
    python test_controller.py incoming 13900139000
    python test_controller.py audio on
    python test_controller.py audio off
    python test_controller.py help
"""

import sys
import socket

def main():
    if len(sys.argv) < 2:
        show_help()
        return

    cmd_parts = sys.argv[1:]
    cmd_line = " ".join(cmd_parts)

    target_host = "127.0.0.1"
    target_port = 15002
    timeout = 2.0

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)

    try:
        sock.sendto(cmd_line.encode('utf-8'), (target_host, target_port))
        print(f"[发送] {cmd_line} -> {target_host}:{target_port}")

        try:
            data, addr = sock.recvfrom(1024)
            print(f"[回显] {data.decode('utf-8', errors='replace')}")
        except socket.timeout:
            print("[提示] 未收到回显，命令可能已发送。请查看PC模拟器窗口输出。")
    except Exception as e:
        print(f"[错误] {e}")
    finally:
        sock.close()

def show_help():
    print("""
用法: python test_controller.py <command> [args...]

可用命令:
  status              - 查看当前状态
  dial [number]       - 手动拨打手机(呼出测试)
  dial_sip [uri]      - 手动拨打 SIP 号码(呼入测试)
  answer              - 手动接听 SIP 来电
  answer_mobile       - 手动接听手机来电
  hangup              - 挂断所有通话
  incoming [number]   - 模拟手机来电(测试)
  audio [on|off]      - 打开/关闭本地音频
  help                - 显示本帮助

示例:
  python test_controller.py status
  python test_controller.py dial 13781142418
  python test_controller.py incoming 13800138000
  python test_controller.py audio off
  python test_controller.py hangup
""")

if __name__ == "__main__":
    main()
