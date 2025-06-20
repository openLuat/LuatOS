#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

int luat_airlink_drv_pm_request(int mode) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(uint8_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x600, sizeof(uint8_t) + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    uint8_t tmp = (uint8_t)mode;
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, &tmp, sizeof(uint8_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_pm_power_ctrl(int id, uint8_t val) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x601, 5 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, &id, 4);
    memcpy(cmd->data + 8 + 4, &val, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_pm_wakeup_pin(int pin, int val) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x602, 5 + 8) ;
    if (cmd == NULL) {
        return -101;
    }

    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, &pin, 4);
    memcpy(cmd->data + 8 + 4, &val, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}