#include "luat_base.h"

int luat_irq_fire(int tp, void* args);

int luat_irq_gpio_cb(int pin);

int luat_irq_uart_cb(int id, int len);

int luat_irq_spi_cb(int id);

