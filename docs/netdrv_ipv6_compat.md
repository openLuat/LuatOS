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

### 1.1 功能开关 `LUAT_USE_NETDRV_IPV6`

`LWIP_IPV6` 在各 BSP 上默认都是打开的, 因此**不能**拿它当"netdrv 是否提供 IPv6 能力"
的判据。本次新增独立的编译宏 `LUAT_USE_NETDRV_IPV6`, 语义与本仓库其它 `LUAT_USE_*`
能力宏(`LUAT_USE_NETDRV_LWIP_ARP` 等)完全一致——**只看"有没有定义", 不看取值**:

| 状态 | 行为 |
|------|------|
| 未定义 | **关闭(默认)** |
| 已定义 | **启用**(惯例写 `1`, 但判据只看是否定义, 写 `0` 同样是启用) |

因此:

- 开启 = 在自己 BSP 的 `luat_conf_bsp.h` 里显式写出 `#define LUAT_USE_NETDRV_IPV6 1`;
- 关闭 = 注释掉/删掉那一行。**不要**用 `#define LUAT_USE_NETDRV_IPV6 0` 来关闭,
  在该约定下 `0` 也算"已定义", 等同于开启。

`bsp/pc/include/luat_conf_bsp.h` 已显式写出该行, 是 PC 模拟器的开启点。
`luatos-soc-2024` 的 SOC 构建读的是它自己那份
`project/luatos/inc/luat_conf_bsp.h`(`bsp/pc/include` 不在其 include 路径上),
那里默认没有这一行, 所以 SOC 构建默认**不含** netdrv IPv6 能力; 需要时在该文件里补上同一行即可。

两种状态均已实测: PC 增量编译都是 `Build completed successfully`; 关闭时
`netdrv.ipv6` 与 `IPV6_PREFIX_*` 整体不存在(新增的 `netdrv_ipv6_basic` 套件会自动跳过而非报错),
不生成链路本地地址, 就绪判定退回纯 IPv4,
且 `netdrv.arp` 仍然可用(它是 IPv4 能力, 不随本宏关闭)。

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
  (未设置时回落 64); 设置时前缀打包进 `EV_LWIP_NETIF_SET_IP` 事件的 Param2 高 24 位,
  由 tcpip 线程在 `net_lwip2_ipv6_apply_set` 内与地址一起写入, 不走跨线程预写;
  与 `socket.localIP()` 的第 4 个返回值共用同一份地址选择逻辑。
- 地址选择顺序: **PREFERRED 全局 → VALID 全局 → PREFERRED 任意 → VALID 任意**,
  这样 `netdrv.ipv6()`/`socket.localIP()` 优先给出用户配置或 RA 下发的全局地址,
  只有完全没有全局地址时才回落到 `fe80::`。
- 就绪判定放宽为"IPv4 非 0 **或** 存在 VALID 的**全局** IPv6 地址", 纯 IPv4 场景行为不变。
  仅有链路本地(fe80::/10)不算就绪——否则链路本地自动生成后, DHCPv4 还没完成
  socket 层就会被误判为网络就绪(见 `net_lwip2_ipv6_is_ready`)。

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
- 未链接 lwip2 适配层的构建里, 该符号由 `luat_netdrv.c` 的弱定义兜底, 不会出现未解析符号:
  MSVC 走 `/alternatename` 别名到 stub, GCC/ELF 直接给带函数体的 `__attribute__((weak))` 定义
  (注意: 仅有 weak 声明而没有定义时, 未定义引用会解析为地址 0, 调用即跳 0 崩溃, 起不到兜底作用)。

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

**另一处行为变化**: 显式传 `flags` 且未传 `mtu` 时, mtu 缺省由 0(历史值, 会导致 TCP MSS
计算异常) 修正为 1460; 显式传 `mtu` 仍按传入值。

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

> 该 API 受 `LUAT_USE_NETDRV_IPV6` 控制, 关闭时不存在(`netdrv.ipv6 == nil`)。

