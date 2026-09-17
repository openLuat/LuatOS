# 日志口用户指令 demo（协议 v2）

通过日志口扩展用户指令，由设备端 Lua 脚本实现文件系统操作，无需额外 UART。
协议 v2 具备：版本号、命令序号、滑动窗口 + 逐片确认 + 自动重传、分片大小协商（HELLO）、
open/read/write/close 文件模型、lsdir 路径+数量+偏移翻页、**可选 HMAC 挑战应答鉴权（AUTH）**、
**挂载点枚举（LSMOUNT）**、**文件系统空间查询（FSSTAT）**。

v2.2 起上下行均以日志口**独占命令帧**（`cmd = SOC_CMD_USER_CMD(19)`）承载，上行帧不再混入日志流。

- 协议文档：[PROTOCOL.md](PROTOCOL.md)
- 设备端协议栈：`log_usercmd.lua`（`uc.fs()` 一键安装标准文件系统操作集，`uc.set_auth()` 开启鉴权，权限由脚本控制）
- 上位机库：`host/luat_usercmd.py`（`UserCmd` 类）
- 测试脚本：`host/test_usercmd.py`

## 组成

| 文件 | 说明 |
|---|---|
| `main.lua` | 设备端 demo：加载协议栈 + 注册 fs 操作集 + 心跳日志 + 启动打印挂载点/空间 |
| `log_usercmd.lua` | 设备端协议栈库（帧解析/序号/去重/鉴权门控/分发），与固件能力无关 |
| `PROTOCOL.md` | 协议文档 |
| `host/luat_usercmd.py` | 上位机 API 库（pyserial） |
| `host/test_usercmd.py` | 真机测试脚本 |

## 固件要求

上下行均为 A5 命令帧（`cmd = SOC_CMD_USER_CMD(19)`），上行不占用日志流；设备端由固件 C 的
`luat_log_user_cmd_write()` 发送（ccm42xx 端口映射到 `soc_cmd_response`）。

下行单帧大小受固件 `am_log.c` 的 `rx_cache1/rx_cache2` 限制，经 HELLO 协商分片大小：
当前固件 `rx_cache1[512]` / `rx_cache2[1056]` → 写片长 **476B**；
旧固件（128/256）→ 写片长 90B。协议栈自动适配，加大固件缓冲即可提升吞吐。

设备端 `io.lsmount()` / `io.fsstat()` / `crypto.hmac_sha256` 均为 LuatOS 标准库，
当前固件已内置；AUTH 需固件带 crypto（`LUAT_USE_CRYPTO`）。

## 使用

```bash
# 刷机(固件 + 本 demo 脚本, 注意脚本目录不要有 __pycache__)
luatos-cli flash run --soc <LuatOS-SoC_*.soc> --port COM6 --script . --tail-log-secs 8
# 看到 "demo v2 ready" 即成功

# 跑测试(设备未配置 token)
python host/test_usercmd.py --port COM6

# 设备端开启鉴权后(main.lua 取消 uc.set_auth 注释): 跑鉴权用例
python host/test_usercmd.py --port COM6 --auth-token 0123456789abcdef
```

## 上位机 API 速览

```python
from luat_usercmd import UserCmd
dev = UserCmd("COM6")
dev.wait_ready()                         # 等设备启动+握手+分片协商
if not dev.auth("your-token"):           # 可选: 仅设备配置 token 时需要
    print("device does not require auth")
dev.write_file("/abc.txt", b"..." )      # 自动分片+窗口+重传
data = dev.read_file("/abc.txt")
for e in dev.lsdir("/"):                 # 自动翻页聚合
    print(e["name"], e["type"], e["size"])
dev.mkdir("/dir"); dev.rmdir("/dir"); dev.remove("/f")
t, size = dev.stat("/abc.txt")           # 不存在抛 UserCmdError(E_NOENT)
dev.exists("/abc.txt")

print(dev.lsmount())                     # [{'path': '/', 'fs': 'soc'}, {'path': '/luadb/', 'fs': 'luadb'}, ...]
print(dev.fsstat("/"))                   # {'total': 196608, 'used': 20480, 'block_size': 4096, 'fs': 'soc'}
```

## 设备端鉴权配置

```lua
uc.set_auth("0123456789abcdef")  -- 8..64 字节, 生产建议 >=16 字节随机串, 须在 uc.start() 前调用
```

- HELLO 握手时设备通过 `caps` 位告知是否需要鉴权；未配置 token 的设备行为与之前完全一致
- 鉴权流程：host 用 token 对 HELLO nonce 做 HMAC-SHA256，hex 后发送；错误 mac 回应 errno=2
- HELLO 会重置鉴权状态（重握后必须重新 auth）；已知限制与威胁模型见 PROTOCOL.md §5.5/§7
