# netdrv IKEv2/IPsec 客户端设计文档

> 适用范围：LuatOS `netdrv` 框架下的 IKEv2/IPsec 隧道模式客户端
> （ESP tunnel mode）。首期已在 PC 模拟器上对接真实 strongSwan 网关
> `ipsec.air32.cn`（strongSwan 5.9.13, Ubuntu 24.04 云主机）联调通过。

---

## 1. 目标与范围

在 netdrv 框架内新增 `netdrv.IPSEC` 虚拟网卡，实现：

- IKEv2 发起端（RFC 7296），服务器证书链校验 + 强制 EAP-MSCHAPv2；
- NAT-T（RFC 3948）：UDP 500 启动，探测到 NAT 后切换 4500；
- DPD 保活、CHILD_SA 到期重协商（CREATE_CHILD_SA 无 PFS）、
  IKE SA 到期全量重建；
- CP（Configuration Payload）下发虚拟 IPv4 + DNS；
- ESP 隧道模式（RFC 4303）AES-CBC-128/256 + HMAC-SHA1-96 /
  HMAC-SHA2-256-128，32 包反重放窗口，ESP-in-UDP(4500)。

首期明确不做：IKEv1、L2TP/IPsec、MOBIKE（网络切换走断线重连）、
ESP 传输模式、客户端证书认证、IPv6 隧道。

## 2. 文件布局

代码按用户要求拆分到 `components/network/netdrv/src/ipsec/`：

| 文件 | 说明 |
|---|---|
| `ipsec_crypto.h/.c` | PRF+/HMAC、DH modp2048、IKE/CHILD 密钥派生、AUTH 计算/验签、X.509 链+SAN 校验（内置 ISRG Root X1 + Let's Encrypt 2026 中间链） |
| `ipsec_esp.h/.c` | ESP 隧道封装/解封（AES-CBC + HMAC）、SPI 方向、32 包反重放 |
| `ipsec_ike.h/.c` | IKEv2 状态机：SA_INIT/AUTH/EAP/CREATE_CHILD_SA/INFORMATIONAL、payload 编解码、SK 加密、NAT-T 切换、DPD、重协商、虚拟 netif 与 adapter 收发 |
| `ipsec_vendor_md4.h/.c` | MD4（Apache-2.0, 从 mbedTLS 2.x vendor, 自包含） |
| `ipsec_vendor_chap_ms.h/.c` | MS-CHAPv2（BSD, 移植自 lwIP2.2 `chap_ms.c`），含 strongSwan 线格式与 RFC 3079 MSK 派生、RFC 2759 测试向量自检 |
| `luat_netdrv_ipsec.c` | netdrv 胶水层：setup/ctrl(UPDOWN)/dhcp(-1)/debug + 链路状态回调 |
| `include/luat_netdrv_ipsec.h` | 胶水层头文件 |

接入点：

- `luat_netdrv_drv.h`：`LUAT_NETDRV_IMPL_IPSEC 7`
- `luat_netdrv.h`：`luat_netdrv_ipsec_conf_t` + `conf->ipsec_conf`
- `luat_netdrv.c` / `luat_lib_netdrv.c`：setup 分发与 `ipsec_*` 参数解析
- `bsp/pc/xmake.lua`：ipsec 头文件搜索路径
- `bsp/pc/include/luat_conf_bsp.h`：`LUAT_USE_NETDRV_IPSEC 1`
- `bsp/pc/include/lwipopts.h`：`MEMP_NUM_SYS_TIMEOUT 30`
- `bsp/pc/port/luat_crypto_mini.c`：PC 模拟器 TRNG 每次调用重新播种

## 3. 架构与数据流

```
Lua (netdrv.setup / socket.*)
   |
   v
luat_netdrv_ipsec.c  (setup/ctrl/dhcp/debug, IP_READY/IP_LOSE 事件)
   |
   v
ipsec_ike.c  (IKEv2 状态机, tcpip 线程)
   |   netif (虚拟网卡, 全流量默认路由)
   |      | netif output -> ESP 封装 -> adapter UDP TX(4500)
   |      | adapter RX(4500) -> IKE(4字节零前缀) 或 ESP -> 内层 IP 注入
   |
   +-- network_ctrl_t (luat_network_adapter, 单 socket: 500 -> 4500)
```

