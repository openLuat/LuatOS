#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_airlink.h"
#include "luat_pm.h"
#include "luat_rtos.h"
#include "luat/drv_pm.h"
#include "luat_airlink_drv_pm.h"


#ifdef LUAT_USE_AIRLINK
#include "luat_airlink.h"
#endif

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

#ifdef LUAT_USE_AIRLINK
static uint8_t s_wifi_sleep = 0;
extern uint32_t g_airlink_pause;
#endif

int luat_drv_pm_power_ctrl(int chip, int id, uint8_t val) {
    if (chip == 0) {
        #ifdef LUAT_USE_AIRLINK
        if (id == LUAT_PM_POWER_WORK_MODE && luat_airlink_has_wifi()) {
            // 首先, 如果是退出
            if (LUAT_PM_POWER_MODE_NORMAL == val) {
                if (s_wifi_sleep) {
                    // 现阶段, 只能重启wifi
                    luat_gpio_set(23, 0); // 关闭wifi
                    luat_rtos_task_sleep(10);
                    luat_gpio_set(23, 1); // 打开wifi
                    s_wifi_sleep = 0;
                }
                g_airlink_pause = 0;
            }
            // 然后, 如果是进入
            else {
                s_wifi_sleep = 1;
                luat_airlink_drv_pm_power_ctrl(1, val);
                luat_rtos_task_sleep(10);
                // 如果是进入休眠模式, 恢复airlink工作
                g_airlink_pause = 1;
            }
        }
        #endif
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
