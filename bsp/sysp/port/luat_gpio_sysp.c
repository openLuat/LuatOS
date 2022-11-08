#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_msgbus.h"

int luat_gpio_setup(luat_gpio_t* gpio) {
    return 0;
}

int luat_gpio_set(int pin, int level) {
    return 0;
}

int luat_gpio_get(int pin) {
    return 0;
}

void luat_gpio_close(int pin) {
}

void luat_gpio_pulse(int pin, uint8_t *level, uint16_t len, uint16_t delay_ns) {

}
