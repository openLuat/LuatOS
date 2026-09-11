# netdrv IPv6 兼容性核查与实现报告

> 分支: `feature/netdrv-ipv6`
> 日期: 2026.01
> 范围: 新增 Lua API `netdrv.ipv6`; 核查 **CH390H 外挂以太网**、**airlink / whale 虚拟网卡**、
> **net_lwip2 适配层** 三条路径的 IPv6 兼容性。

---

## 1. 结论速览

| 对象 | IPv6 入向 | IPv6 出向 | 链路本地自动生成 | 本次改动 |
|------|-----------|-----------|------------------|----------|
| net_lwip2 适配层 | 已有(`ip6_input` + `get_ip6`) | **原先被显式拒绝** | **缺失** | 补齐设置/读取/链路本地/就绪判定 |
| CH390H(AirETH / SPI 外挂网卡) | 已通(`luat_netdrv_ethernet_input` → `ip6_input`) | 已通(`ethip6_output`) | **缺失(时序问题)** | MAC 就绪后补一次链路本地生成 |
| airlink / whale 虚拟网卡 | 已通(loopback exec 无 EtherType 过滤) | **被白名单拦掉(致命)** | **缺失 + MAC 从未生效** | 放行 0x86DD; `netdrv.setup` 解析 `mac` 参数 |
| NAPT | 不适用 | **不支持 IPv6 转发** | — | 显式打点, 明确丢弃 |

一句话: **net_lwip2 是 IPv6 能力的唯一后端**, 此前只有"读"没有"写";
CH390H 的链路只差一次链路本地地址生成; airlink 侧有一个 IPv6 放行白名单必须打开。

---

## 2. net_lwip2 适配层(`components/network/adapter_lwip2/net_lwip2.c`)

### 2.1 核查证据

| 位置 | 现状 | 结论 |
|------|------|------|
| `net_lwip2.c:953`(改动前) `EV_LWIP_NETIF_SET_IP` | `if (is_ipv6) { LLOGE("当前不支持设置ipv6地址"); ... }` | **写路径完全缺失** |
| `net_lwip2_set_static_ip()` | 已支持第4参 `ipv6`, 并把 `ipv6 != NULL` 作为 `Param2` 投递 | 链路已备, 只差消费端 |
| `net_lwip2_get_ip6()` / `net_lwip2_get_full_ip_info()` | 已能按 `IP6_ADDR_PREFERRED` → `IP6_ADDR_VALID` 返回地址 | 读路径可用 |
| `net_lwip2_check_network_ready()` / `net_lwip2_check_ready()` | 只看 `ip_addr_isany()`(IPv4) | **IPv6-only 会被判"未就绪"** |
| 全仓 | 无任何 `netif_create_ip6_linklocal_address()` 调用 | **链路本地地址从未生成**, ND6/RS/SLAAC 无法启动 |
| `lwip22/port/luat_rtos/lwipopts.h:229`, `bsp/pc/include/lwipopts.h:40` | `LWIP_IPV6 1`, MLD6/AUTOCONFIG/SEND_ROUTER_SOLICIT 全开 | 编译期能力齐备, 无需改 lwipopts |

### 2.2 本次实现

- 新增 `net_lwip2_ipv6_supported()` / `net_lwip2_ipv6_addr_info()` /
  `net_lwip2_ipv6_linklocal_addr_info()` / `net_lwip2_ipv6_create_linklocal()` /
  `net_lwip2_set_static_ip6_info()` / `net_lwip2_ipv6_is_ready()`;
  在 `net_lwip2.h` 中声明, `LWIP_IPV6==0` 时提供退化实现。
- `EV_LWIP_NETIF_SET_IP` 分支改造: IPv4 与 IPv6 分派; **IPv4 分支不再触碰 `ip6_addr[]`**。
- IPv6 槽位约定: **槽 0 固定留给链路本地地址**; 全局地址取第一个空闲的非 0 槽位。
- 链路本地地址生成后立即置 `IP6_ADDR_PREFERRED`(跳过 DAD): 地址由 MAC 的 EUI-64 推导,
  唯一性由 MAC 保证; 若保持 TENTATIVE, 出向 ICMPv6/ND 会因"无有效源地址"直接发不出去。
