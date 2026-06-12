/*
 * luat_netdrv_lwip_compat.h
 *
 * LuatOS netdrv 跨 lwIP 实现的兼容层.
 *
 * 主要目的: 在某些厂商魔改过的 lwIP (例如合宙 Air8000 EC718HM 的 PLAT lwIP) 上,
 * 标准 ip4_input 的 "DHCP 单播救济块" 被加上了额外条件
 * (netif->netif_type 必须是 LAN_ETH_RNDIS / LAN_ETH_ECM), 导致 LuatOS netdrv
 * 注册的 netif (type 默认为 LWIP_NETIF_TYPE_INVALID=0) 永远命中不到救济块,
 * 收不到 DHCP 单播 OFFER/ACK.
 *
 * 解决办法: 在 netdrv 的以太网入口直接调用我们自己的 luat_netdrv_ip4_input,
 * 完成最小子集的 IPv4 入栈分发, 不依赖任何 PLAT 私有 API.
 *
 * 设计要点:
 *  - 仅供 LuatOS netdrv 注册的叶子 netif 使用(airlink wifi / 以太网网卡 等).
 *  - 不做多 netif 路由判定, 也不做 IPv4 转发 / CLAT / NAT64.
 *  - 全部分发依赖 lwIP 公开的 udp_input/tcp_input/raw_input/icmp_input.
 *  - 对 IP 分片包等不常见路径直接 fallback 给 PLAT 原版 ip4_input.
 */

#ifndef LUAT_NETDRV_LWIP_COMPAT_H
#define LUAT_NETDRV_LWIP_COMPAT_H

#include "lwip/pbuf.h"
#include "lwip/netif.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief LuatOS netdrv 专属的 ip4_input.
 *
 * 该函数实现 ip4_input 的核心子集, 仅服务 LuatOS netdrv 创建的叶子 netif.
 * 与标准 lwIP ip4_input 行为差异:
 *  - 不检查 netif IP 是否匹配, 默认 "包既然到了我这就接受".
 *    这正是为了让 DHCP 单播 OFFER/ACK 在 netif 还无 IP 阶段也能被接收.
 *  - 不做 ip4_forward / 转发表查询 / NAT.
 *  - 对带 IP options / 分片 / 异常 header 的包 fallback 给原版 ip4_input.
 *
 * @param p     收到的完整 IPv4 包(payload 指向 IP 头).
 * @param netif 收到该包的 netif.
 */
void luat_netdrv_ip4_input(struct pbuf *p, struct netif *netif);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_NETDRV_LWIP_COMPAT_H */