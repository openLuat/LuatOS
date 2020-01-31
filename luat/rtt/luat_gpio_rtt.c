#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>
#include "drivers/pin.h"

void luat_gpio_mode(int pin, int mode) {
    rt_pin_mode(pin, mode);
}

static void luat_gpio_irq_callback(void* ptr) {
    //rt_kprintf("luat_gpio_irq_callback!!!\n");
    luat_gpio_t* gpio = (luat_gpio_t*)ptr;
    rtos_msg_t msg;
    msg.handler = gpio->func;
    msg.ptr = ptr;
    luat_msgbus_put(&msg, 1);
}

int luat_gpio_setup(luat_gpio_t* gpio) {
    int mode = 0;
    switch (gpio->mode)
    {
    case Luat_GPIO_OUTPUT:
        mode = PIN_MODE_OUTPUT;
        break;
    case Luat_GPIO_INPUT:
    case Luat_GPIO_IRQ:
        {
            switch (gpio->pull)
            {
            case Luat_GPIO_PULLUP:
                mode = PIN_MODE_INPUT_PULLDOWN;
                break;
            case Luat_GPIO_PULLDOWN:
                mode = PIN_MODE_INPUT_PULLDOWN;
                break;
            
            case Luat_GPIO_DEFAULT:
            default:
                mode = PIN_MODE_INPUT;
                break;
            }
        }
        break;
    default:
        mode = PIN_MODE_INPUT;
        break;
    }
    rt_pin_mode(gpio->pin, mode);
    if (gpio->mode == Luat_GPIO_IRQ) {
        int irq = 0;
        if (gpio->irq == Luat_GPIO_RISING) {
            irq = PIN_IRQ_MODE_RISING;
        }
        else if (gpio->irq == Luat_GPIO_FALLING) {
            irq = PIN_IRQ_MODE_FALLING;
        }
        else {
            irq = PIN_IRQ_MODE_RISING_FALLING;
        }
        rt_err_t re = rt_pin_attach_irq(gpio->pin, irq, luat_gpio_irq_callback, gpio);
        if (re != RT_EOK) {
            return re;
        }
        return rt_pin_irq_enable(gpio->pin, 1);
    }
    else {
        rt_pin_irq_enable(gpio->pin, 0);
    }
    return 0;
}

int luat_gpio_set(int pin, int level) {
    //rt_kprintf("gpio set pin=%d level=%d\n", pin, level);
    rt_pin_write(pin, level);
    return 0;
}

int luat_gpio_get(int pin) {
    //rt_kprintf("gpio get pin=%d value=%d\n", pin, rt_pin_read(pin));
    return rt_pin_read(pin);
}

void luat_gpio_close(int pin) {
    rt_pin_mode(pin, PIN_MODE_INPUT);
    rt_pin_irq_enable(pin, 0);
}
