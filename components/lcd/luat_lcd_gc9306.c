#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "gc9306"
#include "luat_log.h"

#define LCD_W 240
#define LCD_H 320
#define LCD_DIRECTION 0

static int gc9306_sleep(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x10);
    return 0;
}

static int gc9306_wakeup(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x11);
    //luat_timer_mdelay(120); // 外部休眠就好了吧
    return 0;
}

static int gc9306_close(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}
static int gc9306_init(luat_lcd_conf_t* conf) {
    if (conf->w == 0)
        conf->w = LCD_W;
    if (conf->h == 0)
        conf->h = LCD_H;
    if (conf->direction == 0)
        conf->direction = LCD_DIRECTION;

    luat_gpio_mode(conf->pin_dc, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0); // DC
    luat_gpio_mode(conf->pin_pwr, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0); // POWER
    luat_gpio_mode(conf->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0); // RST

    luat_gpio_mode(conf->pin_dc, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH); // DC
    luat_gpio_mode(conf->pin_pwr, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW); // POWER
    luat_gpio_mode(conf->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW); // RST

    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_LOW);
    luat_timer_mdelay(100);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_HIGH);

    // 发送初始化命令
    lcd_write_cmd(conf,0xfe);
    lcd_write_cmd(conf,0xef);

    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0x48);
    else if(conf->direction==1)lcd_write_data(conf,0xE8);
    else if(conf->direction==2)lcd_write_data(conf,0x28);
    else lcd_write_data(conf,0x38);

    lcd_write_cmd(conf,0x3a);
    lcd_write_data(conf,0x05);

    lcd_write_cmd(conf,0xa4);
    lcd_write_data(conf,0x44);
    lcd_write_data(conf,0x44);

    lcd_write_cmd(conf,0xa5);
    lcd_write_data(conf,0x42);
    lcd_write_data(conf,0x42);

    lcd_write_cmd(conf,0xaa);
    lcd_write_data(conf,0x88);
    lcd_write_data(conf,0x88);

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
    lcd_write_cmd(conf,0xad);
    lcd_write_data(conf,0x33);

    lcd_write_cmd(conf,0xae);
    lcd_write_data(conf,0x2b);

    lcd_write_cmd(conf,0xaf);
    lcd_write_data(conf,0x55);
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
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x06);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x0c);

    lcd_write_cmd(conf,0xF1);
    lcd_write_data(conf,0x01);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x00);
    lcd_write_data(conf,0x3a);
    lcd_write_data(conf,0x3e);
    lcd_write_data(conf,0x09);

    lcd_write_cmd(conf,0xF2);
    lcd_write_data(conf,0x0c);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x26);
    lcd_write_data(conf,0x07);
    lcd_write_data(conf,0x07);
    lcd_write_data(conf,0x30);

    lcd_write_cmd(conf,0xF3);
    lcd_write_data(conf,0x09);
    lcd_write_data(conf,0x06);
    lcd_write_data(conf,0x57);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x03);
    lcd_write_data(conf,0x6b);

    lcd_write_cmd(conf,0xF4);
    lcd_write_data(conf,0x0d);
    lcd_write_data(conf,0x1d);
    lcd_write_data(conf,0x1c);
    lcd_write_data(conf,0x06);
    lcd_write_data(conf,0x08);
    lcd_write_data(conf,0x0F);

    lcd_write_cmd(conf,0xF5);
    lcd_write_data(conf,0x0c);
    lcd_write_data(conf,0x05);
    lcd_write_data(conf,0x06);
    lcd_write_data(conf,0x33);
    lcd_write_data(conf,0x31);
    lcd_write_data(conf,0x0F);

    /* Sleep Out */
    lcd_write_cmd(conf,0x11);
    /* wait for power stability */
    luat_timer_mdelay(100);
    luat_lcd_clear(conf,WHITE);
    /* display on */
    luat_lcd_display_on(conf);
    lcd_write_cmd(conf,0x2c);
    return 0;
};

const luat_lcd_opts_t lcd_opts_gc9306 = {
    .name = "gc9306",
    .init = gc9306_init,
    .close = gc9306_close,
    .sleep = gc9306_sleep,
    .wakeup = gc9306_wakeup,
};

