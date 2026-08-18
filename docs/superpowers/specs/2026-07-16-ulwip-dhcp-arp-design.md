# ulwip DHCP 客户端获取 IP 后发送 ARP 预热设计

## 背景与目标

ulwip（LuatOS 的 LwIP 适配层）使用自研 DHCP 客户端实现 `components/network/ulwip/src/ulwip_dhcp_client.c`。当前在 `DHCP_STATE_CHECK` 阶段拿到 ACK 后，直接调用 `netif_set_addr()` 设置地址并上报 `GOT_IP`，**不会主动发送任何 ARP 包**。

本设计在保持现有 DHCP 时序不变的前提下，在 IP 提交后追加两包 ARP：

1. **Gratuitous ARP**：通知同网段设备本机的 IP→MAC 映射，帮助交换机/其他主机及时刷新 ARP 缓存。
2. **网关 ARP request**：提前解析网关 MAC，避免上层第一个外网包因 ARP 解析而延迟或重传。

## 设计范围

### 修改文件

- `components/network/ulwip/src/ulwip_dhcp_client.c`

### 不修改的内容

- `components/ethernet/common/dhcp_client.c` 中的共享 DHCP 状态机 `ip4_dhcp_run()`。
- 不引入新的 DHCP 状态或定时器。
- 不做 ARP Probe / DAD（Duplicate Address Detection）。
- 不等待 ARP reply，不重试。

## 实现细节

在 `ulwip_dhcp_client_run()` 处理 `DHCP_STATE_CHECK` 的分支中，于 `netif_set_addr()` 之后、`dhcp->state = DHCP_STATE_WAIT_LEASE_P1` 之前插入：

```c
//  gratuitous ARP，通知局域网刷新本机 IP/MAC 映射
etharp_gratuitous(netif);
//  预热网关 MAC，避免上层首包出网卡顿
etharp_request(netif, &gw);
```

### API 说明

- `etharp_gratuitous(netif)` 是 LwIP 2.2 宏，定义在 `lwip/etharp.h`，展开为 `etharp_request(netif, netif_ip4_addr(netif))`。由于此时 `netif_set_addr()` 已生效，该请求的目标 IP 即为本机 IP，起到 gratuitous ARP 的作用。
- `etharp_request(netif, &gw)` 向网关 IP 发送 ARP request，收到 reply 后由 LwIP 自动填入 ARP 缓存。

### 错误处理

- 若 `etharp_gratuitous()` 或 `etharp_request()` 返回非 `ERR_OK`（如内存不足），**不阻塞 DHCP 流程**，仅打印 `LLOGW` 日志后继续进入 `WAIT_LEASE_P1` 并上报 `GOT_IP`。

## 风险与注意事项

1. **线程安全**：`ulwip_dhcp_client_run()` 在 NO_SYS=0 时通过 `tcpip_callback()` 在 LwIP tcpip 线程中执行，直接调用 LwIP ARP API 是安全的。
2. **网络负载**：仅增加两包 ARP，对网络负载影响可忽略。
3. **依赖关系**：仅依赖 LwIP 2.2 公开 API，无需启用 `LWIP_ACD`。

## 验证方案

1. 在 PC 模拟器（`bsp/pc`）下运行 ulwip DHCP 客户端。
2. 通过抓包工具或日志确认：DHCP ACK 之后、上层业务发包之前，出现以下两帧：
   - 源/目标 IP 均为本机 IP 的 ARP request（gratuitous ARP）。
   - 目标 IP 为网关 IP 的 ARP request。
3. 确认 `GOT_IP` 事件和后续网络业务不受影响。