失败语义: 地址非法 / 前缀越界 / 传入 IPv4 字面量 / netdrv 不存在 → 返回 `false`;
读取时网卡不存在 / 无有效 IPv6 → 返回空 `table`。netdrv 未创建或 netif 未就绪
(例如 `netdrv.setup` 后 netif 尚未注册的窗口) 同样按此约定: 读取空 `table`, 设置 `false`。

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
| `unit/net/netdrv_ipv6_basic`(新增, 9 用例) | **9 passed, 0 failed** |
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
6. 关闭 `LUAT_USE_NETDRV_IPV6` 时 `netdrv.ipv6` 与 `IPV6_PREFIX_*` 不存在,
   `netdrv.ready()`/`socket.localIP()` 退回纯 IPv4 语义(IPv6 地址仍由 lwip 自身
   维护, 只是 netdrv 不再参与设置与上报)。

---

## 9. 经验总结

1. **能力宏用「存在语义」, 不要用「值语义」。** 本仓库所有 `LUAT_USE_*` 能力宏
   (`LUAT_USE_NETDRV_LWIP_ARP`、`LUAT_USE_NETDRV_NAPT` 等) 一律用
   `#ifdef` / `defined(...)` 判断。写成 `#if MACRO` 会引入两个坑:
   - 宏未定义时在 `#if` 里求值为 0, 还叠加 `-Wundef` 风险;
   - 「定义成 0」与「不定义」都能关, 关闭手段变成两种, 极易误配。

   因此本宏的约定是: **注释掉即关闭; 不要用 `#define ... 0` 去关**(`0` 也算已定义 = 启用)。

2. **`LWIP_IPV6` 不能当作"netdrv 是否提供 IPv6 能力"的判据。** 各 BSP 的
   `lwipopts.h` 都把 `LWIP_IPV6` 打开, 拿它当判据等于永远开启。历史上那版
   "未定义时跟随 `LWIP_IPV6`" 的兜底, 直接导致「注释掉宏关不掉功能」——这是一个
   实测才发现的静默失效, 静态读代码很难看出来。

3. **`luat_netdrv_t` 是跨编译单元的 ABI 结构体, 字段只能追加在末尾。**
   `drv->debug` 被 openvpn/l2tp/ipsec 等不同 `.c` 直接写, `drv->statics` 由
   netdrv 内部用; 结构体由驱动与预编译库共同分配。所以:
   - 新字段一律追加到末尾, 不要插在中间(会顶掉既有字段偏移);
   - 新字段**不要**包在功能宏里, 否则 `sizeof`/偏移随编译开关变化,
     只要有一处 TU 与该宏取值不一致(典型是预编译库与工程配置不同步),
     就会出现布局错位 -> 静默内存错乱, 且没有任何编译期报错。

   功能开关应该只控制"用不用这个字段", 而不是"有没有这个字段"。

