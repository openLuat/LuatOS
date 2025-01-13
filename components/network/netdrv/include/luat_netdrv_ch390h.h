#ifndef LUAT_NETDRV_CH390H_H
#define LUAT_NETDRV_CH390H_H 1

#include "luat_netdrv.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "luat_ulwip.h"

#define CH390H_MAX_TX_NUM (16)

typedef struct ch390h
{
    uint8_t spiid;
    uint8_t cspin;
    uint8_t intpin;
    uint8_t adapter_id;
    uint8_t status;
    uint8_t dhcp;
    uint8_t hwaddr[6];
    struct netif* netif;
    ulwip_ctx_t ulwip;
    luat_netdrv_t* netdrv;
    uint8_t rxbuff[1600];
    uint8_t txbuff[1600];
    struct pbuf* txqueue[CH390H_MAX_TX_NUM];
}ch390h_t;


luat_netdrv_t* luat_netdrv_ch390h_setup(luat_netdrv_conf_t *conf);

#endif
