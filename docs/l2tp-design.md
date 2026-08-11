# netdrv L2TPv2 客户端驱动设计文档

> 适用范围：在 LuatOS `netdrv` 框架下新增 L2TPv2（RFC 2661）客户端驱动（LAC），
> 当前首期落地 PC 模拟器（`bsp/pc`），硬件 BSP 按需开启 `LUAT_USE_NETDRV_L2TP`。

---

## 1. 背景与目标

LuatOS 需要在内网/办公网场景下提供「二层隧道 + PPP 拨号」的能力，典型形态是
接入企业 LNS（L2TP Network Server）获得内网 IP 并访问内网资源。

需求边界（与 lwip 自带 `pppol2tp.c` 的能力边界一致）：

- ✅ L2TPv2 客户端（LAC），PPP over L2TP（UDP 隧道）
- ✅ PPP 认证：PAP + CHAP(MD5)；可选 L2TP 隧道共享密钥认证（`l2tp_secret`）
- ❌ LNS（服务端）、L2TPv3、隧道切换、多隧道/多会话
- ❌ MSCHAPv2 / MPPE / EAP / CCP

核心约束：**外层 UDP 传输一律走 LuatOS network adapter**（`network_ctrl_t` UDP
模式，与 OpenVPN 客户端一致），不直接创建 lwip `udp_pcb`。这样 VPN 虚拟网卡与
底层物理网卡（4G/WiFi/ETH/CH390H）完全解耦，底层可以是任意 netdrv 适配器。

---

## 2. 总体设计

```
                 Lua 脚本 (netdrv.setup / netdrv.ready / socket.*)
                                    |
                 +------------------v------------------+
                 |        luat_netdrv_l2tp.c (胶水层)     |
                 |  setup/ctrl(UPDOWN)/dhcp/debug        |
                 |  PPP 状态回调 -> net_lwip2 链路状态 +    |
                 |  IP_READY / IP_LOSE 事件               |
                 +------------------+------------------+
                                    |
                 +------------------v------------------+
                 |    luat_netdrv_l2tp_client.c (核心)   |
                 |  - L2TPv2 控制面 (SCCRQ..StopCCN,     |
                 |    ns/nr 窗口, 定时重传)              |
                 |  - PPP 数据面封装 (L2TP data header)  |
                 |  - 重连退避 / 传输在线检测             |
                 +-------+---------------+------------+
                         |               |
            network_ctrl_t (UDP)    vendored lwIP PPP 栈
            luat_network_adapter    netdrv/src/ppp/*.c
                         |               |
                底层物理网卡(4G/WiFi/ETH)   ppp_pcb / netif
```

### 2.1 分层

1. **胶水层**（`luat_netdrv_l2tp.c`）：把 L2TP 客户端包装成标准 `luat_netdrv_t`
   驱动，负责配置拷贝、`LUAT_NETDRV_CTRL_UPDOWN` 控制、链路状态上报。
2. **客户端核心**（`luat_netdrv_l2tp_client.c`）：
   - L2TPv2 控制面从 lwip22 `netif/ppp/pppol2tp.c` 移植，仅替换 UDP 收发为
     `network_tx/network_rx`，去掉 `udp_pcb` 与传输 netif 参数；
   - PPP 会话运行在 vendor 的 lwIP PPP 栈上，`struct link_callbacks` 的
     `write/netif_output` 走 L2TP 数据封装。
3. **PPP 栈**（`components/network/netdrv/src/ppp/`）：lwIP 2.2.1
   `ppp.c/lcp.c/ipcp.c/auth.c/fsm.c/upap.c/chap-new.c/chap-md5.c/magic.c/utils.c`
   的 vendor 副本（保留 BSD 许可头，注明来源），由构建系统按需编译。

### 2.2 线程模型

- `create/connect/close` 与 `ppp_input` 的投递统一 marshal 到 lwip core 线程
  （`tcpip_callback_with_block`，模式同 WG 驱动的 `exec_netif_add`）；
- network adapter 回调（运行在 adapter 任务/Lua 主线程）内**只做数据拷贝**，
  通过 `tcpip_callback` 投递给 tcpip 线程，PPP 状态机绝不在 adapter 线程执行；
