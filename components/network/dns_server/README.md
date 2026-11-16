# DNS 中继（专用 lwIP 后端）

支持多实例的 IPv4 UDP/TCP DNS 中继，采用 [MIT](LICENSE) 许可证。
平台适配层负责 WAN 发现和 ABI 兼容适配。

## API 与构建

包含 `include/luat_dns_server.h` 和 `include/luat_dns_server_lwip.h`。
`luat_dns_server_start(&config, &handle)` 返回 0 或负值的 lwIP 错误码；
`luat_dns_server_running(handle)` 返回 0/1；
`luat_dns_server_stop(&handle)` 无返回值，并清空调用方的句柄。
先将 config 清零，再设置 `lan`、`select_upstream`、`random` 和 `port`。
上游选择回调返回有效的 netif、最多两个服务器地址，以及可选的端口。
上游选择回调和安全熵源回调均在成功时返回 0。

编译 `src/luat_dns_server_packet.c` 和 `src/luat_dns_server_lwip.c`。
使用上游 lwIP 时，还需编译 `src/luat_dns_server_lwip_default.c`，并传入
`&luat_dns_server_lwip_default_port`。厂商版本构建时应排除此文件，
注入自己的移植层函数表。将 `include/` 加入头文件搜索路径。
通用源文件不需要 SDK 或 RNDIS 功能宏。后端依赖 lwIP 的 IPv4、UDP、TCP、
定时器、TCPIP 回调派发，以及 LuatOS 堆内存分配；它并非 POSIX 套接字后端。
报文解析器本身仅依赖标准 C，可在主机上单独测试。

| 配置项 | 配置为零时的默认值 |
| --- | --- |
| 监听端口/上游端口 | 53 |
| 未完成的 UDP 请求数 | 16（最大 128） |
| TCP 流数量 | 4（最大 64） |
| 延迟处理的 UDP 任务数 | UDP 请求数上限的两倍 |
| UDP 查询/响应最大长度 | 4096 字节（最小 17） |
| 重试 | 2000 毫秒；配置了第二个服务器时，向其重试一次 |
| TCP 空闲超时 | 15000 毫秒 |
| 定时器粒度 | 250 毫秒 |

WAN 标识、地址或服务器变化时，会取消已有请求和 TCP 流。TCP 使用第一个服务器，
在 pbuf 拆分或合并时保持基于长度前缀的 DNS 分帧状态，采用原子复制写入和背压，
并允许客户端在等待完整响应帧时发送 FIN。只有成功接收数据、收到 FIN 或建立连接
才会更新活动时间。各实例的 TCP 监听器必须绑定不同的本地地址/端口组合。

## 所有权与 SDK 移植层

所有公开 API 都必须在 **tcpip_thread 上执行，且不得处于原始输入/错误回调或
PCB/netif 链表遍历过程中**。其他上下文应通过投递命令来调用。
配置和移植层函数表会被复制。LAN 和回调参数必须保持有效直到服务停止，
销毁接口前必须先停止服务。后续访问 LAN 前会检查它是否仍在接口列表中，
以及索引和地址是否匹配；更换 LAN 必须重启服务。
选择回调返回的 WAN 指针仅在当前核心线程操作期间使用。

停止服务会取消定时器、解除回调、移除自身持有的 PCB，并释放排队的数据。
已投递的任务会保留内部存储直到派发；它们不能访问外部参数、netif 或替代实例。
应保持 TCPIP 回调队列运行，直到队列排空。停止后不得再通过句柄的其他副本访问实例。
SDK 启停封装仅投递携带索引的命令，在核心线程上查找当前 USB netdrv/netif；
邮箱投递失败时只记录日志，绝不改为同步执行。投递失败后，再次调用封装函数即可重试。

移植层钩子为 `udp_attach`、`udp_bind_netif` 和 `tcp_write_copy`：

- `udp_attach(NULL binding)` 必须同时解除接收钩子**和**释放后错误钩子。
- 接收到的 pbuf 所有权转交给后端。查询和响应路径都必须先将处理任务入队，
  再执行任何 PCB 移除操作，以保护 netdrv 过滤输入路径中的临时 PCB 链表。
- `binding.destroyed` 表示 SDK **已经释放** UDP PCB；它只将状态置为失效。
  关联端的清理需等 SDK 的链表遍历返回后再执行。
- SDK 适配层提供返回类型为 `int` 的 UDP 回调、由 `ENABLE_PSIF` 条件启用的
  释放后错误回调，以及扩展的复制式 `tcp_write` ABI。
- `tcp_write_copy` 必须原子地复制整个传入缓冲区，或返回 `ERR_MEM` 且不消耗
  其中任何数据。通用代码均不依赖厂商宏。

## 响应校验

每次 UDP 尝试都使用独立的 PCB、在 49152–65535 范围内独立随机选择的端口，
以及无冲突的随机事务 ID。重试时会同时更换端口和 ID。
获取熵失败或端口绑定尝试耗尽时，以 SERVFAIL 结束请求，不采用可预测的替代方案。
随机分配最多尝试 128 次。

响应必须匹配实际尝试的服务器/端口、事务代次/ID、QR/opcode，
以及规范化的问题域名、类型和类别。共享的纯解析器对标签、展开域名、指针和
问题字段进行边界检查，拒绝指向后续位置、头部、非标签位置以及形成循环的压缩引用。
仅接受一个问题；应答区段和附加区段原样中继，不作解析。
这是执行事务校验的中继，并非 DNSSEC 校验器或缓存。
调用方必须提供密码学安全的熵源；SDK 使用 `luat_crypto_trng`。

## 回归测试接入点

注入结果确定的上游选择/熵源回调，并在移植层钩子中捕获 UDP 绑定信息。
模拟 lwIP 适配层可暂存 `tcpip_callback_with_block` 任务和 `sys_timeout` 回调，
控制 `sys_now`，并跟踪堆内存、pbuf 和 PCB 的所有权。将 LAN 加入其 `netif_list`
（单 netif 的 lwIP 则设置 `netif_default`）。测试应覆盖查询和响应任务均已入队时
停止服务、重启后排空旧任务、双实例、SDK 释放后错误、WAN 变化、无效响应，
以及使用新 ID/端口的故障切换。
主要回归测试位于 `testcase/tools/network_servers/`。在 LuatOS 根目录运行
`python testcase/tools/network_servers/test_network_servers.py`。
该测试使用实际 lwIP 协议栈、虚拟 netif，以及行为确定的队列、时间和熵源钩子，
覆盖 UDP 故障切换、重启、堆内存清理和 TCP 半关闭转发。
这些测试不能替代固件网络测试。
