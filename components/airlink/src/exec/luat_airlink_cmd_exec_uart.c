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
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

// 前8字节是指令id, 用于返回执行结果, 待定.
static luat_rtos_queue_t rx_queue;

static luat_rtos_task_handle rx_thread;


static void rx_data_input(int uart_id, uint32_t data_len) {
    if (!rx_queue) {
        return;
    }
    uint32_t id = (uint32_t)uart_id;
    luat_rtos_queue_send(rx_queue, &id, 0, 0);
}

static void tx_sent_cb(int uart_id, uint32_t data_len) {
    size_t total_len = sizeof(luat_airlink_cmd_t) + 8 + 1;
    airlink_queue_item_t item = {.len = total_len};
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x411, 1 + 8);
    if (cmd == NULL) {
        LLOGE("内存分配失败!!");
        return;
    }
    uint64_t luat_airlink_next_cmd_id = 0;
    luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t tmp = (uint8_t)uart_id;
    memcpy(cmd->data + 8, &tmp, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
}

static void rx_data_input2(int uart_id, uint32_t data_len) {
    // LLOGD("执行uart read %d %d", uart_id, data_len);
    uint64_t luat_airlink_next_cmd_id = 0;
    size_t length = data_len;
    uint8_t buff[1024];
    while (length > 0) {
        size_t rsize = length;
        if (rsize > 1024) {
            rsize = 1024;
        }
        rsize = luat_uart_read(uart_id, buff, rsize);
        // LLOGD("uart read out %d %d", uart_id, rsize);
        if (rsize < 1) {
            break;
        }
        length -= rsize;

        size_t total_len = rsize + sizeof(luat_airlink_cmd_t) + 8 + 1;
        airlink_queue_item_t item = {.len = total_len};
        luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x410, rsize + 1 + 8);
        if (cmd == NULL) {
            LLOGE("内存分配失败!!");
            return;
        }
        luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
        memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
        uint8_t tmp = (uint8_t)uart_id;
        memcpy(cmd->data + 8, &tmp, 1);
        memcpy(cmd->data + 9, buff, rsize);
        item.cmd = cmd;
        luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    }
    
    return;
}

static void rx_thread_main(void* params) {
    uint32_t id = 0;
    int ret = 0;
    luat_rtos_queue_create(&rx_queue, 1024, sizeof(uint32_t));
    while (1) {
        ret = luat_rtos_queue_recv(rx_queue, &id, 0, LUAT_WAIT_FOREVER);
        if (ret == 0) {
            rx_data_input2(id, 4096);
        }
    }
}

int luat_airlink_cmd_exec_uart_setup(luat_airlink_cmd_t* cmd, void* userdata) {
    luat_uart_t* uart = cmd->data + 8;
    if (uart->id >= 10) {
        uart->id -= 10;
    }
    // LLOGD("uart[%d] setup", uart->id);
    int ret = luat_uart_setup(uart);
    LLOGD("uart[%d] setup baud_rate %d ret %d", uart->id, uart->baud_rate, ret);
    if (ret == 0) {
        if (rx_thread == NULL) {
            luat_rtos_task_create(&rx_thread, 4 * 1024, 50, "airlink_rx", rx_thread_main, NULL, 0);
        }
        luat_uart_ctrl(uart->id, LUAT_UART_SET_RECV_CALLBACK, rx_data_input);
        luat_uart_ctrl(uart->id, LUAT_UART_SET_SENT_CALLBACK, tx_sent_cb);
    }
    return ret;
}

int luat_airlink_cmd_exec_uart_write(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t id = cmd->data[8];
    if (id >= 10) {
        id -= 10;
    }
    // LLOGD("uart[%d] write %d bytes", id, cmd->len - 9);
    int ret = luat_uart_write(id, cmd->data + 9, cmd->len - 9);
    // LLOGD("uart[%d] write ret %d", id, ret);
    return ret;
}
int luat_airlink_cmd_exec_uart_close(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t id = cmd->data[8];
    if (id >= 10) {
        id -= 10;
    }
    // LLOGD("uart[%d] close", id);
    int ret = luat_uart_close(id);
    // LLOGD("uart[%d] close ret %d", id, ret);
    return ret;
}

// 注意, 这个函数是调用端的回调函数, 用于接收数据
extern int luat_airlink_drv_uart_data_cb(int uart_id, void* buffer, size_t length);
int luat_airlink_cmd_exec_uart_data_cb(luat_airlink_cmd_t* cmd, void* userdata) {
    if (cmd->len < 9) {
        return 0;
    }
    uint8_t id = cmd->data[8];
    // LLOGD("uart数据输入 %d %d", id, cmd->len - 9);
    luat_airlink_drv_uart_data_cb(id + 10, cmd->data + 9, cmd->len - 9);
    return 0;
}

// 接收sent事件
extern int luat_airlink_drv_uart_sent_cb(int uart_id, void* buffer, size_t length);
int luat_airlink_cmd_exec_uart_sent_cb(luat_airlink_cmd_t* cmd, void* userdata) {
    if (cmd->len < 9) {
        return 0;
    }
    uint8_t id = cmd->data[8];
    // LLOGD("uart sent %d %d", id, cmd->len - 9);
    luat_airlink_drv_uart_sent_cb(id + 10, cmd->data + 9, cmd->len - 9);
    return 0;
}