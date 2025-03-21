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

int luat_airlink_drv_gpio_setup(luat_gpio_t* gpio) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_gpio_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x300, sizeof(luat_gpio_t) + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, gpio, sizeof(luat_gpio_t));
    item.cmd = cmd;
    luat_airlink_queue_send(0, &item);
    return 0;
}

int luat_airlink_drv_luat_gpio_set(int pin, int level) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 2 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x300, 2 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = (uint8_t)pin;
    data[1] = (uint8_t)level;
    item.cmd = cmd;
    luat_airlink_queue_send(0, &item);
    return 0;
}
