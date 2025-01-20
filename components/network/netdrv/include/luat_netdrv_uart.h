#ifndef LUAT_NETDRV_UART_H
#define LUAT_NETDRV_UART_H 1

#include "luat_netdrv.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "luat_ulwip.h"

typedef struct luat_netdrv_uart_ctx
{
    uint8_t uart_id;
    uint8_t dhcp;
    luat_netdrv_t netdrv;
    ulwip_ctx_t ulwip;
    uint8_t rxbuff[4096];
    uint8_t txbuff[4096];
}luat_netdrv_uart_ctx_t;

luat_netdrv_t* luat_netdrv_uart_setup(luat_netdrv_conf_t *conf);

#endif
