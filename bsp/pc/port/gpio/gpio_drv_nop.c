#include <stdlib.h>
#include <string.h>//add for memset
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_gpio.h"
#include "luat_gpio_drv.h"

#define LUAT_LOG_TAG "gpio.udp"
#include "luat_log.h"

static int gpio_setup_nop(void* userdata, luat_gpio_t* gpio) {
    return 0;
}

static int gpio_write_nop(void* userdata, int pin, int level) {
    return 0;
}

static int gpio_read_nop(void* userdata, int pin) {
    return 0;
}

static int gpio_close_nop(void* userdata, int pin) {
    return 0;
}


const luat_gpio_drv_opts_t gpio_nop = {
    .setup = gpio_setup_nop,
    .write = gpio_write_nop,
    .read = gpio_read_nop,
    .close = gpio_close_nop,
};
