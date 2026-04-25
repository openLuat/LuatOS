#ifndef LUAT_AIRLINK_DRV_RPC_WLAN_H
#define LUAT_AIRLINK_DRV_RPC_WLAN_H

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC_WLAN
#include "luat_airlink.h"
#include "luat_wlan.h"

int luat_airlink_drv_rpc_wlan_init(luat_wlan_config_t* args);
int luat_airlink_drv_rpc_wlan_ap_start(luat_wlan_apinfo_t* info);
int luat_airlink_drv_rpc_wlan_ap_stop(void);
int luat_airlink_drv_rpc_wlan_connect(luat_wlan_conninfo_t* info);
int luat_airlink_drv_rpc_wlan_disconnect(void);
int luat_airlink_drv_rpc_wlan_scan(void);

#endif /* LUAT_USE_AIRLINK_RPC_WLAN */

#endif /* LUAT_AIRLINK_DRV_RPC_WLAN_H */
