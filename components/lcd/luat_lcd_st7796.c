#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "st7796"
#include "luat_log.h"

#define LCD_W 320
#define LCD_H 420
#define LCD_DIRECTION 0

static int st7796_init(luat_lcd_conf_t* conf) {
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
    lcd_write_cmd(conf,0x11);
    luat_timer_mdelay(120);

    lcd_write_cmd(conf,0Xf0);
	lcd_write_data(conf,0xc3);
	lcd_write_cmd(conf,0Xf0);
	lcd_write_data(conf,0x96);

    /* Memory Data Access Control */
    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0x48);
    else if(conf->direction==1)lcd_write_data(conf,0x88);
    else if(conf->direction==2)lcd_write_data(conf,0x28);
    else if(conf->direction==3)lcd_write_data(conf,0xE8);
    /* RGB 5-6-5-bit  */
    lcd_write_cmd(conf,0x3A);
    lcd_write_data(conf,0x55);

    lcd_write_cmd(conf,0xB4);
    lcd_write_data(conf,0x01);
    lcd_write_cmd(conf,0xB7) ;
    lcd_write_data(conf,0xC6) ;
    lcd_write_cmd(conf,0xe8);
    lcd_write_data(conf,0x40);
    lcd_write_data(conf,0x8a);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x29);
    lcd_write_data(conf,0x19);
    lcd_write_data(conf,0xa5);
    lcd_write_data(conf,0x33);
    lcd_write_cmd(conf,0xc1);
    lcd_write_data(conf,0x06);
    lcd_write_cmd(conf,0xc2);
    lcd_write_data(conf,0xa7);
    lcd_write_cmd(conf,0xc5);
    lcd_write_data(conf,0x18);
    lcd_write_cmd(conf,0xe0); //Positive Voltage Gamma Control
    lcd_write_data(conf,0xf0);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x0b);
    lcd_write_data(conf,0x06);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x15);
    lcd_write_data(conf,0x2f);
    lcd_write_data(conf,0x54);
    lcd_write_data(conf,0x42);
    lcd_write_data(conf,0x3c);
    lcd_write_data(conf,0x17);
    lcd_write_data(conf,0x14);
    lcd_write_data(conf,0x18);
    lcd_write_data(conf,0x1b);
    lcd_write_cmd(conf,0xe1); //Negative Voltage Gamma Control
    lcd_write_data(conf,0xf0);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x0b);
    lcd_write_data(conf,0x06);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x2d);
    lcd_write_data(conf,0x43);
    lcd_write_data(conf,0x42);
    lcd_write_data(conf,0x3b);
    lcd_write_data(conf,0x16);
    lcd_write_data(conf,0x14);
    lcd_write_data(conf,0x17);
    lcd_write_data(conf,0x1b);

    // lcd_write_cmd(conf,0Xe8);
    // lcd_write_data(conf,0x40);
    // lcd_write_data(conf,0x82);
    // lcd_write_data(conf,0x07);
    // lcd_write_data(conf,0x18);
    // lcd_write_data(conf,0x27);
    // lcd_write_data(conf,0x0a);
    // lcd_write_data(conf,0xb6);
    // lcd_write_data(conf,0x33);

    // lcd_write_cmd(conf,0Xc5);
    // lcd_write_data(conf,0x27);

    // lcd_write_cmd(conf,0Xc2);
    // lcd_write_data(conf,0xa7);

    // /* Positive Voltage Gamma Control */
    // lcd_write_cmd(conf,0xE0);
    // lcd_write_data(conf,0xf0);
    // lcd_write_data(conf,0x01);
    // lcd_write_data(conf,0x06);
    // lcd_write_data(conf,0x0f);
    // lcd_write_data(conf,0x12);
    // lcd_write_data(conf,0x1d);
    // lcd_write_data(conf,0x36);
    // lcd_write_data(conf,0x54);
    // lcd_write_data(conf,0x44);
    // lcd_write_data(conf,0x0c);
    // lcd_write_data(conf,0x18);
    // lcd_write_data(conf,0x16);
    // lcd_write_data(conf,0x13);
    // lcd_write_data(conf,0x15);
    // /* Negative Voltage Gamma Control */
    // lcd_write_cmd(conf,0xE1);
    // lcd_write_data(conf,0xf0);
    // lcd_write_data(conf,0x01);
    // lcd_write_data(conf,0x05);
    // lcd_write_data(conf,0x0a);
    // lcd_write_data(conf,0x0b);
    // lcd_write_data(conf,0x07);
    // lcd_write_data(conf,0x32);
    // lcd_write_data(conf,0x44);
    // lcd_write_data(conf,0x44);
    // lcd_write_data(conf,0x0c);
    // lcd_write_data(conf,0x18);
    // lcd_write_data(conf,0x17);
    // lcd_write_data(conf,0x13);
    // lcd_write_data(conf,0x16);

    lcd_write_cmd(conf,0Xf0);
    lcd_write_data(conf,0x3c);

    lcd_write_cmd(conf,0Xf0);
    lcd_write_data(conf,0x69);

    luat_timer_mdelay(100);
    luat_lcd_clear(conf,BLACK);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

const luat_lcd_opts_t lcd_opts_st7796 = {
    .name = "st7796",
    .init = st7796_init,
};