- `transport_err` 标志由 adapter 回调置位，由 500ms 周期定时器（tcpip 线程）
  消费，避免跨线程直接操作 PPP 状态机。

### 2.3 就绪信号

PPP 的 `sifup()` 在 `np_up()` 把 phase 推进到 `PPP_PHASE_RUNNING` **之前**就会
回调 `link_status_cb(PPPERR_NONE)`，因此驱动的 ready 判定使用 `ppp->if4_up`
（`sifup` 内部先置位再回调），而不是 phase==RUNNING，否则会出现一次误报
`IP_LOSE` 且不再上报 `IP_READY` 的竞态。

---

## 3. 方案选择与取舍

### 3.1 传输层：network adapter UDP 而非 lwip `udp_pcb`

| 方案 | 结论 |
|---|---|
| 直接创建 lwip `udp_pcb` 走底层 netif | 与 4G/WiFi/ETH 等 LuatOS 自有适配器耦合，需要额外的 netif 路由/ARP 处理，硬件差异大 |
| `network_ctrl_t` UDP（本方案） | 与 OpenVPN 客户端一致，底层网卡即插即用；天然支持「LNS 从随机源端口应答」（posix 适配器不 connect UDP socket） |

代价：多一次 adapter 层数据拷贝，VPN 隧道吞吐受 adapter 缓冲限制
（`network_tx/rx` 单包缓冲，L2TP 数据面当前使用 1600B 栈缓冲）。

### 3.2 PPP 栈：vendor lwip22 源码 vs 自己实现

lwip22 自带完整的 `ppp.c` 系列（LCP/IPCP/PAP/CHAP/FSM/魔法数），直接 vendor
到 `netdrv/src/ppp/` 并配套两个移植补丁：

1. **`ppp_pcb` 改用 `mem_malloc/mem_free`**：本仓库 lwip22 的 `memp_std.h`
   裁剪掉了 PPP/PPPOL2TP 内存池，vendor 副本内自行 `LWIP_MEMPOOL_DECLARE`
   可以编译，但为减少静态池开销并贴合本仓库约定，改为堆分配。
2. **MD5 走外部 mbedTLS**：`LWIP_USE_EXTERNAL_MBEDTLS=1` 把 `lwip_md5_*`
   映射到 LuatOS 已有 mbedtls（`MBEDTLS_MD5_C` 在 PC 与硬件配置均已启用），
   不再编译 lwip 内嵌 PolarSSL 副本。

### 3.3 编译选项覆盖：`luat_ppp_opts_override.h`

`bsp/pc/include/lwipopts.h` 写死 `PPP_SUPPORT 0`，且会**无条件重定义**，因此
per-file 命令行宏会被覆盖；同时 `ppp_opts.h` 的 `#if PPP_SUPPORT` 块在 override
生效之前求值（其中定义的 FSM/UPAP/CHAP/LCP 超时、`MAXNAMELEN/MAXSECRETLEN`、
`PPP_MRU`、`PPP_IPV4_SUPPORT` 等全部缺失）。

解决办法：xmake 仅对 vendor PPP 文件与 L2TP 客户端文件附加
`LUAT_L2TP_PPP_BUILD=1`，并在 `ppp_opts.h` 之后强制 include
`luat_ppp_opts_override.h`，统一恢复特性集：

```
PPP_SUPPORT=1, PPPOL2TP/PPPOS/PPPOE=0, LWIP_PPP_API=0,
PAP_SUPPORT=1, CHAP_SUPPORT=1, MSCHAP/EAP/CCP/MPPE/VJ/LQR=0,
PPP_IPV4_SUPPORT=(LWIP_IPV4), PPP_IPV6_SUPPORT=0, PPP_SERVER=0,
LWIP_USE_EXTERNAL_MBEDTLS=1, MEMP_NUM_PPP_PCB=1
```

配套提供 `netdrv/include/ppp_settings.h`：`lwip22/include/arch/cc.h`
无条件定义 `PPP_INCLUDE_SETTINGS_HEADER`，但仓库从未提供该 port 头文件
（PPP 此前从未编译），本文件为空实现（选项全部走 override 头）。

