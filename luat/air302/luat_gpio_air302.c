#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "gpio_ec616.h"

void luat_gpio_mode(int pin, int mode) {
    //rt_pin_mode(pin, mode);
    // 这是留给sensor框架的接口,鉴于ec616还不能适配,那就先不管了
}

static void luat_gpio_irq_callback(void* ptr) {
    //LOG_D("IRQ Callback");
    int pin = (int)ptr;
    int value = GPIO_PinRead(0, 1 << pin);
    rtos_msg_t msg;
    msg.handler = l_gpio_handler;
    msg.ptr = 0;
    msg.arg1 = pin;
    msg.arg2 = value;
    luat_msgbus_put(&msg, 1);
}

int luat_gpio_setup(luat_gpio_t* gpio) {
    int mode = gpio->mode;
    gpio_pin_config_t config;
    config.pinDirection = gpio->mode != Luat_GPIO_OUTPUT ? GPIO_DirectionInput : GPIO_DirectionOutput;
    GPIO_PinConfig(0, 1 << gpio->pin, &config);
    if (gpio->mode == Luat_GPIO_IRQ) {
        int irq = GPIO_InterruptDisabled;
        if (gpio->irq == Luat_GPIO_RISING) {
            irq = GPIO_InterruptRisingEdge;
        }
        else if (gpio->irq == Luat_GPIO_FALLING) {
            irq = GPIO_InterruptFallingEdge;
        }
        else {
            irq = GPIO_InterruptRisingEdge;
        }
        GPIO_InterruptConfig(0, 1 << gpio->pin, irq);
    }
    return 0;
}

int luat_gpio_set(int pin, int level) {
    //LOG_D("Pin set pin=%d level=%d", pin, level);
    GPIO_PinWrite(0, 1 << pin, level);
    return 0;
}

int luat_gpio_get(int pin) {
    int re = GPIO_PinRead(0, 1 << pin);
    //LOG_D("Pin get pin=%d value=%d", pin, re);
    return re;
}

void luat_gpio_close(int pin) {
    //LOG_D("Pin Close, pin=%d", pin);
    gpio_pin_config_t config;
    config.pinDirection = GPIO_DirectionInput;
    GPIO_PinConfig(0, 1 << pin, &config);
}
