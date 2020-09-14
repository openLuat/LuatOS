
#include "luat_uart.h"
#include "luat_malloc.h"

#include "iot_uart.h"

int luat_uart_write(int uartid, void* data, size_t length) {
    iot_uart_write(OPENAT_UART_USB, data, length);
    return 0;
}
