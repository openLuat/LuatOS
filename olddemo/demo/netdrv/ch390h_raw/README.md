# ch390h_raw — 手工 DHCP + 手工 ARP / ICMP ping demo

平台: **Air780EPM** + CH390H SPI 以太网 (`netdrv.CH390`, SPI0, CS=GPIO8, 25.6MHz)

本 demo **完全绕开系统 DHCP 客户端与 `netdrv.ping`**, 直接在 `socket.LWIP_ETH` 上用
`netdrv.send_raw()` 把手工构造的协议包发到网线, 用 `netdrv.on(EVT_PKG, layer="hw")`
拦截对端回应。

适合用来:

- 验证 `netdrv.send_raw` / `netdrv.on(EVT_PKG, ...)` 的 HW 通道用法
- 调试 CH390H 链路层 / 网关侧行为
- 当系统的 DHCP / ping 模块不便使用或想完全掌控 L2 报文时的参考实现

---

## 文件组成

| 文件 | 作用 |
|---|---|
| `main.lua` | 入口: SPI 初始化 → 注册 ch390h → **禁用系统 DHCP** → 等 link → 加载 raw_dhcp → 加载 ping_raw |
| `raw_dhcp.lua` | 手工 4 步 DHCP 握手 (DISCOVER / OFFER / REQUEST / ACK), 拿到 IP 后调 `netdrv.ipv4()` 应用, publish `RAW_DHCP_DONE` |
| `ping_raw.lua` | 手工 ARP 解析网关 MAC → 手工构造 ICMP echo request → on_pkg 拦截 reply → 计算 RTT, 周期性 ping + 统计 |

---

## 关键 API 用法

### 1. 发送原始包 (TX 方向)

```lua
-- 构造完整 Ethernet 帧 (含 IP/UDP/DHCP 或 ARP/ICMP)
local frame = build_dhcp_frame(...)  -- 自己算 checksum, 自己填 chaddr/options
local zb = zbuff.create(#frame, 0)
zb:write(frame)
local sent = netdrv.send_raw(ADAPTER, netdrv.CH_HW, zb)
```

- `netdrv.CH_HW = 0x10` 是物理硬件通道, 数据通过 `drv->dataout` → SPI → 网线
- `zbuff.used` 长度即发送长度 (可选第 4 参覆盖)
- 发送是异步的, send_raw 成功只代表"已入队"

### 2. 接收原始包 (RX 方向, layer="hw")

```lua
netdrv.on(ADAPTER, netdrv.EVT_PKG, function(id, layer, zb)
    -- layer 是 netdrv.CH_HW / CH_LWIP / CH_NAPT 之一
    -- zb:used() 是包长度, zb:toStr() 拿到完整 Ethernet 帧
end, { layer = "hw" })
```

- `layer="hw"` 是**被动观察**语义: 回调拿到副本, 包照常走 NAPT/LWIP 后续流程
- 如果需要**拦截** LWIP 出口的 TX 包 (即"注册即消费"), 用 `{ layer = "lwip" }`
- 同一时刻一个 adapter 只能有一个 callback; 用 `netdrv.on(adapter, EVT_PKG, nil)` 注销

### 3. 适配器 / 设备注册

```lua
netdrv.setup(socket.LWIP_ETH, netdrv.CH390, { spi = 0, cs = 8 })
netdrv.dhcp(socket.LWIP_ETH, false)              -- 关闭系统 DHCP
netdrv.mac(socket.LWIP_ETH)                       -- 读 MAC
netdrv.ipv4(socket.LWIP_ETH, ip, mask, gw)       -- 设静态 IP (会顺手关 DHCP)
```

注意: `netdrv.setup` 的 opts key 是 **`spi`** (不是 `spiid`), 详见 `luat_lib_netdrv.c l_netdrv_setup`.

---

## 报文构造要点

### DHCP 帧 (Ethernet + IP + UDP + DHCP, 342 字节)

- BOOTP 头 236 字节 + magic cookie `63:82:53:63` + options
- UDP 校验和填 0 (IPv4 下 UDP 校验和是可选的, 0 表示未计算)
- IP 头校验和必须算 (RFC 1071, 16-bit 大端累加 + 回卷 + 取反)
- DHCP 必须有 option 53 (msg type), 55 (param req list), 50 (req IP, 仅 REQUEST), 54 (server ID, 仅 REQUEST)

