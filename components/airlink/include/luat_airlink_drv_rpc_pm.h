#ifndef LUAT_AIRLINK_DRV_RPC_PM_H
#define LUAT_AIRLINK_DRV_RPC_PM_H

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC_PM
#include "luat_airlink.h"

int luat_airlink_drv_rpc_pm_request(int mode);
int luat_airlink_drv_rpc_pm_power_ctrl(int id, uint8_t val);
int luat_airlink_drv_rpc_pm_wakeup_pin(int pin, int val);

#endif /* LUAT_USE_AIRLINK_RPC_PM */

#endif /* LUAT_AIRLINK_DRV_RPC_PM_H */
