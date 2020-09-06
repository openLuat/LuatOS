
#include "luat_vdev_gpio.h"
#include "luat_gpio.h"

int luat_vdev_gpio_init(void) {
    return 0;
}

void luat_gpio_mode(int pin, int mode, int pull, int initOutput) {
    
}
int luat_gpio_setup(luat_gpio_t* gpio) {
    return -1;
}
int luat_gpio_set(int pin, int level) {
    return -1;
}
int luat_gpio_get(int pin) {
    return -1;
}
void luat_gpio_close(int pin) {
    // nop
}
