#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_msgbus.h"

// 模拟GPIO在win32下的实现

int l_gpio_handler(lua_State *L, void* ptr) ;

#define LUAT_WIN32_GPIO_COUNT (32)

typedef struct gpio_state {
    luat_gpio_t gpio;
    uint8_t open;
    uint8_t state;
}gpio_state_t;

gpio_state_t win32gpios[LUAT_WIN32_GPIO_COUNT] = {0};

int luat_gpio_setup(luat_gpio_t* gpio) {
    if (gpio->pin < 0 || gpio->pin >= LUAT_WIN32_GPIO_COUNT) {
        return -1;
    }
    memcpy(&win32gpios[gpio->pin], gpio, sizeof(luat_gpio_t));
    win32gpios[gpio->pin].open = 1;
    if (gpio->mode == Luat_GPIO_OUTPUT) {
        win32gpios[gpio->pin].state = gpio->irq;
    }
    else {
        win32gpios[gpio->pin].state = 0;
    }
    return 0;
}

int luat_gpio_set(int pin, int level) {
    if (pin < 0 || pin >= LUAT_WIN32_GPIO_COUNT) {
        return -1;
    }
    if (win32gpios[pin].open == 0) {
        return -1;
    }
    
    if (win32gpios[pin].state != level) {
        win32gpios[pin].state = level;
        rtos_msg_t msg = {0};
        msg.ptr = NULL;
        msg.arg1 = pin;
        msg.arg2 = level;
        msg.handler = l_gpio_handler;
        luat_msgbus_put(&msg, 0);
    };
    return 0;
}

int luat_gpio_get(int pin) {
    if (pin < 0 || pin >= LUAT_WIN32_GPIO_COUNT) {
        return 0;
    }
    if (win32gpios[pin].open == 0) {
        return 0;
    }
    return win32gpios[pin].state;
}
void luat_gpio_close(int pin) {
    if (pin < 0 || pin >= LUAT_WIN32_GPIO_COUNT) {
        return;
    }
    win32gpios[pin].open = 0;
}