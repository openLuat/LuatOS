#ifndef LUAT_UART_DRV_H
#define LUAT_UART_DRV_H

#include "luat_base.h"
#include "luat_uart.h"

typedef int (*uart_setup)(void* userdata, luat_uart_t* uart);
typedef int (*uart_write)(void* userdata, int uart_id, void* data, size_t length);
typedef int (*uart_read)(void* userdata, int uart_id, void* buffer, size_t length);
typedef int (*uart_close)(void* userdata, int uart_id);

typedef struct luat_uart_drv_opts
{
    uart_setup setup;
    uart_write write;
    uart_read read;
    uart_close close;
}luat_uart_drv_opts_t;

#endif

