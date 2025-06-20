#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

// 前8字节是指令id, 用于返回执行结果, 待定.

static int airlink_gpio_irq_cb(int pin, void* args) {
    return 0;
}

int luat_airlink_cmd_exec_gpio_setup(luat_airlink_cmd_t* cmd, void* userdata) {
    luat_gpio_t conf = {0};
    // 后面是配置参数,是luat_gpio_t结构体
    memcpy(&conf, cmd->data + 8, sizeof(luat_gpio_t));
    if (conf.pin >= 128) {
        conf.pin -= 128;
    }
    LLOGD("收到GPIO配置指令!!! pin %d", conf.pin);
    if (conf.mode == Luat_GPIO_IRQ) {
        conf.irq_cb = airlink_gpio_irq_cb;
        conf.irq_args = NULL;
    }
    else {
        conf.irq_cb = NULL;
    }
    int ret = luat_gpio_setup(&conf);
    LLOGD("收到GPIO配置指令!!! pin %d ret %d", conf.pin, ret);
    return 0;
}

int luat_airlink_cmd_exec_gpio_set(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到GPIO设置指令!!!");
    uint8_t params[2];
    memcpy(params, cmd->data + 8, 2);
    if (params[0] >= 128) {
        params[0] -= 128;
    }
    int ret = luat_gpio_set(params[0], params[1]);
    LLOGD("收到GPIO设置指令!!! pin %d level %d ret %d", params[0], params[1], ret);
    return 0;
}


int luat_airlink_cmd_exec_gpio_get(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到GPIO读取指令!!!");
    uint8_t params[10];
    memcpy(params, cmd->data, 9);
    if (params[0] >= 128) {
        params[0] -= 128;
    }
    params[9] = luat_gpio_get(params[8]);
    LLOGD("收到GPIO读取指令!!! pin %d level %d", params[8], params[9]);
    // 反馈读取结果
    luat_airlink_result_send(params, 10);
    return 0;
}

int luat_airlink_cmd_exec_gpio_driver_yhm27xx(luat_airlink_cmd_t* cmd, void* userdata) {
    // LLOGE("收到yhm27xx的GPIO设置指令!!!");

    uint8_t params[5];
    memcpy(params, cmd->data + 8, 5);
    if (params[0] >= 128) {
        params[0] -= 128;
    }
    int ret = luat_gpio_driver_yhm27xx(params[0], params[1],params[2], params[3], &(params[4]));
    
    return 0;
}

int luat_airlink_cmd_exec_gpio_driver_yhm27xx_reqinfo(luat_airlink_cmd_t* cmd, void* userdata) {
    // LLOGE("收到yhm27xx的GPIO设置指令!!!");

    uint8_t pin = cmd->data[8];
    uint8_t chip_id = cmd->data[9];
    uint8_t params[9] = {0};
    if(pin >= 128)  pin -= 128;
    for (uint8_t i = 0; i < 9; i++)
    {
        luat_gpio_driver_yhm27xx(pin, chip_id, i, 1, &(params[i]));
    }
    // 反馈数据, 走sys_pub
    uint8_t buff[256] = {0};
    int ret = 0;
    int remain = 256;
    uint8_t *ptr = buff;

    ret = luat_airlink_syspub_addstring("YHM27XX_REG", strlen("YHM27XX_REG"), ptr, remain);
    ptr += ret;
    remain -= ret;
        
    ret = luat_airlink_syspub_addstring((const char*)params, 9, ptr, remain);
    ptr += ret;
    remain -= ret;

    luat_airlink_syspub_send(buff, ptr - buff);
    
    return 0;
}