> 注意：这些宏只作用于 vendor PPP 文件与 L2TP 客户端文件，**不是全局宏**。
> 全局开启 `PPP_SUPPORT` 会触发 `lwip22/core/init.c` 的
> `#error "PPP_SUPPORT needs at least one of PPPOS_SUPPORT..."` 编译检查。

### 3.4 L2TP 控制面：自实现（`PPPOL2TP_SUPPORT=0`）

lwip 的 `pppol2tp.c` 与 `udp_pcb` 强耦合，且其头文件要求
`PPPOL2TP_SUPPORT=1`。本驱动把控制面逻辑平移到
`luat_netdrv_l2tp_client.c`（常量、AVP 构造/解析、ns/nr 窗口、定时重传均照搬），
传输改为 adapter 调用，因此 vendor PPP 文件以 `PPPOL2TP_SUPPORT=0` 编译，
避免 `pppol2tp.c` 参与编译。

### 3.5 认证与隧道密钥

- `ppp_set_auth(ppp, PPPAUTHTYPE_ANY, user, passwd)`：PAP/CHAP-MD5 均可；
- `l2tp_secret` 非空时按 RFC 2661 在 SCCRQ/SCCRP/SCCCN 中携带
  Challenge / Challenge-Response AVP（MD5(消息类型|secret|challenge)）。
- 认证选项由**对端**在 LCP ConfReq 中提出：lwip 客户端的 LCP ConfReq 本身
  不携带 auth 选项（`lcp_addci` 使用 gotoptions，客户端侧该位不置位），
  因此 LNS 必须主动要求认证（真实 LNS 行为一致）。

### 3.6 断线检测与自动重连

- **PPP 层**：LCP keepalive（3s 间隔、3 次失败）检测静默断线（对端不响应）；
  对端 StopCCN 在 DATA 阶段不主动断开（沿用 pppol2tp 语义），由 keepalive 兜底。
- **传输层**：`EV_NW_RESULT_CLOSE`/`Param1!=0` 置 `transport_err`，500ms 周期
  定时器消费并触发重连。
- 重连策略：指数退避（base 1s，max 60s，可配置），传输离线时按 base 轮询；
  用户主动 `CTRL_UPDOWN=0` 不重连。
- 在线判定使用 setup 时捕获的 `transport_index`，而非运行时默认 adapter：
  netdrv 虚拟网卡注册后 `network_register_get_default()` 会变成 USERx 自身，
  若用运行时默认值会导致「传输离线」误判。

### 3.7 数据面 MTU 与缓冲

PPP MRU 默认 1450（`L2TP_DEFAULT_MTU`，可用 `l2tp_mtu` 配置）；L2TP 数据头 6B
（flags + tunnel id + session id）。发送侧把 pbuf 拼成扁平缓冲后走
`network_tx`（1600B 栈缓冲），接收侧同样扁平缓冲 -> pbuf -> `ppp_input`。

---

## 4. 文件与构建接线

### 4.1 新增/修改文件

| 文件 | 说明 |
|---|---|
| `components/network/netdrv/include/luat_netdrv_l2tp_client.h` | L2TP 客户端对外结构/API、协议常量 |
| `components/network/netdrv/src/luat_netdrv_l2tp_client.c` | 客户端核心（控制面 + 数据面 + 重连） |
| `components/network/netdrv/include/luat_netdrv_l2tp.h` | netdrv 胶水层头文件 |
| `components/network/netdrv/src/luat_netdrv_l2tp.c` | netdrv 胶水层（setup/ctrl/dhcp/debug/状态回调） |
| `components/network/netdrv/src/ppp/*.c` | vendored lwip 2.2.1 PPP 源码（10 个文件） |
| `components/network/netdrv/src/ppp/luat_ppp_opts_override.h` | PPP 编译选项覆盖 |
| `components/network/netdrv/include/ppp_settings.h` | lwip `PPP_INCLUDE_SETTINGS_HEADER` port 钩子 |
| `components/network/netdrv/include/luat_netdrv.h` | `luat_netdrv_l2tp_conf_t` + `conf.l2tp_conf` |
| `components/network/netdrv/include/luat_netdrv_drv.h` | `LUAT_NETDRV_IMPL_L2TP 6` + setup 声明 |
| `components/network/netdrv/src/luat_netdrv.c` | setup 分发新增 L2TP 分支 |
| `components/network/netdrv/binding/luat_lib_netdrv.c` | `l2tp_*` 配置解析 + `netdrv.L2TP` 常量 |
| `bsp/pc/include/luat_conf_bsp.h` | `LUAT_USE_NETDRV_L2TP 1` |
| `bsp/pc/include/lwipopts.h` | `MEMP_NUM_SYS_TIMEOUT` 17->24（PPP/L2TP 定时器预算） |
| `bsp/pc/xmake.lua` | lwip22 PPP 源码剔除 + vendor PPP 编译 |
| `testcase/unit/net/netdrv_l2tp_basic/` | 测试套件 + Python mock LNS |

