#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>

static void luat_gpio_irq_callback(void* ptr) {
    rt_kprintf("luat_gpio_irq_callback!!!\n");
}

int luat_gpio_setup(luat_gpio_t* gpio) {
    rt_kprintf("gpio setup pin=%d mode=%d irqmode=%d\n", gpio->pin, gpio->mode, gpio->irqmode);
    rt_pin_mode(gpio->pin, gpio->mode);
    // irq ?
    if (gpio->callback) {
        rt_err_t re = rt_pin_attach_irq(gpio->pin, gpio->irqmode, luat_gpio_irq_callback, gpio);
        if (re != RT_EOK) {
            return re;
        }
        return rt_pin_irq_enable(gpio->pin, 1);
    }
    return 0;
}

int luat_gpio_set(int pin, int level) {
    rt_kprintf("gpio set pin=%d level=%d\n", pin, level);
    rt_pin_write(pin, level);
    return 0;
}

int luat_gpio_get(int pin) {
    rt_kprintf("gpio get pin=%d value=%d\n", pin, rt_pin_read(pin));
    return rt_pin_read(pin);
}
