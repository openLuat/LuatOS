#include "luat_base.h"
#include "luat_uart.h"

int luat_uart_setup(luat_uart_t* uart) {
    return -1;
}

int luat_uart_write(int uartid, void* data, size_t length) {
    return 0;
}

int luat_uart_read(int uartid, void* buffer, size_t length) {
    return 0;
}

int luat_uart_close(int uartid) {
    return 0;
}

int luat_uart_exist(int uartid) {
    return 0;
}

int luat_setup_cb(int uartid, int received, int sent) {
    return 0;
}
