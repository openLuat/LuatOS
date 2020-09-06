
#include "luat_vdev_uart.h"

int luat_vdev_uart_init(void) {
    return 0;
}

int luat_uart_setup(luat_uart_t* uart) {
    return 0;
}
int luat_uart_write(int uartid, void* data, size_t length) {
    for (size_t i = 0; i < length; i++)
    {
        char* c = data+i;
        putchar(*c);
    }
    
    return 0;
}
int luat_uart_read(int uartid, void* buffer, size_t length) {
    return -1;
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
