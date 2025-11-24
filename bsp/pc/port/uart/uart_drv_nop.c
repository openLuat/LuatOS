#include <stdlib.h>
#include <string.h>//add for memset
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_uart.h"
#include "luat_uart_drv.h"

#define LUAT_LOG_TAG "uart.udp"
#include "luat_log.h"

static int uart_setup_nop(void* userdata, luat_uart_t* uart) {
    return -1;
}

static int uart_write_nop(void* userdata, int uart_id, void* data, size_t length) {
    return -1;
}

static int uart_read_nop(void* userdata, int uart_id, void* buffer, size_t length) {
    return -1;
}

static int uart_close_nop(void* userdata, int uart_id) {
    return -1;
}


const luat_uart_drv_opts_t uart_nop = {
    .setup = uart_setup_nop,
    .write = uart_write_nop,
    .read = uart_read_nop,
    .close = uart_close_nop,
};
