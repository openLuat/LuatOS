
#ifndef LUAT_DRV_GPIO_H
#define LUAT_DRV_GPIO_H


#include "luat_gpio.h"
int luat_drv_gpio_open(luat_gpio_cfg_t* gpio);
int luat_drv_gpio_set(int pin, int level);
int luat_drv_gpio_setup(luat_gpio_t* gpio);
int luat_drv_gpio_get(int pin, int* val);
int luat_drv_gpio_driver_yhm27xx(uint32_t Pin, uint8_t ChipID, uint8_t RegAddress, uint8_t IsRead, uint8_t *Data);

#endif
