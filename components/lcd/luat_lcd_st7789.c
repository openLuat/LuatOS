#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "st7789"
#include "luat_log.h"

#define LCD_W 240
#define LCD_H 320
#define LCD_DIRECTION 0

static int st7789_init(luat_lcd_conf_t* conf) {
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
    /* Memory Data Access Control */
    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0x00);
    else if(conf->direction==1)lcd_write_data(conf,0xC0);
    else if(conf->direction==2)lcd_write_data(conf,0x70);
    else if(conf->direction==3)lcd_write_data(conf,0xA0);
    /* RGB 5-6-5-bit  */
    lcd_write_cmd(conf,0x3A);
    lcd_write_data(conf,0x05);
    /* Porch Setting */
    lcd_write_cmd(conf,0xB2);
    lcd_write_data(conf,0x0C);
    lcd_write_data(conf,0x0C);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x33);
    lcd_write_data(conf,0x33);
    /*  Gate Control */
    lcd_write_cmd(conf,0xB7);
    lcd_write_data(conf,0x35);
    /* VCOM Setting */
    lcd_write_cmd(conf,0xBB);
    lcd_write_data(conf,0x32);
    /* LCM Control */
    // lcd_write_cmd(conf,0xC0);
    // lcd_write_data(conf,0x2C);
    /* VDV and VRH Command Enable */
    lcd_write_cmd(conf,0xC2);
    lcd_write_data(conf,0x01);
    /* VRH Set */
    lcd_write_cmd(conf,0xC3);
    lcd_write_data(conf,0x15);
    /* VDV Set */
    lcd_write_cmd(conf,0xC4);
    lcd_write_data(conf,0x20);
    /* Frame Rate Control in Normal Mode */
    lcd_write_cmd(conf,0xC6);
    lcd_write_data(conf,0x0F);
    /* Power Control 1 */
    lcd_write_cmd(conf,0xD0);
    lcd_write_data(conf,0xA4);
    lcd_write_data(conf,0xA1);
    /* Positive Voltage Gamma Control */
    lcd_write_cmd(conf,0xE0);
    lcd_write_data(conf,0xD0);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x0E);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x31);
    lcd_write_data(conf,0x33);
    lcd_write_data(conf,0x48);
    lcd_write_data(conf,0x17);
    lcd_write_data(conf,0x14);
    lcd_write_data(conf,0x15);
    lcd_write_data(conf,0x31);
    lcd_write_data(conf,0x34);
    /* Negative Voltage Gamma Control */
    lcd_write_cmd(conf,0xE1);
    lcd_write_data(conf,0xD0);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x0E);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x15);
    lcd_write_data(conf,0x31);
    lcd_write_data(conf,0x33);
    lcd_write_data(conf,0x48);
    lcd_write_data(conf,0x17);
    lcd_write_data(conf,0x14);
    lcd_write_data(conf,0x15);
    lcd_write_data(conf,0x31);
    lcd_write_data(conf,0x34);
    /* Display Inversion On */
    lcd_write_cmd(conf,0x21);
    /* Sleep Out */
    lcd_write_cmd(conf,0x11);
    /* wait for power stability */
    luat_timer_mdelay(100);
    luat_lcd_clear(conf,BLACK);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

const luat_lcd_opts_t lcd_opts_st7789 = {
    .name = "st7789",
    .init = st7789_init,
};

