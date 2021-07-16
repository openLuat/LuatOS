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

static int st7735_sleep(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x10);
    return 0;
}

static int st7735_wakeup(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x11);
    //luat_timer_mdelay(120); // 外部休眠就好了吧
    return 0;
}

static int st7735_close(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}
static int st7735_init(luat_lcd_conf_t* conf) {
    if (conf->w == 0)
        conf->w = LCD_W;
    if (conf->h == 0)
        conf->h = LCD_H;
    if (conf->direction == 0)
        conf->direction = LCD_DIRECTION;

    // 配置CS脚的GPIO
    luat_gpio_mode(conf->pin_cs, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0);
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
    if(conf->direction==0)lcd_write_data(conf,0x00);
    else if(conf->direction==1)lcd_write_data(conf,0xC0);
    else if(conf->direction==2)lcd_write_data(conf,0x70);
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
    luat_lcd_clear(conf,WHITE);
    /* display on */
    luat_lcd_display_on(conf);
    return 0;
};

// TODO 这里的color是ARGB, 需要转为lcd所需要的格式
static int st7735_draw(luat_lcd_conf_t* conf, uint16_t x_start, uint16_t y_start, uint16_t x_end, uint16_t y_end, luat_color_t* color) {
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



const luat_lcd_opts_t lcd_opts_st7735 = {
    .name = "st7735",
    .init = st7735_init,
    .close = st7735_close,
    .draw = st7735_draw,
    .sleep = st7735_sleep,
    .wakeup = st7735_wakeup,
};

