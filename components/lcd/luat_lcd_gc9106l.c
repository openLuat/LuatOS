#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "gc9106l"
#include "luat_log.h"

#define LCD_W 128
#define LCD_H 160
#define LCD_DIRECTION 0

static int gc9106l_init(luat_lcd_conf_t* conf) {
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
    //------------------------------------gc9106lS Frame Rate-----------------------------------------//
    lcd_write_cmd(conf,0xFE);
    lcd_write_cmd(conf,0xEF);
    lcd_write_cmd(conf,0xB3);
    lcd_write_data(conf,0x03);

    lcd_write_cmd(conf,0x21);
    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0xC8);
    else if(conf->direction==1)lcd_write_data(conf,0x08);
    else if(conf->direction==2)lcd_write_data(conf,0x68);
    else lcd_write_data(conf,0xA8);

    lcd_write_cmd(conf,0x3A);
    lcd_write_data(conf,0x05);
    lcd_write_cmd(conf,0xB4);
    lcd_write_data(conf,0x21);

    lcd_write_cmd(conf,0xF0);
    lcd_write_data(conf,0x2D);
    lcd_write_data(conf,0x54);
    lcd_write_data(conf,0x24);
    lcd_write_data(conf,0x61);
    lcd_write_data(conf,0xAB);
	lcd_write_data(conf,0x2E);
    lcd_write_data(conf,0x2F);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x20);
    lcd_write_data(conf,0x10);
    lcd_write_data(conf,0X10);
    lcd_write_data(conf,0x17);
    lcd_write_data(conf,0x13);
    lcd_write_data(conf,0x0F);

    lcd_write_cmd(conf,0xF1);
    lcd_write_data(conf,0x02);
    lcd_write_data(conf,0x22);
    lcd_write_data(conf,0x25);
    lcd_write_data(conf,0x35);
    lcd_write_data(conf,0xA8);
	lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0X09);
    lcd_write_data(conf,0x17);
    lcd_write_data(conf,0x18);
    lcd_write_data(conf,0x0F);

    lcd_write_cmd(conf,0xFE);
    lcd_write_cmd(conf,0xFF);

    /* Sleep Out */
    lcd_write_cmd(conf,0x11);
    /* wait for power stability */
    luat_timer_mdelay(100);
    luat_lcd_clear(conf,BLACK);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

const luat_lcd_opts_t lcd_opts_gc9106l = {
    .name = "gc9106l",
    .init = gc9106l_init,
};

