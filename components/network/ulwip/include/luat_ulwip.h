#ifndef LUAT_ULWIP_H
#define LUAT_ULWIP_H

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_mem.h"
#include "luat_zbuff.h"
#include "luat_rtos.h"

#include "lwip/opt.h"
#include "lwip/debug.h"
#include "lwip/stats.h"
#include "lwip/netif.h"
#include "lwip/etharp.h"
#include "lwip/dhcp.h"
#include "lwip/ethip6.h"
#include "lwip/udp.h"
// #include "lwip/prot/iana.h"
#include "netif/ethernet.h"

// #include "net_lwip.h"
#include "net_lwip2.h"

#include "luat_network_adapter.h"
#include "dhcp_def.h"

#define USERLWIP_NET_COUNT NW_ADAPTER_INDEX_LWIP_NETIF_QTY

void net_lwip2_set_link_state(uint8_t adapter_index, uint8_t updown);

typedef struct ulwip_ctx
{
    int output_lua_ref;
    struct netif *netif;
    uint16_t mtu;
    uint8_t flags;
    uint8_t adapter_index;
    uint16_t use_zbuff_out;
    uint8_t hwaddr[ETH_HWADDR_LEN];
    dhcp_client_info_t *dhcp_client;
    luat_rtos_timer_t dhcp_timer;
    struct udp_pcb *dhcp_pcb;
}ulwip_ctx_t;

typedef struct netif_cb_ctx {
    struct netif *netif;
    struct pbuf *p;
}netif_cb_ctx_t;

#endif