### 4.2 xmake 接线要点（`bsp/pc/xmake.lua`）

```lua
-- 剔除 lwip22 自带 PPP（避免与 vendor 副本重复编译）
remove_files(lwip_path .. "netif/ppp/**.c")

-- netdrv 源码排除 src/ppp（单独带宏编译）
add_files(luatos .. "components/network/netdrv/**.c|src/ppp/**.c")
add_includedirs(luatos .. "components/network/netdrv/src/ppp")

-- vendor PPP + L2TP 客户端按文件附加编译宏
add_files(luatos .. "components/network/netdrv/src/ppp/*.c",
          {defines = {"LUAT_L2TP_PPP_BUILD=1"}})
add_files(luatos .. "components/network/netdrv/src/luat_netdrv_l2tp_client.c",
          {defines = {"LUAT_L2TP_PPP_BUILD=1"}})
add_files(luatos .. "components/network/netdrv/src/luat_netdrv_l2tp.c")
```

### 4.3 Lua 用法

```lua
netdrv.setup(socket.LWIP_USER1, netdrv.L2TP, {
    l2tp_remote_ip = "10.0.0.1",   -- 必填，LNS IP（仅 IP 字面量，同 OpenVPN）
    l2tp_remote_port = 1701,        -- 默认 1701
    l2tp_username = "user",         -- 可选
    l2tp_password = "pass",         -- 可选
    l2tp_secret = nil,              -- 可选，L2TP 隧道共享密钥
    l2tp_mtu = 1450,                -- 可选，默认 1450
    l2tp_retry_enable = true,       -- 可选，失败自动重连
    l2tp_retry_base_ms = 1000,
    l2tp_retry_max_ms = 60000,
})
-- 就绪判断沿用 netdrv.ready(id) 与 IP_READY/IP_LOSE 事件
-- netdrv.dhcp 对该网卡返回 -1（IP 由 IPCP 下发）
```

---

## 5. 测试方案

PC 模拟器 + Python mock LNS（`testcase/unit/net/netdrv_l2tp_basic/mock_lns.py`）：

```bash
# pap 场景
python testcase/unit/net/netdrv_l2tp_basic/mock_lns.py --port 1701 --auth pap --log &
LUAT_L2TP_TEST=pap build/out/luatos-lua.exe \
    ../../testcase/common/scripts/ ../../testcase/unit/net/netdrv_l2tp_basic/scripts/

# chap / reject / reconnect 场景分别用：
#   --port 1702 --auth chap          (LUAT_L2TP_TEST=chap)
#   --port 1703 --reject-auth        (LUAT_L2TP_TEST=reject)
#   --port 1701 --drop-after 8       (LUAT_L2TP_TEST=reconnect)
```

四个场景均已实测通过（`### OVERALL_PASS ###`）：

| 场景 | 验证点 |
|---|---|
| pap | 隧道建立 + PAP 认证 + IPCP 下发 192.168.8.2 + 隧道内 TCP echo |
| chap | CHAP-MD5 认证（挑战/响应校验）+ 同样链路验证 |
| reject | 密码错误 -> 认证失败、一直 not ready |
| reconnect | 会话中途断开 -> `IP_LOSE` -> 自动重连成功 |

回归：`netdrv_evt_pkg`（19/19）、`netdrv_lwip_intercept_basic`（3/3）通过；
PC 增量编译 `Build completed successfully`，无新增告警。

