
#ifndef LUAT_IRQ_H
#define LUAT_IRQ_H
#include "luat_base.h"

int luat_irq_fire(int tp, int arg, void* args);

int luat_irq_gpio_cb(int pin, void* args);

int luat_irq_uart_cb(int uartid, void* args);

int luat_irq_spi_cb(int id);

int32_t luat_irq_hardware_cb_handler(void *pdata, void *param);
#endif