- IKE 与 ESP 共用同一个 adapter UDP socket：先在 500 上完成
  IKE_SA_INIT，NAT 探测后切换到本地/远端 4500（RFC 3948 非 ESP
  marker 区分 IKE 与 ESP）。这是标准 NAT-T 形态，避免了双 socket
  同端口绑定的问题。
- 所有状态机工作经 `tcpip_callback_with_block` 汇聚到 tcpip 线程；
  adapter 回调只拷贝数据并投递，与 L2TP/OpenVPN 客户端一致。
- CP 下发虚拟 IP 后 `netif_set_addr` + `netif_set_default`，DNS 写入
  `network_set_dns_server`。

## 4. 协议要点与互操作细节

- 套件：IKE `aes256-sha256-modp2048, aes128-sha1-modp2048!`；
  ESP `aes256-sha256, aes128-sha1!`（无 PFS）。
- IKE SK 载荷：AES-CBC + HMAC；**ICV 只覆盖 IKE 报文本身**（strongSwan
  收到 4500 报文会先剥离 4 字节非 ESP marker 再校验）。
- AUTH：EAP 模式按 RFC 7296 §2.16 用 MSK 作为共享密钥；
  `"Key Pad for IKEv2"` 为 17 字节（不含 NUL）。
- MSK：按 strongSwan 的 RFC 3079 实现——
  `master=SHA1(HH|NT-Response|Magic1)`，
  `recv/send=SHA1(master[0:16]|0x00*40|Magic2/3|0xF2*40)`，
  `MSK=recv[0:16]|send[0:16]|0x00*32`。
- MS-CHAPv2 线格式采用 strongSwan/Windows 客户端格式：
  `opcode|id|ms_length|value_size|...`（区别于 RFC 2759 排版）。
- ESP SPI 方向：发起端**发送**用响应者分配的 SPI（SAr2），**接收**
  用自己提议的 SPI（SAi2）。
- 证书链：内置 ISRG Root X1 及 Let's Encrypt 2026 中间链
  （YE2 → ISRG Root YE → ISRG Root X2），SAN 校验 `ipsec.air32.cn`；
  mbedTLS 校验需传 `mbedtls_x509_crt_profile_default`，PEM 缓冲需
  NUL 结尾（mbedTLS 3.x 的 PEM 识别条件）。

## 5. 配置参考（Lua）

```lua
netdrv.setup(socket.LWIP_USER1, netdrv.IPSEC, {
    ipsec_remote_ip = "154.8.159.79",  -- 网关 IP（仅字面量）
    ipsec_remote_port = 500,           -- IKE 端口, 默认 500
    ipsec_username = "vpnuser",
    ipsec_password = "xxxx",
    ipsec_san = "ipsec.air32.cn",      -- 服务器 SAN 校验
    -- ipsec_ca_cert_pem = "-----BEGIN CERTIFICATE-----...", -- 可选自定义信任锚
    ipsec_mtu = 1400,
    ipsec_retry_enable = true,
    ipsec_retry_base_ms = 1000,
    ipsec_retry_max_ms = 60000,
})
```

## 6. 联调记录（2026-08-12, PC 模拟器 ↔ ipsec.air32.cn）

