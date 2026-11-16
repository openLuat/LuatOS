/* SPDX-License-Identifier: MIT
 * Copyright (c) 2019-2026 openLuat & AirM2M
 * 仅适用于上游 lwIP ABI；厂商移植版本应排除此编译单元。
 */
#include "luat_dns_server_lwip.h"

static void dns_receive(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                        const ip_addr_t *addr, u16_t port) {
    luat_dns_server_udp_binding_t *binding = arg;
    binding->receive(binding->arg, pcb, p, addr, port);
}

static void dns_attach(struct udp_pcb *pcb, luat_dns_server_udp_binding_t *binding) {
    udp_recv(pcb, binding ? dns_receive : NULL, binding);
}

static err_t dns_write(struct tcp_pcb *pcb, const void *data, uint16_t length) {
    return tcp_write(pcb, data, length, TCP_WRITE_FLAG_COPY);
}

const luat_dns_server_lwip_port_t luat_dns_server_lwip_default_port = {
    dns_attach, udp_bind_netif, dns_write
};
