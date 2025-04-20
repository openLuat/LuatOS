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
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "airlink.uart"
#include "luat_log.h"

int l_uart_handler(lua_State *L, void* ptr);


int luat_airlink_drv_uart_setup(luat_uart_t* conf) {
    // LLOGD("执行uart setup %d baud_rate %d", conf->id, conf->baud_rate);
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_uart_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x400, sizeof(luat_uart_t) + 8);
    if (cmd == NULL) {
        LLOGE("内存分配失败!!");
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, conf, sizeof(luat_uart_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_uart_write(int uart_id, void* data, size_t length) {
    // LLOGD("执行uart write %d %p %d", uart_id, data, length);
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    size_t total_len = length + sizeof(luat_airlink_cmd_t) + 8 + 1;
    airlink_queue_item_t item = {.len = total_len};
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x401, length + 1 + 8);
    if (cmd == NULL) {
        LLOGE("内存分配失败!!");
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t tmp = (uint8_t)uart_id;
    memcpy(cmd->data + 8, &tmp, 1);
    memcpy(cmd->data + 9, data, length);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_uart_close(int uart_id) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8 + 1
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x402, 8 + 1);
    if (cmd == NULL) {
        LLOGE("内存分配失败!!");
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t tmp = (uint8_t)uart_id;
    memcpy(cmd->data + 8, &tmp, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

typedef struct drv_uart_buff {
    size_t remain;
    size_t buff_size;
    uint8_t buff[4];
}drv_uart_buff_t;
static drv_uart_buff_t* uart_rx_buffs[10];

int luat_airlink_drv_uart_data_cb(int uart_id, void* buffer, size_t length) {
    // TODO 要接收UART BUFF数据, 返回给用户代码
    if (uart_id >= 10 && uart_id <= 19) {
        uint8_t realy_id = uart_id - 10;
        if (uart_rx_buffs[realy_id] == NULL) {
            uart_rx_buffs[realy_id] = luat_heap_malloc(4096 + sizeof(drv_uart_buff_t));
            if (uart_rx_buffs[realy_id] == NULL) {
                LLOGE("内存分配失败!!");
                return -101;
            }
            uart_rx_buffs[realy_id]->buff_size = 4096;
            uart_rx_buffs[realy_id]->remain = 0;
        }
        if (uart_rx_buffs[realy_id]->remain + length > uart_rx_buffs[realy_id]->buff_size) {
            LLOGE("RX OVERFLOW remain %d income %d", uart_rx_buffs[realy_id]->remain, length);
            memmove(uart_rx_buffs[realy_id]->buff, uart_rx_buffs[realy_id]->buff + uart_rx_buffs[realy_id]->remain, uart_rx_buffs[realy_id]->buff_size - uart_rx_buffs[realy_id]->remain);
            uart_rx_buffs[realy_id]->remain = uart_rx_buffs[realy_id]->buff_size - length;
        }
        memcpy(uart_rx_buffs[realy_id]->buff + uart_rx_buffs[realy_id]->remain,  buffer, length);
        uart_rx_buffs[realy_id]->remain += length;
        
        rtos_msg_t msg = {0};
        msg.handler = l_uart_handler;
        msg.ptr = NULL;
        msg.arg1 = uart_id;
        msg.arg2 = uart_rx_buffs[realy_id]->remain;
        luat_msgbus_put(&msg, 0);
        return 0;
    }
    return 0;
}

int luat_airlink_drv_uart_read(int uart_id, void* data, size_t length) {
    if (uart_id >= 10 && uart_id <= 19) {
        uint8_t realy_id = uart_id - 10;
        if (uart_rx_buffs[realy_id] == NULL) {
            return 0;
        }
        if (data == NULL) {
            return uart_rx_buffs[realy_id]->remain;
        }
        if (length > uart_rx_buffs[realy_id]->remain) {
            length = uart_rx_buffs[realy_id]->remain;
        }
        memcpy(data, uart_rx_buffs[realy_id]->buff, length);
        memmove(uart_rx_buffs[realy_id]->buff, uart_rx_buffs[realy_id]->buff + length, uart_rx_buffs[realy_id]->remain - length);
        uart_rx_buffs[realy_id]->remain -= length;
        // LLOGD("uart[%d] read %d bytes remain %d", uart_id, length, uart_rx_buffs[realy_id]->remain);
        return length;
    }
    return 0;
}
