#ifndef LUAT_AIRLINK_DRV_UART_H
#define LUAT_AIRLINK_DRV_UART_H


#ifndef LUAT_AIRLINK_H
#error "include luat_airlink.h first"
#endif

// uart参数
#include "luat_uart.h"
int luat_airlink_drv_uart_setup(luat_uart_t* uart);
int luat_airlink_drv_uart_write(int uart_id, void* data, size_t length);
int luat_airlink_drv_uart_read(int uart_id, void* buffer, size_t length);
int luat_airlink_drv_uart_close(int uart_id);


#endif
