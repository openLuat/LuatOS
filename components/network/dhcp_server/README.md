# 可移植 DHCPv4 服务器

可移植的报文和租约引擎，配有基于原始 UDP 接口的后端，采用
[MIT](LICENSE) 许可证。本组件为独立以太网/Wi-Fi 局域网提供服务，
不实现 DHCP 客户端、中继、DNS 解析器、路由或 NAT。

## 文件与集成

| 文件 | 用途 |
| --- | --- |
| `include/luat_dhcps.h`、`src/luat_dhcps.c` | 纯 C99 报文和租约引擎；仅依赖标准 C 头文件 |
| `include/luat_dhcps_lwip.h`、`src/luat_dhcps_lwip.c` | 独立的 lwIP 原始接口传输后端；使用 Luat 日志 |
| `testcase/tools/network_servers/dhcp/run_host_tests.py`（相对于仓库根目录） | 主机测试；无需构建固件或网络权限 |

将 `include/` 加入头文件搜索路径。报文测试或使用其他传输方式时，
仅编译 `src/luat_dhcps.c`。lwIP 固件还需编译 `src/luat_dhcps_lwip.c`，
并提供 lwIP IPv4/UDP 和 Luat 日志支持。可移植引擎不会调用 lwIP、
网络适配器、时钟或内存分配器。

## 配置与报文 API

```c
luat_dhcps_t server = {0};
luat_dhcps_lease_t leases[4];
luat_dhcps_config_t config;
luat_dhcps_config_default(&config, 0xc0a80401u, 0xffffff00u, 4);
/* 可选：config.pool_start = 0xc0a80464u; config.pool_end = 0xc0a80467u; */
/* 可选：config.lease_seconds = 7200; */
/* 可选：config.router = 0xc0a80401u; config.dns[0] = 0xc0a80401u; */
int result = luat_dhcps_init(&server, &config, leases, 4);
/* result == 0 后，对每个收到的 DHCP UDP 负载执行： */
/* size_t n = luat_dhcps_reply(&server, in, in_len, out, out_capacity, now_seconds); */
/* 停止接收新的调用，然后执行： */
luat_dhcps_deinit(&server);
```

- 所有配置和租约地址均为主机序 IPv4 数值，例如 `192.168.4.1 = 0xc0a80401`；
  网络序的 `in_addr` 或 lwIP 地址值必须先转换。
- 默认配置：租期 3600 秒，从子网首个可用地址开始并跳过服务器地址，
  不发送路由器选项（3）和 DNS 选项（6），仅提供本地局域网。
  客户端容量由调用方的配置和租约存储决定。
- 地址池的两个端点必须同时设置，或同时保持为零。范围包含两端，
  排除服务器、网关和 DNS 的池内地址后必须至少有 `client_count` 个可用地址。
  仅管理其中前 `client_count` 个地址，每个地址对应一个租约槽位。
  不接受网络地址、广播地址和非连续掩码；支持 /8 至 /30 掩码，
  且地址空间必须足以容纳服务器和客户端。
- `lease_seconds` 必须非零。`router` 非零时必须是服务子网内的可用地址。
  最多可提供两个单播 DNS 地址（不必位于该子网内）；值为零的条目会被省略。
  通告这些选项不会创建路由器或解析器，且仅在配置后才发送这些选项。
- `luat_dhcps_init` 返回 0 或 -1。配置无效时，服务器和存储保持不变。
  配置会被复制。存储容量以 `luat_dhcps_lease_t` 元素个数计，
  必须至少为 `client_count`。
- `luat_dhcps_reply` 接受 240–1500 字节的请求，输出缓冲区须至少为
  `LUAT_DHCPS_REPLY_SIZE`（300）字节，返回 300 或零。零表示无响应
  （包括成功处理 RELEASE/DECLINE）。输入和输出不可重叠。
  输出缓冲区不足时会拒绝处理，且不改变租约状态。
- `now` 使用单调时间，单位为**秒**，不得使用日历时间；同一实例的所有调用
  须使用相同时间基准。OFFER 预留和被拒绝地址的隔离期均为 60 秒。
  过期租约在处理报文时惰性回收。
- 支持 DISCOVER/OFFER、REQUEST/ACK/NAK、续租/重新绑定、RELEASE、DECLINE 和
  INFORM。仅支持以太网 MAC 标识。忽略中继报文（`giaddr`/hops）、
  BOOTP 选项复用、格式错误或截断的选项、重复的关键选项，以及指定其他服务器的请求。
  未实现 Client-id、持久化、地址冲突探测和 DHCPv6。

