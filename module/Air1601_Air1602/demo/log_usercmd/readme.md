# 日志口用户指令 demo（协议 v2）

通过日志口扩展用户指令，由设备端 Lua 脚本实现文件系统操作，无需额外 UART。
协议 v2 具备：版本号、命令序号、滑动窗口 + 逐片确认 + 自动重传、分片大小协商（HELLO）、
open/read/write/close 文件模型、lsdir 路径+数量+偏移翻页。

- 协议文档：[PROTOCOL.md](PROTOCOL.md)
- 设备端协议栈：`log_usercmd.lua`（`uc.fs()` 一键安装标准文件系统操作集，权限由脚本控制）
- 上位机库：`host/luat_usercmd.py`（`UserCmd` 类）
- 测试脚本：`host/test_usercmd.py`

## 组成

| 文件 | 说明 |
|---|---|
| `main.lua` | 设备端 demo：加载协议栈 + 注册 fs 操作集 + 心跳日志 |
| `log_usercmd.lua` | 设备端协议栈库（帧解析/序号/去重/分发），与固件能力无关 |
| `PROTOCOL.md` | 协议文档 |
| `host/luat_usercmd.py` | 上位机 API 库（pyserial） |
| `host/test_usercmd.py` | 真机测试脚本 |

## 固件要求

下行单帧大小受固件 `am_log.c` 的 `rx_cache1/rx_cache2` 限制，经 HELLO 协商分片大小：
当前固件 `rx_cache1[512]` / `rx_cache2[1056]` → 写片长 **474B**；
旧固件（128/256）→ 写片长 90B。协议栈自动适配，加大固件缓冲即可提升吞吐。

## 使用

```bash
# 刷机(固件 + 本 demo 脚本, 注意脚本目录不要有 __pycache__)
luatos-cli flash run --soc <LuatOS-SoC_*.soc> --port COM6 --script . --tail-log-secs 8
# 看到 "demo v2 ready" 即成功

# 跑测试
python host/test_usercmd.py --port COM6
```

## 上位机 API 速览

```python
from luat_usercmd import UserCmd
dev = UserCmd("COM6")
dev.hello()                              # 握手+分片协商
dev.write_file("/abc.txt", b"..." )      # 自动分片+窗口+重传
data = dev.read_file("/abc.txt")
for e in dev.lsdir("/"):                 # 自动翻页聚合
    print(e["name"], e["type"], e["size"])
dev.mkdir("/dir"); dev.rmdir("/dir"); dev.remove("/f")
t, size = dev.stat("/abc.txt")           # 不存在抛 UserCmdError(E_NOENT)
dev.exists("/abc.txt")
```
