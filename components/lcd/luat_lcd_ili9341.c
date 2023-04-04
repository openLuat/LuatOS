#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "ili9341"
#include "luat_log.h"

#define LCD_W 240
#define LCD_H 320
#define LCD_DIRECTION 0

static int ili9341_init(luat_lcd_conf_t* conf) {
    if (conf->w == 0)
        conf->w = LCD_W;
    if (conf->h == 0)
        conf->h = LCD_H;
    if (conf->direction == 0)
        conf->direction = LCD_DIRECTION;
#ifdef LUAT_LCD_CMD_DELAY_US
    conf->dc_delay_us = LUAT_LCD_CMD_DELAY_US;
#else
    conf->dc_delay_us = 7;
#endif
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
    lcd_write_cmd(conf,0xCF);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0xD9);
    lcd_write_data(conf,0X30);
    lcd_write_cmd(conf,0xED);
    lcd_write_data(conf,0x64);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0X12);
    lcd_write_data(conf,0X81);
    lcd_write_cmd(conf,0xE8);
    lcd_write_data(conf,0x85);
    lcd_write_data(conf,0x10);
    lcd_write_data(conf,0x78);

    lcd_write_cmd(conf,0xCB);
    lcd_write_data(conf,0x39);
    lcd_write_data(conf,0x2C);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x34);
    lcd_write_data(conf,0x02);

    lcd_write_cmd(conf,0xF7);
    lcd_write_data(conf,0x20);

    lcd_write_cmd(conf,0xEA);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);

    lcd_write_cmd(conf,0xC0);
    lcd_write_data(conf,0x21);
    lcd_write_cmd(conf,0xC1);
    lcd_write_data(conf,0x12);

    lcd_write_cmd(conf,0xC5);
    lcd_write_data(conf,0x32);
    lcd_write_data(conf,0x3C);
    lcd_write_cmd(conf,0xC7);
    lcd_write_data(conf,0XC1);

    lcd_write_cmd(conf,0xC5);
    lcd_write_data(conf,0x1A);
    lcd_write_cmd(conf,0x36);
    lcd_write_data(conf,0x00);

    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0x08);
    else if(conf->direction==1)lcd_write_data(conf,0xC8);
    else if(conf->direction==2)lcd_write_data(conf,0x78);
    else lcd_write_data(conf,0xA8);

    lcd_write_cmd(conf,0x3A);
    lcd_write_data(conf,0x55);
    lcd_write_cmd(conf,0xB1);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x18);
    lcd_write_cmd(conf,0xB6);
    lcd_write_data(conf,0x0A);
    lcd_write_data(conf,0xA2);
    lcd_write_cmd(conf,0xF2);
    lcd_write_data(conf,0x00);
    lcd_write_cmd(conf,0x26);
    lcd_write_data(conf,0x01);

    lcd_write_cmd(conf,0xE0);
    lcd_write_data(conf,0x0F);
    lcd_write_data(conf,0x20);
    lcd_write_data(conf,0x1E);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x12);
    lcd_write_data(conf,0x0B);
    lcd_write_data(conf,0x50);
    lcd_write_data(conf,0XBA);
    lcd_write_data(conf,0x44);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x14);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x23);
    lcd_write_data(conf,0x21);
    lcd_write_data(conf,0x00);

    lcd_write_cmd(conf,0XE1);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x19);
    lcd_write_data(conf,0x19);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x12);
    lcd_write_data(conf,0x07);
    lcd_write_data(conf,0x2D);
    lcd_write_data(conf,0x28);
    lcd_write_data(conf,0x3F);
    lcd_write_data(conf,0x02);
    lcd_write_data(conf,0x0A);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x25);
    lcd_write_data(conf,0x2D);
    lcd_write_data(conf,0x0F);

    /* Sleep Out */
    lcd_write_cmd(conf,0x11);
    /* wait for power stability */
    luat_timer_mdelay(100);
    luat_lcd_clear(conf,BLACK);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

const luat_lcd_opts_t lcd_opts_ili9341 = {
    .name = "ili9341",
    .init = ili9341_init,
};