## 线程所有权与生命周期

每个实例及其租约数组归属于一个执行上下文。配置、报文处理和清理操作必须串行执行；
引擎内部不加锁。使用独立存储的不同实例可独立运行。
服务器和租约字段只能由其所有者访问，运行期间不得直接修改。

首次使用前将实例零初始化。只能初始化未运行的实例。重新配置、移动或释放
存储前，须停止报文投递并反初始化。`luat_dhcps_deinit` 会清除所管理的租约条目
和实例；可安全重复调用。反初始化后收到的报文不会产生响应。
纯引擎不存在后台任务、定时器、堆内存分配或尚未完成的回调。

## lwIP 后端

```c
static luat_dhcps_lwip_t lan_server; /* 已零初始化 */
static luat_dhcps_lease_t lan_leases[4];
/* now_cb(userdata) 返回 uint64_t 类型的单调时间秒数。 */
/* 设置 netif 的 IPv4 地址和掩码后，在持有 TCP/IP 核心锁时执行： */
/* luat_dhcps_lwip_start(&lan_server, netif, &config, lan_leases, 4, now_cb, userdata); */
/* 移除 netif 或修改其地址前，仍在持有核心锁时执行： */
/* luat_dhcps_lwip_stop(&lan_server); */
```

启动、接收和停止操作必须在 lwIP 核心线程中或持有核心锁时执行。
在关闭 lwIP DHCP 客户端的构建上，须在 `lwipopts.h` 配置
`LWIP_IP_ACCEPT_UDP_PORT(port)` 接受网络序目的端口 67，以接收首次取址的广播。
时钟回调在该上下文中同步执行，不得阻塞或重入服务器。
时钟回调可使用 `luat_mcu_tick64_ms()/1000`。使用 32 位时钟的平台
必须先处理回绕并扩展计数，再转换为秒。后端不使用定时器。

配置必须匹配 netif 的 IPv4 地址和掩码。在停止之前，实例、租约存储、
回调 userdata 和 netif 必须保持有效且位置不变。每个 netif 使用一个服务器。
每个实例拥有自己的 PCB 和接收回调；多个 netif 同时运行时，lwIP 须配置
`SO_REUSE=1`，以便多次绑定 UDP/67。未启用时，如果 UDP/67 已被占用，
启动将返回 -1。后端会在支持时设置 REUSEADDR，并将各 PCB 绑定到对应 netif。

对已运行的实例再次启动会失败，且不修改实例。分配或绑定失败时，
会移除 PCB 并重置实例和租约，允许重试。停止操作会同步解除接收回调、
移除 PCB 并清除状态，且具备幂等性。停止返回后，不再有延迟释放的资源所有权。

仅处理所属 netif 上收到的、来自 UDP/68 的请求。链式 pbuf 会复制到
容量固定为 1500 字节的局部缓冲区，然后释放。响应从同一 netif 发往 UDP/68：
NAK 或广播标志会强制广播；否则，非零 `ciaddr` 使用单播，
初始 OFFER/ACK 使用广播。接收路径在核心线程栈上使用约 1.8 KiB 的报文缓冲区。
响应分配或发送失败不会回滚地址预留；客户端仍可重传，租约按正常规则到期。

## 验证

在 LuatOS 根目录执行：

```text
python testcase/tools/network_servers/dhcp/run_host_tests.py
```

使用 `--sdk C:/path/to/sdk` 可同时编译并测试受支持的 SDK 适配层，
也可在对应 SDK 目录中运行 `python -m unittest tests.test_dhcps`。
通过 `--cc` 或 `CC` 选择兼容 GCC 的编译器。构建使用 C11，
并启用 `-Wall -Wextra -Werror -pedantic`。
可执行文件存放于临时目录，退出时删除。

测试覆盖仅本地局域网的默认配置和显式选项、地址池、租约到期/耗尽/续租、
RELEASE/DECLINE/INFORM、格式错误或截断的报文、输出容量不足、实例隔离、
重新启动和启动失败清理。后端测试使用真实 LuatOS lwIP 头文件和 UDP/pbuf
传输测试替身，注入分配、复制、绑定和发送失败，检查响应路由和 pbuf 所有权，
并覆盖 `SO_REUSE` 的两种编译配置。这些测试不能替代固件或真实网络验收测试。