- 前缀长度: `ip6_addr_t` 不保存前缀, 由适配层 `net_lwip2_ctrl_struct.ip6_prefix[]` 记录
  (未设置时回落 64); 与 `socket.localIP()` 的第 4 个返回值共用同一份地址选择逻辑。
- 地址选择顺序: **PREFERRED 全局 → VALID 全局 → PREFERRED 任意 → VALID 任意**,
  这样 `netdrv.ipv6()`/`socket.localIP()` 优先给出用户配置或 RA 下发的全局地址,
  只有完全没有全局地址时才回落到 `fe80::`。
- 就绪判定放宽为"IPv4 非 0 **或** 存在 VALID IPv6 地址", 纯 IPv4 场景行为不变。

### 2.3 未覆盖 / 限制

- **不支持 DHCPv6**: `LWIP_IPV6_DHCP6` 保持 0, 未引入有状态地址分配。
- **不写 IPv6 默认路由**: `netdrv.ipv6` 的 `gw` 参数只作回显; IPv6 缺省路由需要 ND6 router
  状态机, 需由 RA 提供或后续单独实现。
- **不做 IPv6-only 的 DNS 说明**: 现有 `net_lwip2_check_network_ready()` 仍按 IPv4 规则配置
  DNS 服务器, IPv6-only 场景下 DNS 需要静态配置(不在本次范围)。

---

## 3. CH390H / AirETH 外挂以太网

### 3.1 核查证据

| 位置 | 现状 | 结论 |
|------|------|------|
| `luat_netdrv_ch390h.c:106-128` `ch390_netif_init` | `output_ip6 = ethip6_output`; flags 含 `NETIF_FLAG_ETHARP \| ETHERNET \| IGMP \| MLD6` | 出向/组播能力已具备 |
| `luat_netdrv_lwip_netif_ethernet.c:220-233` | `ETHTYPE_IPV6` → 跳过以太网头 → `ip6_input` | **入向已通** |
| `luat_netdrv_ch390h_task.c:289-310` | MAC 是异步从芯片读出来的, 写完才 `status = 2` | **链路本地地址生成时机**是唯一缺口 |
| `luat_netdrv.c:318-352` | `netif_set_down` / `set_link_down` 已挂 `nd6_cleanup_netif()` | 休眠/停机路径无需改动 |
| `luat_netdrv_napt.c` | 只放行 `ETHTYPE_IP`(0x0800) | NAPT 不支持 IPv6 转发(见 §5) |

### 3.2 本次实现

- `ch390_netif_init()` 里**不**生成链路本地地址(那时 `hwaddr` 还是全 0)。
- 在 `luat_netdrv_ch390h_task.c` 写完 `netif->hwaddr` 之后再调用
  `net_lwip2_ipv6_create_linklocal()`; 该函数幂等, 且会拒绝全 0 的 MAC。
- 未链接 lwip2 适配层的构建里, 该符号由 `luat_netdrv.c` 的弱符号兜底, 不会出现未解析符号。

### 3.3 真机验证建议

Air8000 / Air780EHM + AirETH(AirETH_1000) 或 SPI 直挂 CH390H:

1. `netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0, cs=8})`
2. 等待链路 up, `netdrv.ipv6(socket.LWIP_ETH, "linklocal").addr` 应为 `fe80::` 且与芯片 MAC 的
   EUI-64 一致(可用 `netdrv.mac()` 手工推算比对)
3. 静态地址: `netdrv.ipv6(socket.LWIP_ETH, "2409:xxxx::10", 64)` → 回读一致
4. 上游路由支持 RA 时, 应能自动拿到全局地址(观察 `netdrv.ipv6()` 返回值出现非 `fe80::` 地址)
5. `netdrv.ping(socket.LWIP_ETH, "2409:xxxx::1")` 用 IPv6 目的地址, 观察 `PING_RESULT`

---

## 4. airlink / WHALE 虚拟网卡

### 4.1 核查证据

