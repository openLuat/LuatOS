#ifndef LUAT_NETDRV_H
#define LUAT_NETDRV_H

#include "lwip/pbuf.h"

typedef void (*luat_netdrv_dataout_cb)(void* userdata, struct pbuf* pb, int flags);
typedef int (*luat_netdrv_bootup_cb)(void* userdata);
typedef int (*luat_netdrv_ready_cb)(void* userdata);

typedef struct luat_netdrv {
    int32_t id;
    struct netif* netif;
    luat_netdrv_dataout_cb dataout;
    luat_netdrv_bootup_cb boot;
    luat_netdrv_ready_cb ready;
    void* userdata;
}luat_netdrv_t;

enum {
    LUAT_NETDRV_TP_NATIVE,
    LUAT_NETDRV_TP_CH390H,
    LUAT_NETDRV_TP_W5100,
    LUAT_NETDRV_TP_W5500,
    LUAT_NETDRV_TP_SPINET,
    LUAT_NETDRV_TP_UARTNET,
    LUAT_NETDRV_TP_USB
};

typedef struct luat_netdrv_conf
{
    int32_t id;
    int32_t impl;
    int32_t tp;
    int32_t flags;
}luat_netdrv_conf_t;


luat_netdrv_t* luat_netdrv_setup(luat_netdrv_conf_t *conf);

int luat_netdrv_dhcp(int32_t id, int32_t enable);

int luat_netdrv_ready(int32_t id);

int luat_netdrv_register(int32_t id, luat_netdrv_t* drv);

#endif
