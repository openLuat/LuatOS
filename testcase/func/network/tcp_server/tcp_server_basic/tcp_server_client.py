#!/usr/bin/env python3
"""
TCP Server 外部测试客户端
用于验证 LuatOS PC 模拟器的 TCP Server 功能

用法:
    python tcp_server_client.py [port]

默认连接 127.0.0.1:18766, 发送 "PING", 等待 "PONG" 响应
"""
import socket
import sys
import time

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18766
    host = "127.0.0.1"

    print(f"Connecting to {host}:{port} ...")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect((host, port))
        print("Connected!")

        # Send PING
        s.sendall(b"PING")
        print("Sent: PING")

        # Wait for PONG
        data = s.recv(1024)
        print(f"Received: {data.decode('utf-8', errors='replace')}")

        s.close()

        if data == b"PONG":
            print("TEST PASSED")
            return 0
        else:
            print(f"TEST FAILED: expected PONG, got {data}")
            return 1
    except Exception as e:
        print(f"TEST FAILED: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
