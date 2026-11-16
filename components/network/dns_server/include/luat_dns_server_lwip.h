/* SPDX-License-Identifier: MIT
 * Copyright (c) 2019-2026 openLuat & AirM2M
 */
#ifndef LUAT_DNS_SERVER_LWIP_H
#define LUAT_DNS_SERVER_LWIP_H
#include "luat_dns_server.h"
#include "lwip/udp.h"
#include "lwip/tcp.h"

#ifdef __cplusplus
extern "C" {
#endif

/** 由后端持有的稳定存储，在解除关联或移除前一直有效。
 * receive 接管 p。只能在 SDK 已释放 pcb 之后调用 destroyed；
 * 它使句柄失效，并将其余清理工作延后到链表遍历结束后执行。
 */
typedef struct {
    void *arg;
    void (*receive)(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                    const ip_addr_t *addr, uint16_t port);
    void (*destroyed)(void *arg, err_t error);
} luat_dns_server_udp_binding_t;

typedef struct luat_dns_server_lwip_port {
    /* binding=NULL 时同时解除接收回调和厂商提供的释放后错误回调。 */
    void (*udp_attach)(struct udp_pcb *pcb, luat_dns_server_udp_binding_t *binding);
    void (*udp_bind_netif)(struct udp_pcb *pcb, const struct netif *netif);
    /* 必须原子地复制全部字节，或返回 ERR_MEM 且不消耗任何数据。 */
    err_t (*tcp_write_copy)(struct tcp_pcb *pcb, const void *data, uint16_t length);
} luat_dns_server_lwip_port_t;

/** 仅由 luat_dns_server_lwip_default.c 定义（适用于未修改的上游 lwIP）。
 * 厂商版本构建时应排除此文件，并显式提供自己的移植层钩子。
 */
extern const luat_dns_server_lwip_port_t luat_dns_server_lwip_default_port;

#ifdef __cplusplus
}
#endif
#endif