| 位置 | 现状 | 结论 |
|------|------|------|
| `luat_netdrv_whale.c:79-84` | `netif_output_ip6` 已实现, 经 `netif_output()` 走 `dataout` | 出向形状正确 |
| `luat_netdrv_whale.c:151-153` | `netif->output_ip6 = netif_output_ip6` | 已注册 |
| `luat_netdrv_whale.c:194-206`(改动前) | 仅 WIFI_STA/WIFI_AP 默认补 `ETHARP\|IGMP\|MLD6` | USER0~7 拿到的是 `NETIF_FLAG_BROADCAST`, **没有 ETHARP → 没有 MAC → 无法生成链路本地地址** |
| `components/airlink/src/luat_airlink.c:576`(改动前) | `if (eth->type == ETHTYPE_IP \|\| eth->type == ETHTYPE_ARP)` 才放行 | **IPv6(0x86DD)被丢弃**, 这是硬阻断 |
| `components/airlink/src/exec/luat_airlink_cmd_exec_ippkg.c:23-89` | 入向按 `adapter_id` 直接 `netif_input_proxy`, 无 EtherType 过滤 | 收向已通, 无需改动 |
| `components/airlink/src/task/luat_airlink_task.c:54` | 硬件路径同样转 `luat_airlink_cmd_exec_ip_pkg` | 与 loopback 同构, 无第二处白名单 |
| `luat_lib_netdrv.c` `l_netdrv_setup`(改动前) | **完全没有解析 `opts.mac`** | `cfg.mac` 恒为全 0, 链路本地地址必然非法 |

### 4.2 本次实现

- `luat_lib_netdrv.c`: 解析 `opts.mac`(必须 6 字节, 否则告警并忽略), 存入 `luat_netdrv_conf_t.mac`。
- `luat_netdrv.h`: `luat_netdrv_conf_t` 增加 `uint8_t mac[6]`。
- `luat_netdrv_whale.c`: 把 `conf->mac` 带进 whale 配置;
  USER0~7 等非 STA/AP 适配器在 `flags == 0` 时也默认补 `ETHARP | MLD6`(`mac` 缺省时打印告警);
  在 `netif_add` / `net_lwip2_register_adapter` 之后调用
  `net_lwip2_ipv6_create_linklocal()`。
- `luat_airlink.c`: EtherType 白名单放行 `ETHTYPE_IPV6`(受 `#if LWIP_IPV6` 保护)。

### 4.3 行为变化提醒(重要)

WHALE 网卡的以太网模式是**显式开启**的, 判据是 `netdrv.setup` 的 opts 里是否传了
`mac`(非全 0)或 `flags`:

| 调用方式 | 结果 |
|----------|------|
| `netdrv.setup(id, netdrv.WHALE)` | **保持历史行为**: 裸 IP 帧、无 MAC、无 IPv6 链路本地地址 |
| `netdrv.setup(id, netdrv.WHALE, {flags = ...})` | 按用户给定 flags; 需要以太网/IPv6 时请自行带上 `ETHARP`/`MLD6` |
| `netdrv.setup(id, netdrv.WHALE, {mac = <6字节>})` | **以太网模式**: 自动补 `BROADCAST\|ETHARP\|MLD6`, 并生成 IPv6 链路本地地址 |
| `socket.LWIP_STA` / `socket.LWIP_AP` 且不传 flags | 仍按历史默认走以太网模式(airlink WiFi 依赖它) |

之所以做成 opt-in: airlink 虚拟链路真实收发的是带以太网头的帧, 但既有部署
(如 `script/libs/exnetif.lua` / `exremotefile.lua` 里的 `netdrv.setup(adapter, netdrv.WHALE)`)
依赖"裸 IP"路径, 默认切换会带来两个可见变化:

1. 网卡会先发 ARP(对端不回 ARP 时, IPv4 报文会被 ARP 队列缓存)。PC 模拟器/虚拟链路下
   可用新增的 `netdrv.arp(id, ip, mac)` 手工写入表项绕过。
2. `netdrv.on(id, netdrv.EVT_PKG, cb, {layer="lwip"})` 捕获到的帧从"裸 IP + ICMP"变为
   "以太网头(14B) + IP + ICMP"。`netdrv_lwip_intercept_basic` 已同时兼容两种格式。

**想在 airlink 上使用 IPv6, 必须显式传 `mac`**:

```lua
netdrv.setup(socket.LWIP_STA, netdrv.WHALE, { mac = string.char(0x02,0,0,0,0,1) })
```

### 4.4 真机验证建议

Air8000/Air1601 双芯片 airlink 场景:

1. 主机侧 `netdrv.setup(socket.LWIP_STA, netdrv.WHALE, {mac=...})`(必须传 mac),
   从机侧 `airlink.start()`