联调期间发现并修复的问题：

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| 1 | 网关对 IKE_SA_INIT 无响应 | Ni/NAT-D 载荷的 Next Payload 误用 notify 值(16388)而非载荷类型(41) | 改为 `IPSEC_PAYLOAD_NOTIFY` |
| 2 | IKE_AUTH 无响应, 网关日志 `message ID 16777216, expected 1` | msgid 以单字节写入 (`01 00 00 00`) 而非 4 字节大端 | `ike_put32(msg+20, msgid)` |
| 3 | 网关日志 `MAC verification failed` | mbedTLS 3 `aes_crypt_cbc` 会把最后一组密文写回 IV 缓冲, 覆盖了包内 IV | 用独立 IV 缓冲 |
| 4 | 网关日志 `MAC verification failed`（修复 3 后仍失败） | 4500 上 ICV 把 4 字节零前缀算进去了, 而 strongSwan 收到会先剥离 | ICV 只覆盖 IKE 报文 |
| 5 | `trust anchor parse failed -0x2180` | mbedTLS 3.x 仅当缓冲区 NUL 结尾才识别 PEM | 内嵌/用户 PEM 均保留 NUL 结尾 |
| 6 | `cert chain verify failed flags=0xFFFFFFFF` | `mbedtls_x509_crt_verify_with_profile` 的 profile 传 NULL 返回 BAD_INPUT_DATA | 传 `mbedtls_x509_crt_profile_default` |
| 7 | 服务器只发叶子证书, 链校验失败 | strongSwan `leftsendcert=always` 只发叶子；Let's Encrypt 2026 新链 | 内置 YE2/ISRG Root YE/ISRG Root X2 中间 CA |
| 8 | `server AUTH signature verification failed` | 裸 r\|s 转 DER 时长度公式少算 2 字节 | 修正 `total=6+r+s+pad` |
| 9 | 服务器 `INVALID_SYNTAX` 拒绝 EAP Identity 响应 | EAP 载荷构建后未 `p += plen`, 内层为空 | 修复三处 EAP 载荷 |
| 10 | `unhandled MS-CHAPv2 request opcode 1` | 用 RFC 2759 排版解析 strongSwan 的 Challenge | 按 strongSwan 线格式解析 |
| 11 | 最终 AUTH 被拒 | 内层 `"Key Pad for IKEv2"` 用 `sizeof`（含 NUL 18 字节） | 用 17 字节 |
| 12 | 最终 AUTH 被拒（修复 11 后仍失败） | MSK 的 master 用 `sizeof(inner)=79`（实际 67）；且 0x36/0x5C 填充与 strongSwan 的 0x00/0xF2 不符；32 字节 key 从 20 字节 digest 越界拷贝 | 按 strongSwan 实现重写 MSK 派生 |
| 13 | ESP 无回包, 网关 `XfrmInNoStates` | ESP SPI 方向反了（发送用了自己提议的 SPI） | 发送用 SAr2 的 SPI |
| 14 | 隧道 IP 与策略不匹配 | CP 的 IPv4 字节序（`ip4_addr_set_u32` 需先 `lwip_htonl`） | 恢复 `lwip_htonl(ike_get32())` |

服务器侧配合项（已处理，用户授权调试）：

- 云主机 `dirtyfrag.conf` 禁用 `esp4` 内核模块（`install esp4 /bin/false`），
  导致 XFRM SAD 安装失败（`netlink error: Requested type not found (93)`）：
  已注释该规则并加载 `esp4`/`xfrm_user`/`xfrm4_tunnel`；
- `ipsec.secrets` 私钥声明为 `: RSA` 但实际是 ECDSA P-384：
  已改为 `: ECDSA`；
- 联调后 `charondebug` 已恢复 `ike 2`，`esp=aes256-sha256, aes128-sha1!`
  已恢复原样。

## 7. 测试结果（PC 模拟器, testcase/unit/net/netdrv_ipsec_basic）

- `connect`：IKE_SA_INIT → 证书链+SAN 校验 → 服务器 AUTH 验签 →
  EAP-MSCHAPv2（含服务器 Authenticator Response 校验）→ 双端 AUTH →
  CP 下发虚拟 IP/DNS → 隧道上线 → 隧道内 TCP 到网关 SSH 收到 banner，
  **3 passed / 0 failed**；
- `badpass`：错误密码 → EAP 失败 → 不 ready，**通过**；
- `sanit`：错误 SAN → 证书校验拒绝 → 不 ready，**通过**。

## 8. 遗留与后续

- 硬件 BSP：需确认目标板 lwip 导出符号（`pbuf/netif/sys/ip4_input`）
  与 adapter 行为，并按验收清单在目标板重跑；
- 服务器 FORWARD 链的 IPsec 池 ACCEPT 规则与 `rightsourceip`
  段需按实际网络调整（当前云主机 iptables 规则与池配置不完全一致，
  隧道到网关本机可用，跨子网转发需核对）；
- `netdrv.debug` 会输出 IKE/ESP 帧日志（含 SK 明文转储仅调试用）。

## 9. 相关文档

- RFC 7296（IKEv2）、RFC 3948（NAT-T）、RFC 4303（ESP）、
  RFC 2759/3079（MS-CHAPv2/MSK）
- `docs/l2tp-design.md`（线程模型/胶水层/构建接线参考）
- `components/network/netdrv/src/luat_netdrv_l2tp_client.c` /
  `luat_netdrv_openvpn_client.c`（传输与 netif 参考）
