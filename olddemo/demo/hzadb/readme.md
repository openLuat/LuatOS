# 日志口用户指令 demo（协议 v2）

通过日志口扩展用户指令，由设备端 Lua 脚本实现文件系统操作，无需额外 UART。
协议 v2 具备：版本号、命令序号、滑动窗口 + 逐片确认 + 自动重传、分片大小协商（HELLO）、
open/read/write/close 文件模型、lsdir 路径+数量+偏移翻页、**可选 HMAC 挑战应答鉴权（AUTH）**、
**挂载点枚举（LSMOUNT）**、**文件系统空间查询（FSSTAT）**。

V2.2 起上下行均以日志口**独占命令帧**（`cmd = SOC_CMD_USER_CMD(20)`）承载，上行帧不再混入日志流。

## 上位机默认参数（都是实测调出来的，改动前请先看 PROTOCOL.md §5.3/§6）

| 参数 | 默认 | 为什么 |
|---|---|---|
| 读窗口 `window` | 1 | 实测比 W=8 快一倍（235 vs 110KB/s）|
| 写窗口 `write_window` | 1 | 连发会丢帧并形成重传活锁 |
| 数据片超时 `data_timeout` | 200ms | 正常往返仅 2.4ms(/ram/)，500ms 会把每次丢帧放大 200 倍 |
| `wire_budget` | 508B | 保守默认：帧小、对 16B 硬件 FIFO 压力小、余量大；2026-09-17 修复后已非硬约束，实测抬到 4096 也零重传，可调大但没必要 |
| `read_chunk` | 4096B | 厂商新固件（2026-09-18 起）命令响应走 16KB 专用 response_fifo，不再受 1600B log record 截断；4096 为保守安全值（最坏线上 ~8.3KB，fifo 余量充足）。主机侧交叉校验保留为防御 |

`write_file` 按**实际内容的转义长度**逐片求解最大片长：随机内容取满 ~470B（199KB/s），
内容全是 0xA5 时自动收缩到 ~240B（仍不超限）。所以 chunk 不需要手工调。

2026-09-17 先修掉 `soc_rx` 的抽帧不完整（循环抽干后 `wire_budget` 可放到 4096 仍零重传；
"解析侧临界区"经实测定性后放弃，见设计文档 §4.2）。随后**同步了主干**：主干把上行改成
`__LOG_PORT_UNDEPENDABLE__` 的 log record 通道（app 构建默认），**单条记录 1600 字节，
超长响应会被截断且没有任何信号** —— 未察觉时 `read_file` 会把截断当成正常短读/EOF，
静默返回残缺内容（实测 4K 文件只回 1546 字节）。

因此（厂商新固件，2026-09-18 起）：TX 侧新增 **16KB 专用 response_fifo**，命令响应不再经过
1600B log record 通道、截断消除，`read_chunk` 由 760 提到 **4096**（保守安全值，最坏线上 ~8.3KB）；
主机侧两道校验**保留为防御**——`_read_window` 校验"声明的 len 是否大于实到数据"，
`read_file` 再与 `stat` 的大小交叉校验，任何未来固件回归引入的截断都会变成**显式报错**。
`cmd` 码也随主干的枚举值调整由 19 改为 **20**（主干新增的 `SOC_CMD_LOG_RELOAD` 占了 19）。

- 协议文档：[PROTOCOL.md](PROTOCOL.md)
- 设备端协议栈：[script/libs/hzadb.lua](../../script/libs/hzadb.lua)（`hzadb.fs()` 一键安装标准文件系统操作集，`hzadb.mem()`/`hzadb.netdrv()` 安装状态指令，`hzadb.set_auth()` 开启鉴权，权限由脚本控制）
- 上位机库：`host/luat_usercmd.py`（`UserCmd` 类）
- 测试脚本：`host/test_usercmd.py`

## 组成

| 文件 | 说明 |
|---|---|
| `main.lua` | 设备端 demo：引用 hzadb 库 + 安装 fs/mem/netdrv 操作集 + 心跳日志 + 启动打印挂载点/空间 |
| `PROTOCOL.md` | 协议文档 |
| `host/luat_usercmd.py` | 上位机 API 库（pyserial） |
| `host/test_usercmd.py` | 真机测试脚本 |

> 设备端协议栈已迁移为通用库 `script/libs/hzadb.lua`，本目录不再自带。

## 固件要求

