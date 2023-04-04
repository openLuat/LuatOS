#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "gc9a01"
#include "luat_log.h"

#define LCD_W 240
#define LCD_H 240
#define LCD_DIRECTION 0

static int gc9a01_init(luat_lcd_conf_t* conf) {
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
    luat_lcd_wakeup(conf);
    luat_timer_mdelay(120);
    // 发送初始化命令
    lcd_write_cmd(conf,0xEF);
    lcd_write_cmd(conf,0xEB);
    lcd_write_data(conf,0x14);

    lcd_write_cmd(conf,0xFE);
    lcd_write_cmd(conf,0xEF);

    lcd_write_cmd(conf,0xEB);
    lcd_write_data(conf,0x14);

    lcd_write_cmd(conf,0x84);
    lcd_write_data(conf,0x40);

    lcd_write_cmd(conf,0x85);
    lcd_write_data(conf,0xFF);

    lcd_write_cmd(conf,0x86);
    lcd_write_data(conf,0xFF);
    lcd_write_cmd(conf,0x87);
    lcd_write_data(conf,0xFF);
    lcd_write_cmd(conf,0x88);
    lcd_write_data(conf,0x0A);

    lcd_write_cmd(conf,0x89);
    lcd_write_data(conf,0x21);

    lcd_write_cmd(conf,0x8A);
    lcd_write_data(conf,0x00);

    lcd_write_cmd(conf,0x8B);
    lcd_write_data(conf,0x80);

    lcd_write_cmd(conf,0x8C);
    lcd_write_data(conf,0x01);
    lcd_write_cmd(conf,0x8D);
    lcd_write_data(conf,0x01);
    lcd_write_cmd(conf,0x8E);
    lcd_write_data(conf,0xFF);

    lcd_write_cmd(conf,0x8F);
    lcd_write_data(conf,0xFF);

    lcd_write_cmd(conf,0xB6);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x20);

    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0x08);
    else if(conf->direction==1)lcd_write_data(conf,0xC8);
    else if(conf->direction==2)lcd_write_data(conf,0x68);
    else lcd_write_data(conf,0xA8);

    lcd_write_cmd(conf,0x3A);
    lcd_write_data(conf,0x05);

    lcd_write_cmd(conf,0x90);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x08);

    lcd_write_cmd(conf,0xBD);
    lcd_write_data(conf,0x06);
    lcd_write_cmd(conf,0xBC);
    lcd_write_data(conf,0x00);
    lcd_write_cmd(conf,0xFF);
    lcd_write_data(conf,0x60);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x04);

    lcd_write_cmd(conf,0xC3);
    lcd_write_data(conf,0x13);
    lcd_write_cmd(conf,0xC4);
    lcd_write_data(conf,0x13);

    lcd_write_cmd(conf,0xC9);
    lcd_write_data(conf,0x22);
    lcd_write_cmd(conf,0xBE);
    lcd_write_data(conf,0x11);

    lcd_write_cmd(conf,0xE1);
    lcd_write_data(conf,0x10);
    lcd_write_data(conf,0x0E);

    lcd_write_cmd(conf,0xDF);
    lcd_write_data(conf,0x21);
    lcd_write_data(conf,0x0c);
    lcd_write_data(conf,0x02);

    lcd_write_cmd(conf,0xF0);
    lcd_write_data(conf,0x45);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x26);
    lcd_write_data(conf,0x2A);

    lcd_write_cmd(conf,0xF1);
    lcd_write_data(conf,0x43);
    lcd_write_data(conf,0x70);
    lcd_write_data(conf,0x72);
    lcd_write_data(conf,0x36);
    lcd_write_data(conf,0x37);
    lcd_write_data(conf,0x6F);

    lcd_write_cmd(conf,0xF2);
    lcd_write_data(conf,0x45);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x26);
    lcd_write_data(conf,0x2A);

    lcd_write_cmd(conf,0xF3);
    lcd_write_data(conf,0x43);
    lcd_write_data(conf,0x70);
    lcd_write_data(conf,0x72);
    lcd_write_data(conf,0x36);
    lcd_write_data(conf,0x37);
    lcd_write_data(conf,0x6F);

    lcd_write_cmd(conf,0xED);
    lcd_write_data(conf,0x1B);
    lcd_write_data(conf,0x0B);
    lcd_write_cmd(conf,0xAE);
    lcd_write_data(conf,0x77);
    lcd_write_cmd(conf,0xCD);
    lcd_write_data(conf,0x63);

    lcd_write_cmd(conf,0x70);
    lcd_write_data(conf,0x07);
    lcd_write_data(conf,0x07);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x0E);
    lcd_write_data(conf,0x0F);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x07);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x03);

    lcd_write_cmd(conf,0xE8);
    lcd_write_data(conf,0x34);

    lcd_write_cmd(conf,0x62);
    lcd_write_data(conf,0x18);
    lcd_write_data(conf,0x0D);
    lcd_write_data(conf,0x71);
    lcd_write_data(conf,0xED);
    lcd_write_data(conf,0x70);
    lcd_write_data(conf,0x70);
    lcd_write_data(conf,0x18);
    lcd_write_data(conf,0x0F);
    lcd_write_data(conf,0x71);
    lcd_write_data(conf,0xEF);
    lcd_write_data(conf,0x70);
    lcd_write_data(conf,0x70);

    lcd_write_cmd(conf,0x63);
    lcd_write_data(conf,0x18);
    lcd_write_data(conf,0x11);
    lcd_write_data(conf,0x71);
    lcd_write_data(conf,0xF1);
    lcd_write_data(conf,0x70);
    lcd_write_data(conf,0x70);
    lcd_write_data(conf,0x18);
    lcd_write_data(conf,0x13);
    lcd_write_data(conf,0x71);
    lcd_write_data(conf,0xF3);
    lcd_write_data(conf,0x70);
    lcd_write_data(conf,0x70);

    lcd_write_cmd(conf,0x64);
    lcd_write_data(conf,0x28);
    lcd_write_data(conf,0x29);
    lcd_write_data(conf,0xF1);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0xF1);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x07);

    lcd_write_cmd(conf,0x66);
    lcd_write_data(conf,0x3C);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0xCD);
    lcd_write_data(conf,0x67);
    lcd_write_data(conf,0x45);
    lcd_write_data(conf,0x45);
    lcd_write_data(conf,0x10);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);

    lcd_write_cmd(conf,0x67);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x3C);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x54);
    lcd_write_data(conf,0x10);
    lcd_write_data(conf,0x32);
    lcd_write_data(conf,0x98);

    lcd_write_cmd(conf,0x74);
    lcd_write_data(conf,0x10);
    lcd_write_data(conf,0x85);
    lcd_write_data(conf,0x80);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x4E);
    lcd_write_data(conf,0x00);

    lcd_write_cmd(conf,0x98);
    lcd_write_data(conf,0x3e);
    lcd_write_data(conf,0x07);

    lcd_write_cmd(conf,0x35);
    lcd_write_cmd(conf,0x21);

    /* Sleep Out */
    luat_lcd_wakeup(conf);
    /* wait for power stability */
    luat_timer_mdelay(100);
    luat_lcd_clear(conf,BLACK);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

const luat_lcd_opts_t lcd_opts_gc9a01 = {
    .name = "gc9a01",
    .init = gc9a01_init,
};

