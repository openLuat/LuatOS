/* SPDX-License-Identifier: MIT
 * 版权和许可声明见 LICENSE。
 */
#ifndef LUAT_DHCPS_LWIP_H
#define LUAT_DHCPS_LWIP_H
#include "luat_dhcps.h"

#ifdef __cplusplus
extern "C" {
#endif

struct udp_pcb;
struct netif;
typedef uint64_t (*luat_dhcps_now_fn)(void *userdata);

typedef struct {
    luat_dhcps_t engine;
    struct udp_pcb *pcb;
    struct netif *netif;
    luat_dhcps_now_fn now;
    void *userdata;
} luat_dhcps_lwip_t;

/** 在 UDP/67 上启动已零初始化或已停止的实例。配置必须匹配
 * netif 的 IPv4 地址和掩码；now 返回单调时间秒数。返回 0 或 -1。
 * 所有调用均须在 lwIP 核心线程中或持有核心锁时执行。多网卡需要 SO_REUSE=1。
 * 调用方须保持实例、租约存储、netif 和 userdata 有效，直至停止。 */
int luat_dhcps_lwip_start(luat_dhcps_lwip_t *server, struct netif *netif,
                          const luat_dhcps_config_t *config,
                          luat_dhcps_lease_t *leases, size_t capacity,
                          luat_dhcps_now_fn now, void *userdata);

/** 同步解除接收回调、移除 PCB 并清除租约。
 * 此操作幂等。移除 netif、修改其地址或释放存储前必须先停止。 */
void luat_dhcps_lwip_stop(luat_dhcps_lwip_t *server);

#ifdef __cplusplus
}
#endif
#endif