### mock LNS 实现要点（实测中踩过的坑，写在这里供后续参考）

- 每端第一条控制消息 NS 从 **0** 开始（SCCRP 的 NS 必须为 0）；
- ZLB 不消耗 NS 槽位：其 NS 与下一条真实消息相同，接收方不推进 `peer_ns`；
- 数据包隧道/会话 ID 必须用**客户端分配**的 ID（lwip 按 `remote_*_id` 校验）；
- LCP/IPCP 是对称协议：服务端必须发送自己的 ConfReq，否则客户端 FSM 停在
  ACKRCVD 并重传；
- LCP Echo-Reply 必须携带**服务端自己的 magic**，lwip 会拒绝携带自身 magic
  的 Echo-Reply（视为回环）；
- CHAP 校验用的 secret 是 PPP 密码（客户端 `settings.passwd`），与 L2TP 隧道
  `l2tp_secret` 无关；
- IPCP ConfNak 的 length 字段必须等于实际负载长度（含 DNS 选项时容易写错，
  会导致客户端只解析到部分选项）。

---

## 6. 尚待完善之处

1. **硬件 BSP 使能**：首期只落地 PC。硬件 BSP 需要确认 lwip 导出
   `pbuf/netif/sys/ip4_input` 等符号；若未导出 `ip4_input`，在
   `LUAT_USE_NETDRV_LWIP_ARP` 下把 vendor `ppp.c` 的调用改走
   `luat_netdrv_ip4_input`。硬件侧建议在正式发布前跑一遍 mock LNS 验证。
2. **IPCP DNS 下发**：PC 当前 `LWIP_DNS=0`，`ppp.c` 的 `sdns()` 未编译，
   IPCP 携带的 DNS 选项会被忽略。后续可评估启用 `LWIP_DNS` 或由驱动把
   IPCP 协商出的 DNS 写入 `net_lwip2` 的 `set_dns_server`。
3. **LNS 域名支持**：`l2tp_remote_ip` 仅支持 IP 字面量；可通过传输 adapter
   的 DNS 能力扩展域名解析（同 OpenVPN 现状）。
4. **隧道认证自动化测试**：`l2tp_secret` 的 Challenge/Challenge-Response
   流程已实现，mock LNS 也支持 `--secret`，但当前四场景未覆盖，待补测试。
5. **认证/加密能力扩展**：MSCHAPv2、MPPE（CCP）、EAP 需要额外 vendor
   `chap_ms.c/ccp.c/mppe.c/eap.c` 并调整编译选项，属后续需求。
6. **多实例**：当前按单会话设计（`MEMP_NUM_PPP_PCB=1`），多隧道/多会话、
   隧道切换未支持。
7. **资源释放细节**：配置字符串（用户名/密码/密钥）在客户端生命周期内保留，
   用户停止后不释放（便于再次启动）；PPP 会话若处于 `TERMINATE` 进行中，
   `ppp_free` 会等待状态归位，极端时序下可能保留 pcb 等待下一次 start 清理。
8. **定时器预算**：`MEMP_NUM_SYS_TIMEOUT` 由 17 提到 24 以容纳
   PPP/L2TP 的 LCP-FSM + LCP-Echo + 认证 + IPCP-FSM + L2TP 控制/周期定时器；
   硬件侧若同时跑 OpenVPN/WG，需按实际固件核对预算。
9. **CI 集成**：mock LNS 依赖本机 UDP 端口，目前是手工编排；后续可封装成
   CI job（起 LNS -> 跑模拟器 -> 校验 OVERALL_PASS）。
10. **文档与 API 注释**：`luat_lib_netdrv.c` 已补充 `netdrv.L2TP` 用法注释，
    建议后续在 `script/` 侧补充完整 usage.md/示例。

---

## 7. 相关文档

- `components/network/lwip22/netif/ppp/pppol2tp.c`（控制面移植来源）
- `components/network/lwip22/include/netif/ppp/ppp_opts.h`（选项语义）
- RFC 2661（Layer Two Tunneling Protocol "L2TP"）
- `testcase/unit/net/netdrv_l2tp_basic/mock_lns.py`（测试用 LNS 参考实现）
