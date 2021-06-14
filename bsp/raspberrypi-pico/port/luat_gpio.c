#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "hardware/gpio.h"

static void luat_gpio_irq_callback(uint gpio, uint32_t events)
{
    int pin = (int)gpio;
    int value = gpio_get(pin);
    rtos_msg_t msg;
    msg.handler = l_gpio_handler;
    msg.ptr = NULL;
    msg.arg1 = pin;
    msg.arg2 = value;
    luat_msgbus_put(&msg, 1);
}

int luat_gpio_setup(luat_gpio_t *gpio)
{
    int dir = 0;
    int irq = 0;
    int ret;
    gpio_init(gpio->pin);
    switch (gpio->mode)
    {
    case Luat_GPIO_OUTPUT:
        dir = true;
        break;
    case Luat_GPIO_INPUT:
    case Luat_GPIO_IRQ:
    {
        dir = false;
        switch (gpio->pull)
        {
        case Luat_GPIO_PULLUP:
            gpio_pull_up(gpio->pin);
            break;
        case Luat_GPIO_PULLDOWN:
            gpio_pull_down(gpio->pin);
            break;
        case Luat_GPIO_DEFAULT:
            gpio_disable_pulls(gpio->pin);
        default:
            gpio_disable_pulls(gpio->pin);
            break;
        }
    }
    break;
    default:
        dir = false;
        break;
    }
    gpio_set_dir(gpio->pin, dir);

    if (gpio->mode == Luat_GPIO_IRQ)
    {
        if (gpio->irq == Luat_GPIO_RISING)
        {
            irq = GPIO_IRQ_EDGE_RISE;
        }
        else if (gpio->irq == Luat_GPIO_FALLING)
        {
            irq = GPIO_IRQ_EDGE_FALL;
        }
        else
        {
            irq = GPIO_IRQ_EDGE_RISE;
        }

        gpio_set_irq_enabled_with_callback(gpio->pin, irq, true,  &luat_gpio_irq_callback);

        return 0;
    }
    else
    {
        gpio_set_irq_enabled(gpio->pin, irq, false);
    }
    return 0;
}

int luat_gpio_set(int pin, int level)
{
    gpio_put(pin,level);
    return 0;
}

int luat_gpio_get(int pin)
{
    return (gpio_get(pin)? 1 : 0);
}

void luat_gpio_close(int pin)
{
    gpio_set_dir(pin, false);
    gpio_set_irq_enabled(pin, 0, false);
}
