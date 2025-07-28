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
    #ifdef __BK72XX__
    // SPI的GPIO禁止设置
    if ((conf.pin >= 14 && conf.pin <= 17) || conf.pin == 48) {
        LLOGE("禁止设置SPI相关的GPIO");
        return 0;
    }
    #endif
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
    return ret;
}

int luat_airlink_cmd_exec_gpio_set(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到gpio.set指令!!!");
    uint8_t params[2];
    memcpy(params, cmd->data + 8, 2);
    if (params[0] >= 128) {
        params[0] -= 128;
    }
    int ret = luat_gpio_set(params[0], params[1]);
    LLOGD("收到GPIO设置指令!!! pin %d level %d ret %d", params[0], params[1], ret);
    return ret;
}


int luat_airlink_cmd_exec_gpio_get(luat_airlink_cmd_t* reqcmd, void* userdata) {
    LLOGD("收到gpio.get指令!!!");
    uint8_t params[10];
    memcpy(params, reqcmd->data, 9);
    if (params[0] >= 128) {
        params[0] -= 128;
    }
    params[9] = luat_gpio_get(params[8]);
    LLOGD("收到GPIO读取指令!!! pin %d level %d", params[8], params[9]);

    // 反馈读取结果
    uint64_t seq_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 2 + sizeof(luat_airlink_cmd_t) + 8 + 8
    };
    luat_airlink_cmd_t* cmd2 = luat_airlink_cmd_new(0x310, 2 + 8 + 8) ;
    if (cmd2 == NULL) { 
        return -101;
    }
    memcpy(cmd2->data, &seq_id, 8);
    memcpy(cmd2->data + 8, reqcmd->data, 8);
    uint8_t* data = cmd2->data + 16;
    data[0] = (uint8_t)params[8];
    data[1] = (uint8_t)params[9];
    item.cmd = cmd2;
    LLOGD("发送回复 %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X",
        cmd2->data[0],  cmd2->data[1], cmd2->data[2], cmd2->data[3],  cmd2->data[4],  cmd2->data[5],  cmd2->data[6],  cmd2->data[7],
        cmd2->data[8],  cmd2->data[9], cmd2->data[0], cmd2->data[11], cmd2->data[12], cmd2->data[13], cmd2->data[14], cmd2->data[15], 
        cmd2->data[16], cmd2->data[17]
    );
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

extern luat_rtos_semaphore_t g_drv_gpio_sem;
extern uint64_t g_drv_gpio_input_level;
int luat_airlink_cmd_exec_gpio_get_result(luat_airlink_cmd_t* cmd, void* userdata) {
    LLOGD("收到GPIO读取指令的回复!!!");
    if (g_drv_gpio_sem == NULL) {
        LLOGE("g_drv_gpio_sem is NULL");
        return 0;
    }
    if (cmd->len < 8 + 8 + 2) {
        LLOGE("gpio_get_result data len error %d", cmd->len);
        return 0;
    }
    // TODO 打印出发送和收到的seq id, 匹配一下, 验证数据
    LLOGD("收到回复 %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X",
        cmd->data[0],  cmd->data[1], cmd->data[2], cmd->data[3],  cmd->data[4],  cmd->data[5],  cmd->data[6],  cmd->data[7],
        cmd->data[8],  cmd->data[9], cmd->data[0], cmd->data[11], cmd->data[12], cmd->data[13], cmd->data[14], cmd->data[15], 
        cmd->data[16], cmd->data[17]
    );

    // 读取数据, pin 及 输入值
    uint8_t pin = cmd->data[16];
    uint8_t level = cmd->data[17];
    // LLOGI("gpio(%d) input %d", pin, level);
    if (pin < 64) {
        uint64_t tmp = pin;
        if (level) {
            // bit set
            g_drv_gpio_input_level |= (1ULL << tmp);
        }
        else {
            // bit clean
            g_drv_gpio_input_level &= ~(1ULL << tmp);
        }
        luat_rtos_semaphore_release(g_drv_gpio_sem);
    }
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
    
    return ret;
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

