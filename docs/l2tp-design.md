# netdrv L2TPv2 客户端驱动设计文档

> 适用范围：在 LuatOS `netdrv` 框架下新增 L2TPv2（RFC 2661）客户端驱动（LAC）。
> 首期落地 PC 模拟器（`bsp/pc`），2026-10 完成 **Air1601 真机（CH390 外挂以太网）使能**
> 与真实运营商 LNS 互通验证，见 §8。

---

## 1. 背景与目标

LuatOS 需要在内网/办公网场景下提供「二层隧道 + PPP 拨号」的能力，典型形态是
接入企业 LNS（L2TP Network Server）获得内网 IP 并访问内网资源。

需求边界（与 lwip 自带 `pppol2tp.c` 的能力边界一致）：

- ✅ L2TPv2 客户端（LAC），PPP over L2TP（UDP 隧道）
- ✅ PPP 认证：PAP + CHAP(MD5) + **MS-CHAPv2**（RFC 2759，含双向认证）；
  可选 L2TP 隧道共享密钥认证（`l2tp_secret`）
- ❌ LNS（服务端）、L2TPv3、隧道切换、多隧道/多会话
- ❌ MPPE / EAP / CCP（LNS 强制加密时才需要，见 §6.5）

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
                 |   components/network/l2tp/src (核心)  |
                 |  - l2tp_client.c: 生命周期/定时器/传输 |
                 |  - l2tp_ctrl.c: 控制面 (SCCRQ..StopCCN,|
                 |    ns/nr 窗口, 定时重传)              |
                 |  - l2tp_ppp.c: PPP 数据面封装 + 状态回调|
                 +-------+---------------+------------+
                         |               |
            network_ctrl_t (UDP)    vendored lwIP PPP 栈
            luat_network_adapter    l2tp/src/ppp/*.c
                         |               |
                底层物理网卡(4G/WiFi/ETH)   ppp_pcb / netif
```

### 2.1 分层

1. **胶水层**（`luat_netdrv_l2tp.c`）：把 L2TP 客户端包装成标准 `luat_netdrv_t`
   驱动，负责配置拷贝、`LUAT_NETDRV_CTRL_UPDOWN` 控制、链路状态上报。
2. **客户端核心**（`components/network/l2tp/src/`，按协议层拆为三个文件）：
   - `l2tp_client.c`：生命周期/状态机/定时器/网络适配器传输
     （`l2tp_udp_send`、`l2tp_timeout`、重连退避、`l2tp_client_*` API）；
   - `l2tp_ctrl.c`：L2TPv2 控制面从 lwip22 `netif/ppp/pppol2tp.c` 移植，
     仅替换 UDP 收发为 `network_tx/network_rx`，去掉 `udp_pcb` 与传输
     netif 参数（线格式/AVP 构造解析、ns/nr 窗口、定时重传）；
   - `l2tp_ppp.c`：PPP 会话运行在 vendor 的 lwIP PPP 栈上，
     `struct link_callbacks` 的 `write/netif_output` 走 L2TP 数据封装，
     并处理 `ppp_status_cb` 链路状态回调。
   - 跨文件原型在 `components/network/l2tp/include/l2tp/`（`l2tp_ctrl.h` /
     `l2tp_ppp.h`），公共客户端 API 在 `l2tp/l2tp_client.h`。
3. **PPP 栈**（`components/network/l2tp/src/ppp/`）：lwIP 2.2.1
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
到 `components/network/l2tp/src/ppp/` 并配套两个移植补丁：

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
PAP_SUPPORT=1, CHAP_SUPPORT=1, MSCHAP_SUPPORT=1, EAP/CCP/MPPE/VJ/LQR=0,
PPP_MD5_RANDM=1,
PPP_IPV4_SUPPORT=(LWIP_IPV4), PPP_IPV6_SUPPORT=0, PPP_SERVER=0,
LWIP_USE_EXTERNAL_MBEDTLS=1, MEMP_NUM_PPP_PCB=1
```

MS-CHAPv2 额外需要三块密码学件，都由 mbedtls + 本地垫片解决（见 §3.5）：
DES（3DES 挑战应答 / NT 口令哈希）、SHA1（Authenticator Response）、
MD4（NT 口令哈希 —— **本仓库所有 mbedtls 版本都不带**，走
`src/ppp/luat_ppp_md4.c` 的 vendor 实现）。

配套提供 `components/network/l2tp/include/ppp_settings.h`：`lwip22/include/arch/cc.h`
无条件定义 `PPP_INCLUDE_SETTINGS_HEADER`，但仓库从未提供该 port 头文件
（PPP 此前从未编译），本文件为空实现（选项全部走 override 头）。

> 注意：这些宏只作用于 vendor PPP 文件与 L2TP 客户端文件，**不是全局宏**。
> 全局开启 `PPP_SUPPORT` 会触发 `lwip22/core/init.c` 的
> `#error "PPP_SUPPORT needs at least one of PPPOS_SUPPORT..."` 编译检查。

### 3.4 L2TP 控制面：自实现（`PPPOL2TP_SUPPORT=0`）

lwip 的 `pppol2tp.c` 与 `udp_pcb` 强耦合，且其头文件要求
`PPPOL2TP_SUPPORT=1`。本驱动把控制面逻辑平移到
`l2tp_ctrl.c`（常量、AVP 构造/解析、ns/nr 窗口、定时重传均照搬），
传输改为 adapter 调用，因此 vendor PPP 文件以 `PPPOL2TP_SUPPORT=0` 编译，
避免 `pppol2tp.c` 参与编译。

### 3.5 认证与隧道密钥

- `ppp_set_auth(ppp, PPPAUTHTYPE_ANY, user, passwd)`：PAP / CHAP-MD5 / MS-CHAPv2
  均可 —— 用哪种由**对端在 LCP ConfReq 里指定**，客户端只负责表达自己能做什么；
- MS-CHAPv2 的客户端代码本来就在 `chap-new.c` / `auth.c` / `lcp.c` 里，之前只是被
  `MSCHAP_SUPPORT 0` 编掉。打开后：
  - 能力广播：`CHAP_MDTYPE_SUPPORTED`（`ppp_impl.h`）自动含 `MDTYPE_MICROSOFT_V2`，
    `lcp.c` 把它装进 `ao->chap_mdtype`，对端要 0x81 时直接 ACK，不需要 NAK 往返；
  - 响应：`chapms2_make_response()` → PeerChallenge(16) | Reserved(8) |
    NT-Response(24) | Flags(1)，其中 NT-Response = 3×DES(ChallengeHash, NT-Pw-Hash)；
  - **双向认证**：客户端会校验 Success 里的 Authenticator Response
    （`chapms2_check_success`），算错即视为认证失败并断链 —— 这一点 mock LNS 侧
    有独立的 RFC 2759 实现做交叉验证（含 `--bad-auth-response` 负例）。
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
| `components/network/l2tp/include/l2tp/l2tp_client.h` | L2TP 客户端对外结构/API、协议常量 |
| `components/network/l2tp/include/l2tp/l2tp_ctrl.h` | 控制面跨文件原型（内部） |
| `components/network/l2tp/include/l2tp/l2tp_ppp.h` | PPP 胶水跨文件原型（内部） |
| `components/network/l2tp/src/l2tp_client.c` | 客户端核心（生命周期/定时器/传输/重连） |
| `components/network/l2tp/src/l2tp_ctrl.c` | 控制面（线格式/AVP/ns-nr 窗口/定时重传） |
| `components/network/l2tp/src/l2tp_ppp.c` | PPP 胶水（link_callbacks + 状态回调） |
| `components/network/netdrv/include/luat_netdrv_l2tp.h` | netdrv 胶水层头文件 |
| `components/network/l2tp/src/luat_netdrv_l2tp.c` | netdrv 胶水层（setup/ctrl/dhcp/debug/状态回调） |
| `components/network/l2tp/src/ppp/*.c` | vendored lwip 2.2.1 PPP 源码（12 个文件；含 MS-CHAPv2 的 `chap_ms.c` 与 `pppcrypt.c`） |
| `components/network/l2tp/src/ppp/luat_ppp_md4.c/.h` | MD4（MS-CHAPv2 必需，各版 mbedtls 都不带；BSD 许可，vendor 自 lwip polarssl 副本） |
| `components/network/l2tp/src/ppp/luat_ppp_opts_override.h` | PPP 编译选项覆盖 |
| `components/network/l2tp/include/ppp_settings.h` | lwip `PPP_INCLUDE_SETTINGS_HEADER` port 钩子 |
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

-- netdrv 核心（VPN 子模块已拆出为独立目录）
add_files(luatos .. "components/network/netdrv/**.c")

-- L2TP 子模块：头文件路径 + vendor PPP + 客户端按文件附加编译宏
add_includedirs(luatos .. "components/network/l2tp/include")
add_includedirs(luatos .. "components/network/l2tp/src/ppp")
add_files(luatos .. "components/network/l2tp/src/ppp/*.c",
          {defines = {"LUAT_L2TP_PPP_BUILD=1"}})
add_files(luatos .. "components/network/l2tp/src/l2tp_client.c",
          luatos .. "components/network/l2tp/src/l2tp_ctrl.c",
          luatos .. "components/network/l2tp/src/l2tp_ppp.c",
          {defines = {"LUAT_L2TP_PPP_BUILD=1"}})
add_files(luatos .. "components/network/l2tp/src/luat_netdrv_l2tp.c")
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

# 其余场景 (端口/flag 与 LUAT_L2TP_TEST 一一对应, 见该套件 scripts/main.lua 顶部):
#   --port 1702 --auth chap                                   (chap)
#   --port 1703 --reject-auth                                 (reject)
#   --port 1701 --drop-after 8                                (reconnect)
#   --port 1704 --auth mschapv2                               (mschapv2)
#   --port 1705 --auth mschapv2 --bad-auth-response            (mschapv2-bad)
#   --port 1706 --auth pap --secret tunnel-secret-123          (secret)
#   --port 1707 --auth pap --secret tunnel-secret-123          (secret-bad)
```

八个场景全部实测通过（`### OVERALL_PASS ###`）：

| 场景 | 验证点 |
|---|---|
| pap | 隧道建立 + PAP 认证 + IPCP 下发 192.168.8.2 + 隧道内 TCP echo |
| chap | CHAP-MD5 认证（挑战/响应校验）+ 同样链路验证 |
| reject | 密码错误 -> 认证失败、一直 not ready |
| reconnect | 会话中途断开 -> `IP_LOSE` -> 自动重连成功 |
| mschapv2 | MS-CHAPv2 认证：mock 侧用独立实现（pycryptodome MD4/DES/SHA1）重算 NT-Response 并校验，客户端再互验 Authenticator Response |
| mschapv2-bad | LNS 回**算错的** Authenticator Response -> 客户端必须拒绝建链（`chapms2_check_success`） |
| secret | L2TP 隧道认证（共享密钥）通过 + 隧道内 echo |
| secret-bad | 隧道密钥不匹配 -> LNS 回 StopCCN -> 一直 not ready |

> `mschapv2*` 场景需要 `pycryptodome`（`pip install pycryptodome`）；缺失时 mock 会在
> 启动阶段明确报错退出，不会静默降级成别的认证方式。
> mock 侧那套 MS-CHAPv2 已用 RFC 2759 §9.2 的四条测试向量自检过
> （NT-Hash / ChallengeHash / NT-Response / AuthenticatorResponse）。

回归：`netdrv_evt_pkg`（19/19）、`netdrv_lwip_intercept_basic`（3/3）通过；
PC 增量编译 `Build completed successfully`，无新增告警。

### 真实 LNS 联调用例（`testcase/unit/net/netdrv_l2tp_real_lns/`）

mock LNS 覆盖协议细节，另一套用例覆盖**与真实运营商 LNS 的互通**（PC + Air1601
都能跑，凭据走环境变量或 `/luadb/lns_secret.txt`，不入库）：隧道就绪 → IPCP 地址
→ 隧道内 TCP/HTTP 往返。2026-10 在 PC 与 Air1601(COM23) 上均 `### OVERALL_PASS ###`，
错误口令对照场景 `### OVERALL_FAIL ###`（证明不是空跑）。详见 §8。

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

1. ~~**硬件 BSP 使能**~~ **已完成（2026-10，Air1601/CCM4211）**：原担心
   `ip4_input` 等 lwIP 符号未导出——实测不成立，真机与 PC 共用
   `components/network/lwip22`，静态链接无符号白名单，`ip4_input` 直接可用，
   **不需要**改走 `luat_netdrv_ip4_input`。SDK 侧接线见 §8。
2. **IPCP DNS 下发**：PC 当前 `LWIP_DNS=0`，`ppp.c` 的 `sdns()` 未编译，
   IPCP 携带的 DNS 选项会被忽略（真机同）。后续可评估启用 `LWIP_DNS`
   或由驱动把 IPCP 协商出的 DNS 写入 `net_lwip2` 的 `set_dns_server`。
3. **LNS 域名支持**：`l2tp_remote_ip` 仅支持 IP 字面量；可通过传输 adapter
   的 DNS 能力扩展域名解析（同 OpenVPN 现状）。
4. **隧道认证自动化测试**：`l2tp_secret` 的 Challenge/Challenge-Response
   流程已实现，mock LNS 也支持 `--secret`，但当前四场景未覆盖，待补测试。
5. **认证/加密能力扩展**：~~MSCHAPv2~~、MPPE（CCP）、EAP。
   **MS-CHAPv2 已完成**（见 §3.5，客户端代码本来就具备，打开 `MSCHAP_SUPPORT`
   并补 `chap_ms.c/pppcrypt.c` + MD4 垫片即可）。
   仍未做的是 MPPE（隧道内加密）与 EAP：MPPE 还需 vendor `ccp.c/mppe.c`
   外加一份本地 RC4（本仓库各版 mbedtls 都无 ARC4），且 PAP+MPPE 不可能
   （密钥来自 NT 口令哈希）；触发条件是 LNS 把加密策略从"可选"改成"必需"。
   EAP 目前只会被 NAK 成 CHAP，纯 EAP 的 LNS 连不上。
6. **多实例**：当前按单会话设计（`MEMP_NUM_PPP_PCB=1`），多隧道/多会话、
   隧道切换未支持。
7. **资源释放细节**：配置字符串（用户名/密码/密钥）在客户端生命周期内保留，
   用户停止后不释放（便于再次启动）；PPP 会话若处于 `TERMINATE` 进行中，
   `ppp_free` 会等待状态归位，极端时序下可能保留 pcb 等待下一次 start 清理。
8. ~~**定时器预算**~~ **真机口径已修正**：`MEMP_NUM_SYS_TIMEOUT` 在真机上是
   **死代码**——`lwipopts.h` 里 `LWIP_TIMERS_CUSTOM=1`，`core/timeouts.c` 与
   SYS_TIMEOUT 内存池都不参与编译，定时器由
   `components/network/lwip22/port/luat_rtos/luat_rtos_lwip.c` 用 RTOS 定时器实现
   （堆分配，受 `LUAT_HEAP_SIZE` 约束）。真机侧必须满足的两个移植前提：
   - `sys_jiffies()` 必须由移植层提供（`LWIP_TIMERS_CUSTOM=1` 时 lwip 不自带；
     `ppp/magic.c` 用它做随机种子）——已补；
   - `sys_untimeout()` **不能是空实现**：`ppp_close()` 用它取消 holdoff 的
     `ppp_do_connect` 定时器，而 `ppp_free()` 随后会 `mem_free(pcb)`，空实现会让
     定时器打到已释放的 pcb 上（use-after-free，只有真机会走这条路）——已按
     "登记表 + id 寻址" 实现，见该文件 `sys_timeout/sys_untimeout` 注释。
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
- `testcase/unit/net/netdrv_l2tp_real_lns/`（真实 LNS 联调用例 + 协议探针/中继工具）

---

## 8. 真机（Air1601）使能与真实 LNS 互通（2026-10 实测）

### 8.1 客户现场与实测结论

客户给的 Windows 配置是「VPN 类型 = L2TP/IPsec + 数据加密 = 可选加密 +
身份验证 = PAP/CHAP/MS-CHAPv2」，LNS `58.213.164.4`。实测结论：

- 该 LNS **允许无 IPsec 的明文 L2TP**（单个裸 SCCRQ 32ms 内回 SCCRP，主机名
  `tietaIDC.VPNserver-4`），因此**不需要** IKEv1/ESP 传输模式；
- LNS 在 LCP ConfReq 中唯一要求的认证是 **CHAP alg=5（MD5）**，
  **不需要** MS-CHAPv2、**不需要** MPPE/CCP；
- 隧道 + PPP + IPCP 全部打通，隧道内 `/32` 地址 + 对端 `10.129.128.1`，
  隧道内 HTTP 往返正常。

即：**既有实现（PAP + CHAP-MD5）直接可用**。代价是隧道内数据不加密
（仅 CHAP-MD5 认证），若客户要求传输加密则需另做 IKEv1 + ESP 传输模式
（`docs/ipsec-design.md` §1 明确列为不做项，属重量级新功能）。

### 8.2 SDK 侧接线（跨仓库改动，`luatos-sdk-ccm42xx-gcc`）

`csdk/project/luatos/`：

1. `include/luat_conf_bsp.h`：加 `#define LUAT_USE_NETDRV_L2TP 1`
   （该开关在 LuatOS 仓库里只有 `bsp/pc` 定义过）。
2. `xmake.lua`：剔除 `lwip22/netif/ppp/**.c`（避免与 vendor 副本重复），并加
   `components/network/l2tp` 的 include + `src/ppp/*.c` + 三个客户端 TU
   （后两者附加 `LUAT_L2TP_PPP_BUILD=1`）+ `luat_netdrv_l2tp.c`。
   与 `bsp/pc/xmake.lua:955-963` 同款。
3. 真机固件体积：FLASH 6.54MB / 8MB（77.99%），链接通过。

### 8.3 真机测试链路上的三个坑

- **默认网卡必须钉住**：`luat_netdrv_l2tp.c` 在 `setup()` 时把
  `network_register_get_default()` 记为外层 UDP 传输网卡。Air1601 同时有
  mobile/wlan，不显式 `socket.dft(socket.LWIP_ETH)` 可能从 4G/WiFi 出去；
  且 netdrv 虚拟网卡注册后默认网卡会漂移成隧道自身。
  `testcase/common/scripts/netready.lua` 的 Air1601 CH390 分支已补
  `socket.dft(socket.LWIP_ETH)`，用例侧也做了兜底钉住。
- **传输网卡上线时序**：试运行中点 1.05s 就 `netdrv.setup(L2TP)`，而 CH390 的
  link/DHCP 到 1.74s 才好，客户端会打印 `transport offline, deferring start`
  并按退避重试，2s 后自愈——这是设计内行为，不是故障。
- **LuaDB 文件名上限 27 字节**（含 `.luac`）：长文件名的用例脚本会被
  `luatos-cli` 打包阶段直接拒绝，真机用例文件名要短。

### 8.4 真机测试跑法

```powershell
$CLI = "D:\github\luatos-cli\target\release\luatos-cli.exe"
$SOC = "D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\out\LuatOS-SoC_V1029_Air160X.soc"
& $CLI flash test --soc $SOC --port COM23 --baud 6000000 `
  --script D:\github\LuatOS\testcase\common\scripts `
  --script D:\github\LuatOS\testcase\unit\net\netdrv_l2tp_real_lns\scripts `
  --script <放 lns_secret.txt 的目录> `
  --timeout 150 --keyword "### OVERALL_PASS ###" --fail-keyword "### OVERALL_FAIL ###"
```
