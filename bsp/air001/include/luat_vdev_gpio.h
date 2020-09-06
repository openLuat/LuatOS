
#include "luat_base.h"
#include "luat_gpio.h"

// GPIO 设备
typedef struct luat_vdev_gpio_pin
{
    uint8_t valid;
    uint8_t mode;
    uint8_t value;
    uint8_t pull;
    uint32_t ref;
}luat_vdev_gpio_pin_t;

typedef struct luat_vdev_gpio
{
    size_t count;
    luat_vdev_gpio_pin_t pins[256];
}luat_vdev_gpio_t;

int luat_vdev_gpio_init(void);
