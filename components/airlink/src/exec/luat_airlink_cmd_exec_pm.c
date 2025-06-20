#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_pm.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

int luat_airlink_cmd_exec_pm_request(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t tp = cmd->data[8];
    if (tp >= LUAT_PM_SLEEP_MODE_NONE && tp <= LUAT_PM_SLEEP_MODE_DEEP) {
        LLOGD("收到pm_request指令!!! tp %d", tp);
        luat_pm_request(tp);
    }
    return 0;
}

int luat_airlink_cmd_exec_pm_power_ctrl(luat_airlink_cmd_t* cmd, void* userdata) {
    uint32_t id = 0;
    memcpy(&id, cmd->data + 8, 4);
    uint8_t onoff = cmd->data[8 + 4];
    LLOGD("收到pm_power_ctrl指令!!! id %d onoff %d", id, onoff);
    luat_pm_power_ctrl(id, onoff);
    return 0;
}

int luat_airlink_cmd_exec_pm_wakeup_pin(luat_airlink_cmd_t* cmd, void* userdata) {
    uint32_t pin = 0;
    memcpy(&pin, cmd->data + 8, 4);
    uint8_t val = cmd->data[8 + 4];
    LLOGD("收到pm_wakeup_pin指令!!! pin %d val %d", pin, val);
    luat_pm_wakeup_pin(pin, val);
    return 0;
}
