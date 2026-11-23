/* SPDX-License-Identifier: MIT
 * 版权和许可声明见 LICENSE。
 * 基于 lwIP 原始接口的传输后端；协议和租约逻辑位于 luat_dhcps.c。
 */
#include "luat_dhcps_lwip.h"
#include "lwip/udp.h"
#include "lwip/netif.h"
#include "lwip/ip.h"
#include <string.h>

#define LUAT_LOG_TAG "dhcps"
#include "luat_log.h"

static void receive(void *arg, struct udp_pcb *socket, struct pbuf *p,
                    const ip_addr_t *addr, u16_t port)
{
    luat_dhcps_lwip_t *s = (luat_dhcps_lwip_t *)arg;
    (void)addr;
    if (!p) return;
    uint8_t request[LUAT_DHCPS_REQUEST_MAX], reply[LUAT_DHCPS_REPLY_SIZE];
    size_t length = p->tot_len;
    if (port != 68 || ip_current_input_netif() != s->netif || length > sizeof(request)) {
        pbuf_free(p);
        return;
    }
    u16_t copied = pbuf_copy_partial(p, request, (u16_t)length, 0);
    pbuf_free(p);
    if (copied != length) return;
    length = luat_dhcps_reply(&s->engine, request, length, reply, sizeof(reply), s->now(s->userdata));
    if (!length) return;
    struct pbuf *response = pbuf_alloc(PBUF_TRANSPORT, (u16_t)length, PBUF_RAM);
    if (!response) return;
    ip_addr_t destination;
    IP_ADDR4(&destination, 255, 255, 255, 255);
    if (reply[242] != 6 && !(request[10] & 0x80) && (reply[12] | reply[13] | reply[14] | reply[15])) {
        IP_ADDR4(&destination, reply[12], reply[13], reply[14], reply[15]);
    }
    err_t result = pbuf_take(response, reply, (u16_t)length);
    if (result == ERR_OK) result = udp_sendto_if(socket, response, &destination, 68, s->netif);
    pbuf_free(response);
    LLOGD("reply=%u ip=%u.%u.%u.%u result=%d", (unsigned)reply[242],
          (unsigned)reply[16], (unsigned)reply[17], (unsigned)reply[18], (unsigned)reply[19], (int)result);
}

int luat_dhcps_lwip_start(luat_dhcps_lwip_t *s, struct netif *netif,
                          const luat_dhcps_config_t *config,
                          luat_dhcps_lease_t *leases, size_t capacity,
                          luat_dhcps_now_fn now, void *userdata)
{
    if (!s || s->pcb || !netif || !config || !now ||
        config->server_ip != lwip_ntohl(ip4_addr_get_u32(netif_ip4_addr(netif))) ||
        config->netmask != lwip_ntohl(ip4_addr_get_u32(netif_ip4_netmask(netif)))) return -1;
    if (luat_dhcps_init(&s->engine, config, leases, capacity)) return -1;
    s->pcb = udp_new_ip_type(IPADDR_TYPE_V4);
    if (!s->pcb) { luat_dhcps_lwip_stop(s); return -1; }
    ip_set_option(s->pcb, SOF_BROADCAST);
#if SO_REUSE
    ip_set_option(s->pcb, SOF_REUSEADDR);
#endif
    udp_bind_netif(s->pcb, netif);
    if (udp_bind(s->pcb, IP_ANY_TYPE, 67) != ERR_OK) {
        luat_dhcps_lwip_stop(s);
        return -1;
    }
    s->netif = netif;
    s->now = now;
    s->userdata = userdata;
    udp_recv(s->pcb, receive, s);
    return 0;
}

void luat_dhcps_lwip_stop(luat_dhcps_lwip_t *s)
{
    if (!s) return;
    if (s->pcb) {
        udp_recv(s->pcb, NULL, NULL);
        udp_remove(s->pcb);
    }
    luat_dhcps_deinit(&s->engine);
    memset(s, 0, sizeof(*s));
}
