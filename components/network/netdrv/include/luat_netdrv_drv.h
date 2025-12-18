#ifndef LUAT_NETDRV_DRV_H
#define LUAT_NETDRV_DRV_H

#include "luat_netdrv.h"

luat_netdrv_t* luat_netdrv_ch390h_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_uart_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_whale_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_wg_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_openvpn_setup(luat_netdrv_conf_t *conf);

#endif // !LUAT_NETDRV_DRV_H
