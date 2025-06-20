#ifndef __DRV_WLAN_H
#define __DRV_WLAN_H

#include "luat_base.h"
#include "luat_pm.h"

int luat_drv_pm_request(int chip, int mode);
int luat_drv_pm_power_ctrl(int chip, int id, uint8_t val);
int luat_drv_pm_wakeup_pin(int chip, int pin, int val);

#endif