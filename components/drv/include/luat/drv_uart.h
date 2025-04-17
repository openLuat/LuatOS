
#ifndef LUAT_DRV_UART_H
#define LUAT_DRV_UART_H


#include "luat_uart.h"
int luat_drv_uart_setup(luat_uart_t* uart);
int luat_drv_uart_write(int uart_id, void* data, size_t length);
int luat_drv_uart_read(int uart_id, void* buffer, size_t length);
int luat_drv_uart_close(int uart_id);

#endif
