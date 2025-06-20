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

luat_rtos_semaphore_t g_drv_gpio_sem;
uint64_t g_drv_gpio_input_level = 0;
extern luat_airlink_dev_info_t g_airlink_ext_dev_info;
int luat_airlink_drv_gpio_get(int pin, int* val) {
    int ret = 0;
    if (pin >= 128) {
        pin -= 128;
    }
    if (pin >= 64) {
        LLOGE("invaild pin %d/%d", pin, pin + 128);
        *val = 0;
        return 0;
    }
    uint32_t version;
    memcpy(&version, &g_airlink_ext_dev_info.wifi.version, 4);
    if (version < 9) {
        LLOGE("wifi version < 9, not support gpio.set");
        *val = 0;
        return 0;
    }
    uint64_t seq_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 1 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x302, 1 + 8) ;
    if (cmd == NULL) {
        LLOGE("out of memory when gpio.get");
        return 0;
    }
    if (g_drv_gpio_sem == NULL) {
        luat_rtos_semaphore_create(&g_drv_gpio_sem, 0);
        luat_rtos_semaphore_take(g_drv_gpio_sem, 100);
    }
    memcpy(cmd->data, &seq_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = (uint8_t)pin;
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    // LLOGI("g_drv_gpio_sem take");
    ret = luat_rtos_semaphore_take(g_drv_gpio_sem, 100);
    // LLOGI("g_drv_gpio_sem take %d", ret);
    uint64_t tmp = pin;
    LLOGD("g_drv_gpio_input_level %d %08X", pin, g_drv_gpio_input_level);
    LLOGD("g_drv_gpio_input_level %d is %d", pin, (g_drv_gpio_input_level >> tmp) & 1);
    *val = (g_drv_gpio_input_level >> tmp) & 1;
    if (ret) {
        LLOGW("gpio.get timeout!! pin %d", pin);
    }
    return ret;
}

int luat_airlink_drv_gpio_driver_yhm27xx(uint32_t Pin, uint8_t ChipID, uint8_t RegAddress, uint8_t IsRead, uint8_t *Data) 
{
    uint8_t Pin_id = Pin;
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x304, 5 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = Pin_id;
    data[1] = ChipID;
    data[2] = RegAddress;
    data[3] = IsRead;
    data[4] = *Data;

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_gpio_driver_yhm27xx_reqinfo(uint8_t Pin, uint8_t ChipID)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x305, 2 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t* data = cmd->data + 8;
    data[0] = Pin;
    data[1] = ChipID;

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


