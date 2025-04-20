#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_uart.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

// 前8字节是指令id, 用于返回执行结果, 待定.

int luat_airlink_cmd_exec_uart_setup(luat_airlink_cmd_t* cmd, void* userdata) {
    luat_uart_t* uart = cmd->data + 8;
    if (uart->id >= 10) {
        uart->id -= 10;
    }
    LLOGD("uart[%d] setup", uart->id);
    int ret = luat_uart_setup(uart);
    LLOGD("uart[%d] setup baud_rate %d ret %d", uart->id, uart->baud_rate, ret);
    return ret;
}

int luat_airlink_cmd_exec_uart_write(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t id = cmd->data[8];
    if (id >= 10) {
        id -= 10;
    }
    LLOGD("uart[%d] write %d bytes", id, cmd->len - 9);
    int ret = luat_uart_write(id, cmd->data + 9, cmd->len - 9);
    LLOGD("uart[%d] write ret %d", id, ret);
    return ret;
}
int luat_airlink_cmd_exec_uart_close(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t id = cmd->data[8];
    if (id >= 10) {
        id -= 10;
    }
    LLOGD("uart[%d] close", id);
    int ret = luat_uart_close(id);
    LLOGD("uart[%d] close ret %d", id, ret);
    return ret;
}
int luat_airlink_cmd_exec_uart_data_cb(luat_airlink_cmd_t* cmd, void* userdata) {
    return 0;
}