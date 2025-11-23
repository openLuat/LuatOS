#ifndef LUAT_UART_DRV_H
#define LUAT_UART_DRV_H

#include "luat_base.h"
#include "luat_gpio.h"

typedef int (*gpio_setup)(void* userdata, luat_gpio_t* uart);
typedef int (*gpio_write)(void* userdata, int pin, int level);
typedef int (*gpio_read)(void* userdata, int pin);
typedef int (*gpio_close)(void* userdata, int pin);

typedef struct luat_gpio_drv_opts
{
    gpio_setup setup;
    gpio_write write;
    gpio_read read;
    gpio_close close;
}luat_gpio_drv_opts_t;

#endif