上下行均为 A5 命令帧（`cmd = SOC_CMD_USER_CMD(20)`），上行不占用日志流；设备端由固件 C 的
`luat_log_user_cmd_write()` 发送（ccm42xx 端口映射到 `soc_cmd_response`）。

下行单帧大小受固件 `am_log.c` 的 `rx_cache1/rx_cache2` 限制，经 HELLO 协商分片大小：
厂商新固件 `rx_cache1[1064]` / `rx_cache2[2128]` → 写片长 **1024B**；
旧固件（512/1056）→ 写片长 476B，（128/256）→ 写片长 90B。协议栈自动适配，加大固件缓冲即可提升吞吐。

设备端 `io.lsmount()` / `io.fsstat()` / `crypto.hmac_sha256` 均为 LuatOS 标准库，
当前固件已内置；AUTH 需固件带 crypto（`LUAT_USE_CRYPTO`）。

**2026-09-17 起固件侧暂时关闭**：无自旋的日志口 RX 抽帧实测让 518B 的帧约 50% 端点收不全、
靠协议重传兜住（吞吐 196KB/s → 3KB/s），故 core 的 `am_uart.c/am_log.c/am_service.c` 已整体回滚到
原厂版本，`csdk/project/luatos/include/luat_conf_bsp.h` 里的 `LUAT_USE_LOG_USER_CMD` 已注释掉，
等原厂完成日志口 RX 适配后再打开。脚本侧已做判空：固件没开这个宏时 `hzadb.start()` 返回 `false`、
打一条 warn，心跳与挂载点打印照跑、不报错。上面参数表与实测数字均针对"宏打开"时的固件。

实测设备端下行 RX 只吞得下约 **4 个连发帧**（每帧线上 ~518B），而 W=1 在读写两个方向都最快
（读 235KB/s vs W=8 的 110KB/s），所以上位机**读写窗口都默认 1**，不要把写窗口调大。
2026-09-17 修掉了 `soc_rx` 的抽帧不完整（`chunk=476` 的单帧线上 518B 超过 512B 抽帧缓冲，
尾字节被拆到下一次中断才补回），但连发能力仍受 16B 硬件 FIFO 与 `dev_rx_buffer`(1056B) 限制。

## 文件系统兼容性

`hzadb.fs()` 安装的操作集不假设文件系统支持随机写，具体差异：

| 挂载点 | fs | 写语义 |
|---|---|---|
| `/` | soc (littlefs) | 支持带 offset 的随机写，空洞自动补零；单次 ≥256B 的写有 ~50ms page program 停顿 |
| `/ram/` | ram | **顺序写**，不支持写未分配区域（`f:seek("set", offset)` 越界被忽略、数据落到 EOF） |

对顺序写文件系统，`hzadb.lua` 的 write 处理函数在 `offset > 当前文件大小` 时**先补零到 offset 再写**，
使窗口写的重传/乱序到达保持幂等（补零上限 64KiB，超出回应 errno=4），并在写后回读大小确认落盘。
此前"直接 seek + 写"在 `/ram/` 上会静默把数据追加到 EOF，使 W≥2 的大文件写入错位、尾部丢失，且协议层无感知。
上位机侧对应加了两道校验：WRITE_DATA 回显 offset 必须与请求一致，CLOSE 返回的最终大小必须等于预期长度。
详见 PROTOCOL.md §3 / §5.3 / §6。

## 使用

```bash
# 刷机(固件 + 本 demo 脚本 + hzadb 库, 注意脚本目录不要有 __pycache__)
luatos-cli flash run --soc <LuatOS-SoC_*.soc> --port COM6 --script . --script ../../script/libs --tail-log-secs 8
# 看到 "demo ready" 即成功

# 跑测试(设备未配置 token)
python host/test_usercmd.py --port COM6

# 设备端开启鉴权后(main.lua 取消 hzadb.set_auth 注释): 跑鉴权用例
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
hzadb.set_auth("0123456789abcdef")  -- 8..64 字节, 生产建议 >=16 字节随机串, 须在 hzadb.start() 前调用
```

- HELLO 握手时设备通过 `caps` 位告知是否需要鉴权；未配置 token 的设备行为与之前完全一致
- 鉴权流程：host 用 token 对 HELLO nonce 做 HMAC-SHA256，hex 后发送；错误 mac 回应 errno=2
- HELLO 会重置鉴权状态（重握后必须重新 auth）；已知限制与威胁模型见 PROTOCOL.md §5.5/§7
