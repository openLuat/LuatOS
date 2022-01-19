
#include "luat_base.h"
#include "luat_conf_bsp.h"

#include "rtthread.h"
#include <rtdevice.h>

extern rt_device_t luat_log_uart_device;

void luat_nprint(char *s, size_t l) {
    rt_device_write(luat_log_uart_device, 0, s, l);
}

void luat_log_write(char *s, size_t l) {
    rt_device_write(luat_log_uart_device, 0, s, l);
}

