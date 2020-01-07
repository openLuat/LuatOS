#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>

int luat_gpio_setup(luat_gpio_t gpio) {
    rt_kprintf("gpio setup pin=%d mode=%d pull=%d\n", gpio.pin, gpio.mode, gpio.pull);
    rt_pin_mode(gpio.pin, gpio.mode == LUAT_GPIO_MODE_OUTPUT ? PIN_MODE_OUTPUT : PIN_MODE_INPUT_PULLUP);
    return 0;
}
int luat_gpio_set(luat_gpio_t gpio, int level) {
    rt_kprintf("gpio set pin=%d level=%d\n", gpio.pin, level);
    rt_pin_write(gpio.pin, level);
    return 0;
}
int luat_gpio_get(luat_gpio_t gpio) {
    rt_kprintf("gpio get pin=%d value=%d\n", gpio.pin, rt_pin_read(gpio.pin));
    return rt_pin_read(gpio.pin);
}