2. 主机侧 `netdrv.ipv6(socket.LWIP_STA, "2409:xxxx::20", 64)`, 从机侧同网段配置并互 ping
3. 观察主机侧 `netdrv.on(..., {layer="lwip"})` 能否看到 ethertype=0x86DD 的出向帧
   (修复前该帧在 `luat_airlink_queue_send_ippkg` 被丢弃)

---

## 5. NAPT 边界

`luat_netdrv_napt.c` 的转发改写器全部是 `ip4_addr_t`, 因此:

- 入包在 `ctx.eth->type != PP_HTONS(ETHTYPE_IP)` 时直接 `return 0`, 本来就无法进入 IPv4 解析;
- 本次只补了一条 `ETHTYPE_IPV6` 的 `LLOGD` 打点, 便于定位"IPv6 流量被静默丢弃";
- **IPv6 网关转发 / NAPT66 明确不在本次范围**。

---

## 6. 新增 Lua API

```lua
-- 读取(全局地址优先; 无地址时返回空 table)
local info = netdrv.ipv6(socket.LWIP_ETH)
-- { addr="2001:DB8::10", prefix=64, gw="", source="static", state="preferred" }

-- 单独读取链路本地地址
local ll = netdrv.ipv6(socket.LWIP_ETH, "linklocal")

-- 设置静态地址(第2参必须是 IPv6 字面量; prefix 1..128, 默认 64)
netdrv.ipv6(socket.LWIP_ETH, "2409:8a00:1234:5678::10", 64)
```

失败语义: 地址非法 / 前缀越界 / 传入 IPv4 字面量 / netdrv 不存在 → 返回 `false`;
读取时网卡不存在 / 无有效 IPv6 → 返回空 `table`。

辅助 API(本次一并新增):

```lua
-- 手工写入 ARP 表(点对点/虚拟链路场景, 对端不回 ARP 时必需)
netdrv.arp(socket.LWIP_ETH, "192.168.1.1", string.char(0x02,0,0,0,0,1))
netdrv.arp(socket.LWIP_ETH, "192.168.1.1", nil)   -- 删除
```

新增常量: `netdrv.IPV6_PREFIX_DEFAULT`(64)、`netdrv.IPV6_PREFIX_MAX`(128)。

---

## 7. 测试与验收

### 7.1 PC 模拟器(已验证)

```powershell
cd bsp\pc
cmd /c build_windows_32bit_msvc.bat
cd build\out
.\luatos-lua.exe ..\..\..\..\testcase\common\scripts\ ..\..\..\..\testcase\unit\net\netdrv_ipv6_basic\scripts\
```

| 套件 | 结果 |
|------|------|
| `unit/net/netdrv_ipv6_basic`(新增, 7 用例) | **7 passed, 0 failed** |
| `unit/net/netdrv_lwip_intercept_basic`(兼容以太网帧) | **3 passed, 0 failed** |
| `unit/net/netdrv_evt_pkg` | **19 passed, 0 failed** |
| `unit/net/netdrv_ipsec_basic` | 3 passed, 0 failed |

`unit/net/netdrv_l2tp_basic` 的 `test_l2tp_connect` 失败与本分支无关: 该用例需要本地
`127.0.0.1:1701` 上有一个可应答的 L2TP/PPP 服务端, 当前环境未启动, 30s 超时。

### 7.2 CI

`.github/workflows/windows-build.yml` 的 test matrix 已加入
`netdrv_ipv6_basic` 与 `netdrv_lwip_intercept_basic`。

### 7.3 真机清单(待执行)

见 §3.3 与 §4.4; 建议型号矩阵: Air8000 + AirETH/CH390H、Air780EHM + CH390H、
Air8101(内置以太网 + WHALE)、以及 airlink 双芯片组合。

---

## 8. 已知限制汇总

1. 不支持 DHCPv6 / IPv6 有状态地址分配。
2. `netdrv.ipv6` 的 `gw` 参数只回显, 不写 IPv6 默认路由。
3. IPv6 网关转发(NAPT66)未实现。
4. `netdrv.ping` 的 IPv6 源地址选择在存在多个地址时由 `netdrv.ping` 内部策略决定(优先全局地址)。
5. `netdrv.arp` 只支持 IPv4; IPv6 邻居表(ND6)暂无手工写入接口
   (lwip 的 `neighbor_cache` 为 `nd6.c` 内部私有状态)。
