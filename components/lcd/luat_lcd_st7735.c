#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "st7735"
#include "luat_log.h"

#define LCD_W 128
#define LCD_H 160
#define LCD_DIRECTION 0

static int st7735_init(luat_lcd_conf_t* conf) {
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
    //------------------------------------ST7735S Frame Rate-----------------------------------------//
    lcd_write_cmd(conf,0xB1);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x3C);
    lcd_write_data(conf,0x3C);
    lcd_write_cmd(conf,0xB2);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x3C);
    lcd_write_data(conf,0x3C);
    lcd_write_cmd(conf,0xB3);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x3C);
    lcd_write_data(conf,0x3C);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x3C);
    lcd_write_data(conf,0x3C);
    //------------------------------------End ST7735S Frame Rate---------------------------------//
    lcd_write_cmd(conf,0xB4);
    lcd_write_data(conf,0x03);
	//------------------------------------ST7735S Power Sequence---------------------------------//
    lcd_write_cmd(conf,0xC0);
    lcd_write_data(conf,0x28);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x04);
    lcd_write_cmd(conf,0xC1);
    lcd_write_data(conf,0XC0);
    lcd_write_cmd(conf,0xC2);
    lcd_write_data(conf,0x0D);
    lcd_write_data(conf,0x00);
    lcd_write_cmd(conf,0xC3);
    lcd_write_data(conf,0x8D);
    lcd_write_data(conf,0x2A);
    lcd_write_cmd(conf,0xC4);
    lcd_write_data(conf,0x8D);
    lcd_write_data(conf,0xEE);
	//---------------------------------End ST7735S Power Sequence-------------------------------------//
    lcd_write_cmd(conf,0xC5);
    lcd_write_data(conf,0x1A);

    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0xC0);
    else if(conf->direction==1)lcd_write_data(conf,0x70);
    else if(conf->direction==2)lcd_write_data(conf,0x00);
    else lcd_write_data(conf,0xA0);
	//------------------------------------ST7735S Gamma Sequence---------------------------------//
	lcd_write_cmd(conf,0xE0);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x22);
    lcd_write_data(conf,0x07);
    lcd_write_data(conf,0x0A);
    lcd_write_data(conf,0x2E);
    lcd_write_data(conf,0x30);
    lcd_write_data(conf,0x25);
    lcd_write_data(conf,0x2A);
    lcd_write_data(conf,0x28);
    lcd_write_data(conf,0x26);
    lcd_write_data(conf,0x2E);
    lcd_write_data(conf,0x3A);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x13);
    lcd_write_cmd(conf,0xE1);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x16);
    lcd_write_data(conf,0x06);
    lcd_write_data(conf,0x0D);
    lcd_write_data(conf,0x2D);
    lcd_write_data(conf,0x26);
    lcd_write_data(conf,0x23);
    lcd_write_data(conf,0x27);
    lcd_write_data(conf,0x27);
    lcd_write_data(conf,0x25);
    lcd_write_data(conf,0x2D);
    lcd_write_data(conf,0x3B);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x13);

    lcd_write_cmd(conf,0x3A);
    lcd_write_data(conf,0x05);

    /* Sleep Out */
    lcd_write_cmd(conf,0x11);
    /* wait for power stability */
    luat_timer_mdelay(100);
    luat_lcd_clear(conf,BLACK);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

const luat_lcd_opts_t lcd_opts_st7735 = {
    .name = "st7735",
    .init = st7735_init,
};

