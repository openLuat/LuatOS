#ifndef LUAT_AIRLINK_DRV_PM_H
#define LUAT_AIRLINK_DRV_PM_H

#ifndef LUAT_AIRLINK_H
#error "include luat_airlink.h first"
#endif

int luat_airlink_drv_pm_request(int mode);
int luat_airlink_drv_pm_power_ctrl(int id, uint8_t val);

#endif
