#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "gc9306x"
#include "luat_log.h"

#define LCD_W 240
#define LCD_H 320
#define LCD_DIRECTION 0

static int gc9306x_init(luat_lcd_conf_t* conf) {
    if (conf->w == 0)
        conf->w = LCD_W;
    if (conf->h == 0)
        conf->h = LCD_H;
    if (conf->direction == 0)
        conf->direction = LCD_DIRECTION;

    if (conf->pin_pwr != 255)
        luat_gpio_mode(conf->pin_pwr, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW); // POWER
    luat_gpio_mode(conf->pin_dc, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH); // DC
    luat_gpio_mode(conf->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW); // RST

    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_LOW);
    luat_timer_mdelay(100);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_HIGH);
    luat_timer_mdelay(120);
    // 发送初始化命令
    lcd_write_cmd(conf,0xfe);
    lcd_write_cmd(conf,0xef);

    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0x48);
    else if(conf->direction==1)lcd_write_data(conf,0xE8);
    else if(conf->direction==2)lcd_write_data(conf,0x28);
    else lcd_write_data(conf,0xF8);

    lcd_write_cmd(conf,0x3a);
    lcd_write_data(conf,0x05);

    lcd_write_cmd(conf,0xad);
    lcd_write_data(conf,0x33);
    lcd_write_cmd(conf,0xaf);
    lcd_write_data(conf,0x55);
    lcd_write_cmd(conf,0xae);
    lcd_write_data(conf,0x2b);

    lcd_write_cmd(conf,0xa4);
    lcd_write_data(conf,0x44);
    lcd_write_data(conf,0x44);

    lcd_write_cmd(conf,0xa5);
    lcd_write_data(conf,0x42);
    lcd_write_data(conf,0x42);

    lcd_write_cmd(conf,0xaa);
    lcd_write_data(conf,0x88);
    lcd_write_data(conf,0x88);

    lcd_write_cmd(conf,0xae);
    lcd_write_data(conf,0x2b);

    lcd_write_cmd(conf,0xe8);
    lcd_write_data(conf,0x11);
    lcd_write_data(conf,0x0b);

    lcd_write_cmd(conf,0xe3);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x10);

    lcd_write_cmd(conf,0xff);
    lcd_write_data(conf,0x61);
    lcd_write_cmd(conf,0xac);
    lcd_write_data(conf,0x00);

    lcd_write_cmd(conf,0xaf);
    lcd_write_data(conf,0x67);
    lcd_write_cmd(conf,0xa6);
    lcd_write_data(conf,0x2a);
    lcd_write_data(conf,0x2a);

    lcd_write_cmd(conf,0xa7);
    lcd_write_data(conf,0x2b);
    lcd_write_data(conf,0x2b);

    lcd_write_cmd(conf,0xa8);
    lcd_write_data(conf,0x18);
    lcd_write_data(conf,0x18);

    lcd_write_cmd(conf,0xa9);
    lcd_write_data(conf,0x2a);
    lcd_write_data(conf,0x2a);

    lcd_write_cmd(conf,0x2a);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0xef);
    lcd_write_cmd(conf,0x2b);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x3f);
    lcd_write_cmd(conf,0x2c);

    lcd_write_cmd(conf,0xF0);
    lcd_write_data(conf,0x02);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x1b);
    lcd_write_data(conf,0x1f);
    lcd_write_data(conf,0x0b);

    lcd_write_cmd(conf,0xF1);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x28);
    lcd_write_data(conf,0x2b);
    lcd_write_data(conf,0x0e);

    lcd_write_cmd(conf,0xF2);
    lcd_write_data(conf,0x0b);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x3b);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x4c);

    lcd_write_cmd(conf,0xF3);
    lcd_write_data(conf,0x0e);
    lcd_write_data(conf,0x07);
    lcd_write_data(conf,0x46);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x51);

    lcd_write_cmd(conf,0xF4);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x15);
    lcd_write_data(conf,0x15);
    lcd_write_data(conf,0x1f);
    lcd_write_data(conf,0x22);
    lcd_write_data(conf,0x0F);

    lcd_write_cmd(conf,0xF5);
    lcd_write_data(conf,0x0b);
    lcd_write_data(conf,0x13);
    lcd_write_data(conf,0x11);
    lcd_write_data(conf,0x1f);
    lcd_write_data(conf,0x21);
    lcd_write_data(conf,0x0F);

    /* Sleep Out */
    lcd_write_cmd(conf,0x11);
    /* wait for power stability */
    luat_timer_mdelay(100);
    lcd_write_cmd(conf,0x2c);
    luat_lcd_clear(conf,BLACK);
    /* display on */
    luat_lcd_display_on(conf);
    lcd_write_cmd(conf,0x2c);
    return 0;
};

const luat_lcd_opts_t lcd_opts_gc9306x = {
    .name = "gc9306x",
    .init = gc9306x_init,
};

