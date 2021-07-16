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

static int st7789_sleep(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x10);
    return 0;
}

static int st7789_wakeup(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x11);
    //luat_timer_mdelay(120); // 外部休眠就好了吧
    return 0;
}

static int st7789_close(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}


static int st7789_init(luat_lcd_conf_t* conf) {

    if (conf->w == 0)
        conf->w = LCD_W;
    if (conf->h == 0)
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

    /* Memory Data Access Control */
    lcd_write_cmd(conf,0x36);
    if(conf->direction==0)lcd_write_data(conf,0x00);
    else if(conf->direction==1)lcd_write_data(conf,0xC0);
    else if(conf->direction==2)lcd_write_data(conf,0x70);
    else lcd_write_data(conf,0xA0);
    /* RGB 5-6-5-bit  */
    lcd_write_cmd(conf,0x3A);
    lcd_write_data(conf,0x65);
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
    lcd_write_data(conf,0x19);
    /* LCM Control */
    lcd_write_cmd(conf,0xC0);
    lcd_write_data(conf,0x2C);
    /* VDV and VRH Command Enable */
    lcd_write_cmd(conf,0xC2);
    lcd_write_data(conf,0x01);
    /* VRH Set */
    lcd_write_cmd(conf,0xC3);
    lcd_write_data(conf,0x12);
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
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x0D);
    lcd_write_data(conf,0x11);
    lcd_write_data(conf,0x13);
    lcd_write_data(conf,0x2B);
    lcd_write_data(conf,0x3F);
    lcd_write_data(conf,0x54);
    lcd_write_data(conf,0x4C);
    lcd_write_data(conf,0x18);
    lcd_write_data(conf,0x0D);
    lcd_write_data(conf,0x0B);
    lcd_write_data(conf,0x1F);
    lcd_write_data(conf,0x23);
    /* Negative Voltage Gamma Control */
    lcd_write_cmd(conf,0xE1);
    lcd_write_data(conf,0xD0);
    lcd_write_data(conf,0x04);
    lcd_write_data(conf,0x0C);
    lcd_write_data(conf,0x11);
    lcd_write_data(conf,0x13);
    lcd_write_data(conf,0x2C);
    lcd_write_data(conf,0x3F);
    lcd_write_data(conf,0x44);
    lcd_write_data(conf,0x51);
    lcd_write_data(conf,0x2F);
    lcd_write_data(conf,0x1F);
    lcd_write_data(conf,0x1F);
    lcd_write_data(conf,0x20);
    lcd_write_data(conf,0x23);
    /* Display Inversion On */
    lcd_write_cmd(conf,0x21);
    /* Sleep Out */
    lcd_write_cmd(conf,0x11);
    /* wait for power stability */
    luat_timer_mdelay(100);
    luat_lcd_clear(conf,WHITE);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

// TODO 这里的color是ARGB, 需要转为lcd所需要的格式
static int st7789_draw(luat_lcd_conf_t* conf, uint16_t x_start, uint16_t y_start, uint16_t x_end, uint16_t y_end, luat_color_t* color) {
    uint16_t i = 0, j = 0;
    uint32_t size = 0, size_remain = 0;
    uint8_t *fill_buf = NULL;
    size = (x_end - x_start+1) * (y_end - y_start+1) * 2;
    if (size > conf->w*conf->h/10)
    {
        /* the number of remaining to be filled */
        size_remain = size - conf->w*conf->h/10;
        size = conf->w*conf->h/10;
    }
    luat_lcd_set_address(conf,x_start, y_start, x_end, y_end);
    fill_buf = (uint8_t *)luat_heap_malloc(size);
    if (fill_buf)
    {
        /* fast fill */
        while (1)
        {
            for (i = 0; i < size / 2; i++)
            {
                fill_buf[2 * i] = color[i]>>8;
                //color >> 8;
                fill_buf[2 * i + 1] = color[i];
            }
            luat_gpio_set(conf->pin_dc, Luat_GPIO_HIGH);
            luat_spi_send(conf->port, fill_buf, size);
            /* Fill completed */
            if (size_remain == 0)
                break;
            /* calculate the number of fill next time */
            if (size_remain > conf->w*conf->h/10)
            {
                size_remain = size_remain - conf->w*conf->h/10;
            }
            else
            {
                size = size_remain;
                size_remain = 0;
            }
        }
        luat_heap_free(fill_buf);
    }
    else
    {
        for (i = y_start; i <= y_end; i++)
        {
            for (j = x_start; j <= x_end; j++)lcd_write_half_word(conf,color[i]);
        }
    }
    return 0;
}

const luat_lcd_opts_t lcd_opts_st7789 = {
    .name = "st7789",
    .init = st7789_init,
    .close = st7789_close,
    .draw = st7789_draw,
    .sleep = st7789_sleep,
    .wakeup = st7789_wakeup,
};

