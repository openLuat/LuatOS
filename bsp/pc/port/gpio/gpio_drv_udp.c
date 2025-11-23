#include <stdlib.h>
#include <string.h>//add for memset
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_gpio.h"
#include "luat_gpio_drv.h"

#define LUAT_LOG_TAG "gpio.udp"
#include "luat_log.h"

static int gpio_setup_udp(void* userdata, luat_gpio_t* gpio) {
    return 0;
}

static int gpio_write_udp(void* userdata, int pin, int level) {
    return 0;
}

static int gpio_read_udp(void* userdata, int pin) {
    return 0;
}

static int gpio_close_udp(void* userdata, int pin) {
    return 0;
}

// 还得想想
void gpio_udp_init(void) {

}

const luat_gpio_drv_opts_t gpio_udp = {
    .setup = gpio_setup_udp,
    .write = gpio_write_udp,
    .read = gpio_read_udp,
    .close = gpio_close_udp,
};
