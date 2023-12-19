#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "custom"
#include "luat_log.h"

luat_lcd_opts_t lcd_opts_custom = {
    .name = "custom",
};

