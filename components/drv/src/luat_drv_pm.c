#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_airlink.h"
#include "luat_pm.h"
#include "luat/drv_pm.h"
#include "luat_airlink_drv_pm.h"

#define LUAT_LOG_TAG "drv.pm"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

int luat_drv_pm_request(int chip, int mode) {
    if (chip == 0) {
        return luat_pm_request(mode);
    }
    else {
        return luat_airlink_drv_pm_request(mode);
    }
}

int luat_drv_pm_power_ctrl(int chip, int id, uint8_t val) {
    if (chip == 0) {
        return luat_pm_power_ctrl(id, val);
    }
    else {
        return luat_airlink_drv_pm_power_ctrl(id, val);
    }
}

int luat_drv_pm_wakeup_pin(int chip, int pin, int val) {
    if (chip == 0) {
        return luat_pm_wakeup_pin(pin, val);
    }
    else {
        pin -= 128;
        return luat_airlink_drv_pm_wakeup_pin(pin, val);
    }
}
