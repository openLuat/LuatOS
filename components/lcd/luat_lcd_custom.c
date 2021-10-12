#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "custom"
#include "luat_log.h"

#define LCD_W 240
#define LCD_H 320
#define LCD_DIRECTION 0

static int custom_sleep(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_timer_mdelay(5);
    luat_lcd_custom_t * cst = (luat_lcd_custom_t *)conf->userdata;
    luat_lcd_execute_cmds(conf, &cst->sleepcmd, 1);
    return 0;
}

static int custom_wakeup(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_timer_mdelay(5);
    luat_lcd_custom_t * cst = (luat_lcd_custom_t *)conf->userdata;
    luat_lcd_execute_cmds(conf, &cst->wakecmd, 1);
    return 0;
}

static int custom_close(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}

static int custom_init(luat_lcd_conf_t* conf) {

    if (conf->w == 0 || conf->h == 0)
        conf->h = LCD_H;
    if (conf->direction == 0)
        conf->direction = LCD_DIRECTION;
    luat_gpio_mode(conf->pin_dc, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH); // DC
    luat_gpio_mode(conf->pin_pwr, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW); // POWER
    luat_gpio_mode(conf->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW); // RST

    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_LOW);
    luat_timer_mdelay(100);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_HIGH);

    // 发送初始化命令
    luat_lcd_custom_t * cst = (luat_lcd_custom_t *)conf->userdata;
    luat_lcd_execute_cmds(conf, cst->initcmd, cst->init_cmd_count);
    return 0;
};

const luat_lcd_opts_t lcd_opts_custom = {
    .name = "custom",
    .init = custom_init,
    .close = custom_close,
    .sleep = custom_sleep,
    .wakeup = custom_wakeup,
};

