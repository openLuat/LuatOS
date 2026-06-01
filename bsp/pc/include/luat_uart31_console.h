#ifndef LUAT_UART31_CONSOLE_H
#define LUAT_UART31_CONSOLE_H

#include "luat_base.h"
#include "luat_uart_drv.h"

typedef void (*luat_uart31_console_visit_cb_t)(int is_tx, uint64_t ts_ms, const uint8_t* data, size_t len, void* userdata);

extern const luat_uart_drv_opts_t uart_console31;

void luat_uart31_console_mount(void);
int luat_uart31_console_inject_rx(const uint8_t* data, size_t len);
void luat_uart31_console_visit_history(luat_uart31_console_visit_cb_t cb, void* userdata);

#endif