### ARP request / reply (Ethernet + ARP, 42 / 28 字节)

- Ethernet type `0x0806`
- ARP: HTYPE=1 PTYPE=`0x0800` HLEN=6 PLEN=4
- request: OPER=1, THA=00:00:00:00:00:00 (未知), TPA=target IP
- reply:   OPER=2, THA=sender, SHA=us, SPA=our IP, TPA=sender IP

### ICMP echo request / reply (Ethernet + IP + ICMP, 58+ 字节)

- IP 头: protocol=1 (ICMP), 头校验和必须算
- ICMP 头: type=8 (req) / 0 (reply), code=0, checksum 必须算
- 同一对 request/reply 的 `identifier` 必须一致 (我们用 session 起点 + seq 派生, 每次唯一)

---

## 关键设计点 (踩过的坑)

### 1. 手工 ARP reply 必须做 (不要等 LWIP)

注册 `layer="hw"` 之后, LWIP 默认的 ARP 自动回复路径不再可靠 — 网关反复发
`who-has <our IP>` 但收不到 reply, 后续 ICMP reply 也发不出来 (它需要先知道我们的 MAC)。

修法: 在 `on_pkg` 里**解析 ARP request**, 如果 `target IP == our IP`, 立刻手工构造
ARP reply 通过 `netdrv.send_raw(CH_HW, ...)` 发回:

```lua
if oper == 1 and MY_IP and tpa == MY_IP then
    local reply = build_arp_reply(sha, spa, MY_IP)
    send_frame(reply, "ARP reply (手工)")
end
```

### 2. 不要随便改 IP, 用 DHCP 拿到的 IP

把 DHCP 拿到的 IP (例如 `192.168.1.4`) 再用 `netdrv.ipv4()` 覆盖成"自定义" IP
(例如 `.200`), 网关的 ARP cache 会刷新, **期间 ping 会丢包**, 表现为"前 N 次成功,
后面失败"。

本 demo 直接使用 `raw_dhcp` 拿到的 IP, 不二次覆盖。

### 3. ICMP id 和 IP identification 必须每次唯一

固定值 (`0x1234`) 会被部分路由器按 IP id 去重, 表现为"前几次成功, 后面失败"。

```lua
local ICMP_ID_BASE  = (mcu.ticks() & 0xFFFF)   -- session 起点, 每 ping 自增
local pkt_ip_id     = (mcu.ticks() & 0xFFFF)   -- 独立 IP id 计数器, 每发一包 +1
```

### 4. REQUEST 必须用 option 54, 不是 siaddr

DHCP 服务器在 OFFER 里经常**不填 siaddr** (`siaddr=0.0.0.0`), 但 **option 54 (Server
Identifier) 是 RFC 2131 必填**。REQUEST 必须把 OFFER 里的 option 54 原样回填, 否则
server 不知道接受哪家 offer, 直接忽略 (不 ACK 也不 NAK, 12s 超时)。

```lua
local server_id = offer.options[54] and ip_from_bytes(offer.options[54]) or offer.siaddr
build_dhcp_frame(..., requested_ip = offer.yiaddr, server_id = server_id)
```

### 5. MAC 字符串格式兼容

`netdrv.mac()` 返回无分隔 (`AABBCCDDEEFF`), `bytes_to_mac()` 返回带冒号
(`AA:BB:CC:DD:EE:FF`)。`mac_str_to_bytes` 用 `gsub("[:-]", "")` 两种都吃。

### 6. 同步机制: sys.publish/subscribe + 短轮询 waitUntil

sys 没有 semaphore。包回调和 task 间同步用 `sys.publish` + 短轮询
`sys.waitUntil(topic, 100)`:

```lua
-- 回调里
sys.publish("ping_raw_icmp")
-- task 里
while not pending_icmp_reply do
    if mcu.ticks() >= deadline then break end
    sys.waitUntil("ping_raw_icmp", 100)  -- 100ms 内有 publish 就立即唤醒
end
```

