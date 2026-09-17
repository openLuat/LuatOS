# 日志口用户指令 demo（协议 v2）

通过日志口扩展用户指令，由设备端 Lua 脚本实现文件系统操作，无需额外 UART。
协议 v2 具备：版本号、命令序号、滑动窗口 + 逐片确认 + 自动重传、分片大小协商（HELLO）、
open/read/write/close 文件模型、lsdir 路径+数量+偏移翻页、**可选 HMAC 挑战应答鉴权（AUTH）**、
**挂载点枚举（LSMOUNT）**、**文件系统空间查询（FSSTAT）**。

V2.2 起上下行均以日志口**独占命令帧**（`cmd = SOC_CMD_USER_CMD(19)`）承载，上行帧不再混入日志流。

## 上位机默认参数（都是实测调出来的，改动前请先看 PROTOCOL.md §5.3/§6）

| 参数 | 默认 | 为什么 |
|---|---|---|
| 读窗口 `window` | 1 | 实测比 W=8 快一倍（235 vs 110KB/s）|
| 写窗口 `write_window` | 1 | 连发会丢帧并形成重传活锁 |
| 数据片超时 `data_timeout` | 200ms | 正常往返仅 2.4ms(/ram/)，500ms 会把每次丢帧放大 200 倍 |
| `wire_budget` | 508B | 单帧线上长上限：设备 ISR 抽帧缓冲只有 512B，超了就丢帧 |
| `read_chunk` | 4096B | 512→240KB/s，4096→389KB/s；设备端上限 32732B（超过会被静默丢弃）|

`write_file` 按**实际内容的转义长度**逐片求解最大片长：随机内容取满 ~470B（199KB/s），
内容全是 0xA5 时自动收缩到 ~240B（仍不超限）。所以 chunk 不需要手工调。

2026-09-17 固件侧修复后（`soc_rx` 循环抽干 + 大响应回退直发），
上位机不再需要为设备缺陷让步：`wire_budget` 可放到 4096 而仍零重传，
`read_chunk` 也不再受 32732 限制。
（原计划的"解析侧临界区"经实测定性后放弃，未合入——见设计文档 §4.2。）

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

实测设备端下行 RX 只吞得下约 **4 个连发帧**（每帧线上 ~518B），连发 8 帧会稳定丢帧。
因此上位机**写窗口默认 W=1、读窗口 W=8**（下行只有十几字节请求的读方向不受影响）。
加大固件 RX 抽取缓冲/深度后才谈得上开大写窗口。

## 文件系统兼容性

`uc.fs()` 安装的操作集不假设文件系统支持随机写，具体差异：

| 挂载点 | fs | 写语义 |
|---|---|---|
| `/` | soc (littlefs) | 支持带 offset 的随机写，空洞自动补零；单次 ≥256B 的写有 ~50ms page program 停顿 |
| `/ram/` | ram | **顺序写**，不支持写未分配区域（`f:seek("set", offset)` 越界被忽略、数据落到 EOF） |

对顺序写文件系统，`log_usercmd.lua` 的 write 处理函数在 `offset > 当前文件大小` 时**先补零到 offset 再写**，
使窗口写的重传/乱序到达保持幂等（补零上限 64KiB，超出回应 errno=4），并在写后回读大小确认落盘。
此前"直接 seek + 写"在 `/ram/` 上会静默把数据追加到 EOF，使 W≥2 的大文件写入错位、尾部丢失，且协议层无感知。
上位机侧对应加了两道校验：WRITE_DATA 回显 offset 必须与请求一致，CLOSE 返回的最终大小必须等于预期长度。
详见 PROTOCOL.md §3 / §5.3 / §6。

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
