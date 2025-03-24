#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat/drv_gpio.h"
#include "luat_airlink.h"

#define LUAT_LOG_TAG "drv.gpio"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

int luat_drv_gpio_open(luat_gpio_cfg_t* gpio) {
    if (gpio == NULL) {
        return -1;
    }
    if (gpio->pin < 0 || gpio->pin >= 255) {
        return -2;
    }
    if (gpio->pin < 128) {
        return luat_gpio_open(gpio);
    }
    else {
        return luat_airlink_drv_gpio_open(gpio);
    }
}

int luat_drv_gpio_set(int pin, int level) {
    if (pin < 0 || pin >= 255) {
        return -1;
    }
    if (pin < 128) {
        return luat_gpio_set(pin, level);
    }
    else {
        return luat_airlink_drv_gpio_set(pin, level);
    }
}

int luat_drv_gpio_setup(luat_gpio_t* gpio) {
    LLOGD("执行luat_drv_gpio_setup pin %d mode %d", gpio->pin, gpio->mode);
    if (gpio == NULL) {
        return -1;
    }
    if (gpio->pin < 0 || gpio->pin >= 255) {
        return -2;
    }
    if (gpio->pin < 128) {
        return luat_gpio_setup(gpio);
    }
    else {
        return luat_airlink_drv_gpio_setup(gpio);
    }
}
