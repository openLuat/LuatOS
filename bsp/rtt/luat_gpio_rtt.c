#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>
#include "drivers/pin.h"

#define DBG_TAG           "luat.gpio"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

// void luat_gpio_mode(int pin, int mode) {
//     rt_pin_mode(pin, mode);
// }

static void luat_gpio_irq_callback(void* ptr) {
    //LOG_D("IRQ Callback");
    int pin = (int)ptr;
    int value = rt_pin_read(pin);
    rtos_msg_t msg;
    msg.handler = l_gpio_handler;
    msg.ptr = RT_NULL;
    msg.arg1 = pin;
    msg.arg2 = value;
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
                mode = PIN_MODE_INPUT_PULLUP;
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
        rt_err_t re = rt_pin_attach_irq(gpio->pin, irq, luat_gpio_irq_callback, (void*)gpio->pin);
        if (re != RT_EOK) {
            return re;
        }
        rt_pin_irq_enable(gpio->pin, 1);
    }
    else {
        rt_pin_irq_enable(gpio->pin, 0);
    }
    rt_pin_mode(gpio->pin, mode);
    return 0;
}

int luat_gpio_set(int pin, int level) {
    LOG_D("Pin set pin=%d level=%d", pin, level);
    rt_pin_write(pin, level);
    return 0;
}

int luat_gpio_get(int pin) {
    int re = rt_pin_read(pin);
    LOG_D("Pin get pin=%d value=%d", pin, re);
    return re;
}

void luat_gpio_close(int pin) {
    LOG_D("Pin Close, pin=%d", pin);
    rt_pin_irq_enable(pin, 0);
    rt_pin_mode(pin, PIN_MODE_INPUT);
}
