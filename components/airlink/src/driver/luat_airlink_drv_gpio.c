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

int luat_airlink_drv_gpio_setup(luat_gpio_t* gpio) {
    // LLOGD("执行GPIO配置指令!!! pin %d mode %d pull %d", gpio->pin, gpio->mode, gpio->pull);
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
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_gpio_set(int pin, int level) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 2 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x301, 2 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = (uint8_t)pin;
    data[1] = (uint8_t)level;
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

static void drv_gpio_result_exec(struct luat_airlink_result_reg *reg, luat_airlink_cmd_t* cmd) {
    uint8_t tmp;
    memcpy(&tmp, cmd->data + 8 + 8 + 1, 1);
    int* val = reg->userdata2;
    *val = tmp;
    luat_rtos_semaphore_release(reg->userdata);
}

static void drv_gpio_result_cleanup(struct luat_airlink_result_reg *reg, luat_airlink_cmd_t* cmd) {
    luat_rtos_semaphore_release(reg->userdata);
}

// static luat_rtos_semaphore_t semaphore_drv_gpio;
int luat_airlink_drv_gpio_get(int pin, int* val) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 1 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x302, 1 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    luat_rtos_semaphore_t semaphore_drv_gpio;
    luat_rtos_semaphore_create(&semaphore_drv_gpio, 0);
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = (uint8_t)pin;
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    luat_airlink_result_reg_t reg = {
        .exec = drv_gpio_result_exec,
        .id = luat_airlink_next_cmd_id,
        .userdata = semaphore_drv_gpio,
        .userdata2 = val
    };
    luat_airlink_result_reg(&reg);
    luat_rtos_semaphore_take(semaphore_drv_gpio, 1000);
    return 0;
}
