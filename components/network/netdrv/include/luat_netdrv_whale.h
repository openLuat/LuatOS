#ifndef LUAT_NETDRV_WHALE_H
#define LUAT_NETDRV_WHALE_H 1

#include "luat_netdrv.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "luat_ulwip.h"


void luat_netdrv_whale_dataout(luat_netdrv_t* drv, void* userdata, uint8_t* buff, uint16_t len);
void luat_netdrv_whale_boot(luat_netdrv_t* drv, void* userdata);

#endif
