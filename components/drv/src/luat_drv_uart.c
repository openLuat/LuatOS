#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat/drv_gpio.h"
#include "luat/drv_uart.h"
#include "luat_airlink.h"

#define LUAT_LOG_TAG "drv.uart"
#include "luat_log.h"

int luat_drv_uart_setup(luat_uart_t* uart) {
    if (uart->id >= 10 && uart->id <= 19) {
        return luat_airlink_drv_uart_setup(uart);
    }
    else {
        return luat_uart_setup(uart);
    }
}

int luat_drv_uart_write(int uart_id, void* data, size_t length) {
    if (uart_id >= 10 && uart_id <= 19) {
        return luat_airlink_drv_uart_write(uart_id, data, length);
    }
    else {
        return luat_uart_write(uart_id, data, length);
    }
}

int luat_drv_uart_read(int uart_id, void* buffer, size_t length) {
    if (uart_id >= 10 && uart_id <= 19) {
        return luat_airlink_drv_uart_read(uart_id, buffer, length);
    }
    else {
        return luat_uart_read(uart_id, buffer, length);
    }
}

int luat_drv_uart_close(int uart_id) {
    if (uart_id >= 10 && uart_id <= 19) {
        return luat_airlink_drv_uart_close(uart_id);
    }
    else {
        return luat_uart_close(uart_id);
    }
}