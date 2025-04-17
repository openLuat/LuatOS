#ifndef LUAT_ICMP_H
#define LUAT_ICMP_H

#include "luat_base.h"
#include "luat_netdrv.h"
#include "lwip/ip.h"
#include "lwip/ip_addr.h"
#include "lwip/icmp.h"
#include "lwip/netif.h"
#include "lwip/raw.h"


typedef void (*luat_icmp_recv_fn)(void* ctx, uint32_t tused);

typedef struct luat_icmp_ctx
{
    uint8_t adapter_id;
    struct netif *netif;
    struct raw_pcb *pcb;
    ip_addr_t dst;
    uint16_t id;
    uint16_t seqno;
    uint64_t send_time;
    uint64_t recv_time;
    luat_icmp_recv_fn cb;
}luat_icmp_ctx_t;


luat_icmp_ctx_t* luat_icmp_init(uint8_t adapter_id);
luat_icmp_ctx_t* luat_icmp_get(uint8_t adapter_id);
int luat_icmp_ping(luat_icmp_ctx_t* ctx, ip_addr_t* dst, size_t size);

#endif
