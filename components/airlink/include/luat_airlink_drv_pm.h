#ifndef LUAT_AIRLINK_DRV_PM_H
#define LUAT_AIRLINK_DRV_PM_H

#include "luat_airlink.h"

int luat_airlink_drv_pm_request(int mode);
int luat_airlink_drv_pm_power_ctrl(int id, uint8_t val);
int luat_airlink_drv_pm_wakeup_pin(int pin, int val);

#endif
