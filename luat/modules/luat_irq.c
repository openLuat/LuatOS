#include "luat_base.h"
#include "luat_irq.h"
#include "luat_msgbus.h"
#include "luat_gpio.h"
#include "luat_uart.h"

int luat_irq_fire(int tp, int arg, void* args);

int luat_irq_gpio_cb(int pin, void* args) {
    rtos_msg_t msg = {0};
    msg.handler = l_gpio_handler;
    msg.ptr = NULL;
    msg.arg1 = pin;
    msg.arg2 = luat_gpio_get(pin);
    return luat_msgbus_put(&msg, 0);
}

int luat_irq_uart_cb(int id, void* args) {
    int len = (int)(args);
    rtos_msg_t msg = {0};
    msg.handler = l_uart_handler;
    msg.ptr = NULL;
    msg.arg1 = id;
    msg.arg2 = len;
    return luat_msgbus_put(&msg, 0);
}

int luat_irq_spi_cb(int id);

