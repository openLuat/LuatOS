#ifndef LUAT_AIRLINK_DRV_GPIO_H
#define LUAT_AIRLINK_DRV_GPIO_H


#ifndef LUAT_AIRLINK_H
#error "include luat_airlink.h first"
#endif

// GPIO 操作, 临时放这里
#include "luat_gpio.h"
int luat_airlink_drv_gpio_setup(luat_gpio_t* gpio);
int luat_airlink_drv_gpio_set(int pin, int level);
int luat_airlink_drv_gpio_open(luat_gpio_cfg_t* gpio);
int luat_airlink_drv_gpio_get(int pin, int* val);

#endif