注意: 包可能比 `waitUntil` 先到, 必须**先有状态变量 (如 `pending_icmp_reply`)**,
waitUntil 只是加速唤醒, 真正判断靠状态。

### 7. on_pkg 引用本地函数的 forward-declare

`on_pkg` 里要调 `send_frame`, 但 `send_frame` 定义在 `on_pkg` 之后, Lua
会把 `send_frame` 当 global 解析 (此时还是 nil)。必须在 `on_pkg` 之前
`local send_frame` 前向声明。

---

## DHCP 状态机

```
IDLE --(DISCOVER)--> WAIT_OFFER --(OFFER)--> WAIT_ACK --(ACK)--> DONE
                          |                    |
                          +-(12s 超时)--------> |
                          +-(NAK)--------------> |
```

每步最大 12s, 最多重试 5 次。

## ICMP ping 流程

```
1) 等 raw_dhcp 拿 IP
2) 注册 on_pkg (HW 入口被动观察 + 手工 ARP reply)
3) 主动 ARP request 解析网关 MAC (重试 3 次)
4) 周期 ICMP echo (默认 4 次, 间隔 3s):
   - 构造 ICMP request (Ethernet + IP + ICMP, 含 checksum)
   - send_raw(CH_HW)
   - 等 reply, 匹配 id+seq, 算 RTT (mcu.ticks 毫秒)
5) 打印 min / avg / max RTT
```

---

## 调参

`ping_raw.lua` 顶部:

```lua
local ICMP_ID_BASE  = (mcu.ticks() & 0xFFFF)   -- session 起点
local ICMP_PAYLOAD  = "LuatOS-raw-ping"
local PING_INTERVAL = 500                       -- ms, ping 间隔
local ARP_TIMEOUT   = 3000                      -- ms, 等 ARP reply 超时
local ICMP_TIMEOUT  = 3000                      -- ms, 等 ICMP reply 超时
local PING_COUNT    = 16                        -- 总次数
local ARP_RETRIES   = 3                         -- ARP 请求重试次数
```

`raw_dhcp.lua` 顶部可调超时/重试。

---

## 烧录与运行

1. 把整个目录 (`main.lua` + `raw_dhcp.lua` + `ping_raw.lua`) 烧到 Air780EPM
2. 串口日志看握手过程: link up → DHCP OFFER/ACK → ARP 网关 → ICMP echo

典型日志 (摘录):

```
I/user.ch390h_raw  ✓ link up
I/user.raw_dhcp    TX DISCOVER
I/user.raw_dhcp    RX OFFER xid=... yiaddr=192.168.1.4
I/user.raw_dhcp    ✓ OFFER: ip=192.168.1.4 mask=255.255.255.0 gw=192.168.1.1
I/user.raw_dhcp    TX REQUEST
I/user.raw_dhcp    RX ACK xid=...
I/user.raw_dhcp    应用 netdrv.ipv4(192.168.1.4, 255.255.255.0, 192.168.1.1)
I/user.raw_dhcp    已关闭 DHCP 包拦截
I/user.ping_raw    使用 DHCP IP: ip=192.168.1.4 mask=255.255.255.0 gw=192.168.1.1
I/user.ping_raw    RX ARP req who-has 192.168.1.4 tell 192.168.1.1 -> 回 ARP reply
I/user.ping_raw    TX ARP reply (手工) 已发送 42 字节
I/user.ping_raw    RX ARP reply: 192.168.1.1 is-at 54:E0:05:EC:0E:FC
I/user.ping_raw    ✓ 网关 MAC = 54:E0:05:EC:0E:FC
I/user.ping_raw    ✓ #1 reply id=0xE2 seq=1 from 192.168.1.1 rtt=8ms
...
I/user.ping_raw    统计: 发送=16 成功=16 失败=0 平均 RTT=7ms min=5ms max=8ms
```

---

## 依赖 (boot 期 loadedlibs, 无需 require)

- `netdrv` — send_raw / on / ipv4 / setup / dhcp / mac
- `zbuff`  — 包缓冲
- `socket` — `socket.LWIP_ETH` 常量
- `sys`    — taskInit / publish / waitUntil / wait
- `mcu`    — `mcu.ticks()` 毫秒计时
- `log`    — 日志