4. **头文件注释里有两个会打断编译的写法**(MSVC 实测, 报错位置会指向注释本身):
   - 反引号紧跟 `#`(如 `` `#define ``): 反引号会被当作**字符常量起始**, 吞掉后面整个
     头文件内容;
   - 注释里出现 `*/`(如写路径 `xxx/*/include/`): 会**提前闭合块注释**。

5. **SOC 构建不读 `bsp/pc/include`。** `luatos-soc-2024` 的构建经
   `components/common/c_common.h` 引入的是它自己那份
   `project/luatos/inc/luat_conf_bsp.h`, `bsp/pc/include` 不在其 include 路径上。
   所以宏的提供方是**各 BSP 自己的 `luat_conf_bsp.h`**, 改 `bsp/pc` 不会影响 SOC。

6. **换源树后必须清构建缓存。** 同一 `build/.objs` 下曾同时残留 `LuatOS` 与
   `LuatOS-ipv6` 两棵源树的对象, 会污染对比结论; 切换 `luatos_root` 前先
   `xmake clean -a`。

---

## 10. 问答

### Q1. 某一款固件要怎么打开 netdrv IPv6?
在该 BSP 的 `luat_conf_bsp.h` 里显式写一行:

```c
#define LUAT_USE_NETDRV_IPV6 1
```

PC 模拟器已写在 `bsp/pc/include/luat_conf_bsp.h`。`luatos-soc-2024` 的 SOC 构建需写在
它自己的 `project/luatos/inc/luat_conf_bsp.h`, 默认没有这一行(即默认关闭)。

### Q2. 怎么关掉?
把那一行**注释掉或删掉**即可, 不需要写别的。

### Q3. 我写 `#define LUAT_USE_NETDRV_IPV6 0` 想关掉, 为什么不生效?
因为判据是"有没有定义", 不是取值。`0` 同样是"已定义", 所以**反而会开启**。
这是刻意与 `LUAT_USE_NETDRV_LWIP_ARP` 等宏保持一致的语义。要关就注释掉。

### Q4. 不写这个宏会怎样? 会报错吗?
不会报错, 也**不会**自动跟随 `LWIP_IPV6`。结果是静默关闭: `netdrv.ipv6 == nil`、
`netdrv.IPV6_PREFIX_*` 不存在、不生成链路本地地址、`netdrv.ready()` 与
`socket.localIP()` 退回纯 IPv4; 对应的 `netdrv_ipv6_basic` 套件会自动跳过。
好处是省 flash(SOC 实测 `.text` 由 4429604 降到 4426148, 约省 3.4KB)。

**代价是"忘了定义"没有任何编译期提示**, 只会安静地少功能。核查办法: 编译后看
`net_lwip2_ipv6_supported()` 的返回值(开启 1 / 关闭 0), 或确认 `netdrv.ipv6` 是否存在。

### Q5. 关掉 IPv6 会连带关掉 `netdrv.arp` 吗?
不会。`netdrv.arp` 是 IPv4 能力, 由 `LUAT_USE_NETDRV_LWIP_ARP` 控制, 与
`LUAT_USE_NETDRV_IPV6` 无关, 两者在 `reg_netdrv[]` 里各自独立注册。

### Q6. 给 `luat_netdrv_t` 加字段该怎么加?
追加到结构体**末尾**, 且**不要**用 `#ifdef` 包起来。理由见 §9 第 3 条:
该结构体跨编译单元与预编译库共用, 布局必须固定。
功能开关只控制读写该字段的代码, 不控制字段本身是否存在。

### Q7. 为什么 `ipv6_gw` 只回显、不真的写 IPv6 默认路由?
写默认路由需要 ND6 router 状态参与, 当前未实现(见 §8 第 2 条)。
该字段只用于让 `netdrv.ipv6(...)` 读回用户设置过的网关。

### Q8. 怎么在 PC 上验证这个开关的两态?
先改 `bsp/pc/include/luat_conf_bsp.h` 那一行, 然后:

```powershell
cd bsp\pc
xmake                     # 关闭态建议先 xmake clean -a 做干净全量, 便于核对 warning
cd build\out
.\luatos-lua.exe ..\..\..\..\testcase\common\scripts\ ..\..\..\..\testcase\unit\net\netdrv_ipv6_basic\scripts\
```

开启态期望 `Total: 9 passed, 0 failed`; 关闭态期望套件自跳过而非报错。
两态都应做到零 error、零新增 warning。

### Q9. `net_lwip2_*` 的 IPv6 接口在关闭态还会存在吗?
会, 但都是退化实现。`net_lwip2.c` 在 `!(LWIP_IPV6 && defined(LUAT_USE_NETDRV_IPV6))`
时提供 `supported()->0`、`is_ready()->0`、`create_linklocal()->-1` 等 stub;
`luat_netdrv.c` 另外提供 GCC weak 定义, 供未链接 lwip2 适配层的构建兜底,
避免未解析符号。

