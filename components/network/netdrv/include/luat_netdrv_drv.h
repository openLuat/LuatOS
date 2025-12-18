#ifndef LUAT_NETDRV_DRV_H
#define LUAT_NETDRV_DRV_H

#include "luat_netdrv.h"

#define LUAT_NETDRV_IMPL_CH390H 1
#define LUAT_NETDRV_IMPL_UART   2
#define LUAT_NETDRV_IMPL_WHALE  3
#define LUAT_NETDRV_IMPL_WG     4
#define LUAT_NETDRV_IMPL_OPENVPN 5

luat_netdrv_t* luat_netdrv_ch390h_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_uart_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_whale_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_wg_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_openvpn_setup(luat_netdrv_conf_t *conf);

#endif // !LUAT_NETDRV_DRV_H
