#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "ili9488"
#include "luat_log.h"

#define LCD_W 320
#define LCD_H 480
#define LCD_DIRECTION 0

static int ili9488_sleep(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x10);
    return 0;
}

static int ili9488_wakeup(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x11);
    //luat_timer_mdelay(120); // 外部休眠就好了吧
    return 0;
}

static int ili9488_close(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}
static int ili9488_init(luat_lcd_conf_t* conf) {
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


    // // 发送初始化命令
    lcd_write_cmd(conf,0xE0);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x16);
    lcd_write_data(conf,0x0A);
    lcd_write_data(conf,0x3F);
    lcd_write_data(conf,0x78);
    lcd_write_data(conf,0x4C);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x0A);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x16);
    lcd_write_data(conf,0x1A);
    lcd_write_data(conf,0x0F);

    lcd_write_cmd(conf,0xE1);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x16);
    lcd_write_data(conf,0x19);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x0F);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x32);
    lcd_write_data(conf,0x45);
    lcd_write_data(conf,0x46);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x0E);
    lcd_write_data(conf,0x0D);
    lcd_write_data(conf,0x35);
    lcd_write_data(conf,0x37);
    lcd_write_data(conf,0x0F);

    lcd_write_cmd(conf,0xC0);
    lcd_write_data(conf,0x17);
    lcd_write_data(conf,0x15);

    lcd_write_cmd(conf,0xC1);
    lcd_write_data(conf,0x41);

    lcd_write_cmd(conf,0xC5);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x12);
    lcd_write_data(conf,0x80);

    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0x48);
    else if(conf->direction==1)lcd_write_data(conf,0x88);
    else if(conf->direction==2)lcd_write_data(conf,0x28);
    else lcd_write_data(conf,0xE8);

    lcd_write_cmd(conf,0x3A);
    // lcd_write_data(conf,0x55);
    lcd_write_data(conf,0x66);

    lcd_write_cmd(conf,0XB0);
    lcd_write_data(conf,0x00);
    lcd_write_cmd(conf,0xB1);
    lcd_write_data(conf,0xA0);
    lcd_write_cmd(conf,0xB4);
    lcd_write_data(conf,0x02);
    lcd_write_cmd(conf,0xB6);
    lcd_write_data(conf,0x02);
    lcd_write_data(conf,0x02);
    lcd_write_data(conf,0x3B);

    lcd_write_cmd(conf,0xB7);
    lcd_write_data(conf,0xC6);

    lcd_write_cmd(conf,0XF7);
    lcd_write_data(conf,0xA9);
    lcd_write_data(conf,0x51);
    lcd_write_data(conf,0x2C);
    lcd_write_data(conf,0x82);

    // 发送初始化命令
    // lcd_write_cmd(conf,0xE0);
    // lcd_write_data(conf,0x00);
    // lcd_write_data(conf,0x07);
    // lcd_write_data(conf,0x0f);
    // lcd_write_data(conf,0x0D);
    // lcd_write_data(conf,0x1B);
    // lcd_write_data(conf,0x0A);
    // lcd_write_data(conf,0x3c);
    // lcd_write_data(conf,0x78);
    // lcd_write_data(conf,0x4A);
    // lcd_write_data(conf,0x07);
    // lcd_write_data(conf,0x0E);
    // lcd_write_data(conf,0x09);
    // lcd_write_data(conf,0x1B);
    // lcd_write_data(conf,0x1e);
    // lcd_write_data(conf,0x0f);

    // lcd_write_cmd(conf,0xE1);
    // lcd_write_data(conf,0x00);
    // lcd_write_data(conf,0x22);
    // lcd_write_data(conf,0x24);
    // lcd_write_data(conf,0x06);
    // lcd_write_data(conf,0x12);
    // lcd_write_data(conf,0x07);
    // lcd_write_data(conf,0x36);
    // lcd_write_data(conf,0x47);
    // lcd_write_data(conf,0x47);
    // lcd_write_data(conf,0x06);
    // lcd_write_data(conf,0x0a);
    // lcd_write_data(conf,0x07);
    // lcd_write_data(conf,0x30);
    // lcd_write_data(conf,0x37);
    // lcd_write_data(conf,0x0f);

    // lcd_write_cmd(conf,0xC0);
    // lcd_write_data(conf,0x10);
    // lcd_write_data(conf,0x10);

    // lcd_write_cmd(conf,0xC1);
    // lcd_write_data(conf,0x41);

    // lcd_write_cmd(conf,0xC5);
    // lcd_write_data(conf,0x00);
    // lcd_write_data(conf,0x22);
    // lcd_write_data(conf,0x80);

    // lcd_write_cmd(conf,0x36);
    // if(conf->direction==0)lcd_write_data(conf,0x48);
    // else if(conf->direction==1)lcd_write_data(conf,0x88);
    // else if(conf->direction==2)lcd_write_data(conf,0x28);
    // else lcd_write_data(conf,0xE8);

    // lcd_write_cmd(conf,0x3A);
    // lcd_write_data(conf,0x66);

    // lcd_write_cmd(conf,0XB0);
    // lcd_write_data(conf,0x00);
    // lcd_write_cmd(conf,0xB1);
    // lcd_write_data(conf,0xB0);
    // lcd_write_data(conf,0x11);
    // lcd_write_cmd(conf,0xB4);
    // lcd_write_data(conf,0x02);
    // lcd_write_cmd(conf,0xB6);
    // lcd_write_data(conf,0x02);
    // lcd_write_data(conf,0x02);

    // lcd_write_cmd(conf,0xB7);
    // lcd_write_data(conf,0xC6);
    // lcd_write_cmd(conf,0xE9);
    // lcd_write_data(conf,0x00);

    // lcd_write_cmd(conf,0XF7);
    // lcd_write_data(conf,0xA9);
    // lcd_write_data(conf,0x51);
    // lcd_write_data(conf,0x2C);
    // lcd_write_data(conf,0x82);



    // lcd_write_cmd(conf,0XF7);
    // lcd_write_data(conf,0x18);
    // lcd_write_data(conf,0xA3);
    // lcd_write_data(conf,0x12);
    // lcd_write_data(conf,0x02);
    // lcd_write_data(conf,0XB2);
    // lcd_write_data(conf,0x12);
    // lcd_write_data(conf,0xFF);
    // lcd_write_data(conf,0x10);
    // lcd_write_data(conf,0x00);
    // lcd_write_cmd(conf,0XF8);
    // lcd_write_data(conf,0x21);
    // lcd_write_data(conf,0x04);
    // lcd_write_cmd(conf,0X13);

    // lcd_write_cmd(conf,0x36);
    // if(conf->direction==0)lcd_write_data(conf,0x08);
    // else if(conf->direction==1)lcd_write_data(conf,0xC8);
    // else if(conf->direction==2)lcd_write_data(conf,0x78);
    // else lcd_write_data(conf,0xA8);

    // lcd_write_cmd(conf,0xB4);
    // lcd_write_data(conf,0x02);
    // lcd_write_cmd(conf,0xB6);
    // lcd_write_data(conf,0x02);
    // lcd_write_data(conf,0x22);
    // lcd_write_cmd(conf,0xC1);
    // lcd_write_data(conf,0x41);
    // lcd_write_cmd(conf,0xC5);
    // lcd_write_data(conf,0x00);
    // lcd_write_data(conf,0x18);

    // lcd_write_cmd(conf,0x3a);
    // lcd_write_data(conf,0x66);
    // luat_timer_mdelay(50);

    // lcd_write_cmd(conf,0xE0);
    // lcd_write_data(conf,0x0F);
    // lcd_write_data(conf,0x1F);
    // lcd_write_data(conf,0x1C);
    // lcd_write_data(conf,0x0C);
    // lcd_write_data(conf,0x0F);
    // lcd_write_data(conf,0x08);
    // lcd_write_data(conf,0x48);
    // lcd_write_data(conf,0x98);
    // lcd_write_data(conf,0x37);
    // lcd_write_data(conf,0x0A);
    // lcd_write_data(conf,0x13);
    // lcd_write_data(conf,0x04);
    // lcd_write_data(conf,0x11);
    // lcd_write_data(conf,0x0D);
    // lcd_write_data(conf,0x00);

    // lcd_write_cmd(conf,0xE1);
    // lcd_write_data(conf,0x0F);
    // lcd_write_data(conf,0x32);
    // lcd_write_data(conf,0x2E);
    // lcd_write_data(conf,0x0B);
    // lcd_write_data(conf,0x0D);
    // lcd_write_data(conf,0x05);
    // lcd_write_data(conf,0x47);
    // lcd_write_data(conf,0x75);
    // lcd_write_data(conf,0x37);
    // lcd_write_data(conf,0x06);
    // lcd_write_data(conf,0x10);
    // lcd_write_data(conf,0x03);
    // lcd_write_data(conf,0x24);
    // lcd_write_data(conf,0x20);
    // lcd_write_data(conf,0x00);

    /* Sleep Out */
    lcd_write_cmd(conf,0x11);
    /* wait for power stability */
    luat_timer_mdelay(100);
    luat_lcd_clear(conf,WHITE);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

const luat_lcd_opts_t lcd_opts_ili9488 = {
    .name = "ili9488",
    .init = ili9488_init,
    .close = ili9488_close,
    .sleep = ili9488_sleep,
    .wakeup = ili9488_wakeup,
};

