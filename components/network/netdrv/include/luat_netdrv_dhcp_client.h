#ifndef LUAT_NETDRV_DHCP_CLIENT_H
#define LUAT_NETDRV_DHCP_CLIENT_H

#include "luat_netdrv.h"

// DHCP 客户端 (netif 级), 由 luat_netdrv 统一管理生命周期
// 由历史模块 components/network/ulwip/src/ulwip_dhcp_client.c 迁移而来
void luat_netdrv_dhcp_client_start(luat_netdrv_t* drv);
void luat_netdrv_dhcp_client_stop(luat_netdrv_t* drv);

#endif
