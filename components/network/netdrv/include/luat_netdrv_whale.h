#ifndef LUAT_NETDRV_WHALE_H
#define LUAT_NETDRV_WHALE_H 1

#include "luat_netdrv.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "luat_ulwip.h"

typedef struct luat_netdrv_whale {
    uint8_t id;
    void* userdata;
    uint8_t flags;
    uint16_t mtu;
    uint8_t mac[6];
    uint8_t dhcp;
    ulwip_ctx_t ulwip;
}luat_netdrv_whale_t;


void luat_netdrv_whale_dataout(luat_netdrv_t* drv, void* userdata, uint8_t* buff, uint16_t len);
void luat_netdrv_whale_boot(luat_netdrv_t* drv, void* userdata);

luat_netdrv_t* luat_netdrv_whale_create(luat_netdrv_whale_t* cfg);

void luat_netdrv_whale_ipevent(luat_netdrv_t* drv, uint8_t updown);

#endif
