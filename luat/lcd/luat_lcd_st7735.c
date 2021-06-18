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
#define LCD_CLEAR_SEND_NUMBER LCD_W*LCD_H/10//5760


static int st7735_init(luat_lcd_conf_t* conf) {
    if (conf->w == 0)
        conf->w = LCD_W;
    if (conf->h == 0)
        conf->h = LCD_H;

    // 配置CS脚的GPIO
    luat_gpio_mode(conf->pin_cs, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0);
    luat_gpio_mode(conf->pin_dc, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0); // DC
    luat_gpio_mode(conf->pin_pwr, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0); // POWER
    luat_gpio_mode(conf->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0); // RST

    int pin_dc = conf->pin_dc;
    int pin_pwr = conf->pin_pwr;

    // 发送初始化命令
    //------------------------------------ST7735S Frame Rate-----------------------------------------//
    lcd_write_cmd(0xB1, conf);
    lcd_write_data(0x05, conf);
    lcd_write_data(0x3C, conf);
    lcd_write_data(0x3C, conf);
    lcd_write_cmd(0xB2, conf);
    lcd_write_data(0x05, conf);
    lcd_write_data(0x3C, conf);
    lcd_write_data(0x3C, conf);
    lcd_write_cmd(0xB3, conf);
    lcd_write_data(0x05, conf);
    lcd_write_data(0x3C, conf);
    lcd_write_data(0x3C, conf);
    lcd_write_data(0x05, conf);
    lcd_write_data(0x3C, conf);
    lcd_write_data(0x3C, conf);
    //------------------------------------End ST7735S Frame Rate---------------------------------//
    lcd_write_cmd(0xB4, conf);
    lcd_write_data(0x03, conf);
	//------------------------------------ST7735S Power Sequence---------------------------------//
    lcd_write_cmd(0xC0, conf);
    lcd_write_data(0x28, conf);
    lcd_write_data(0x08, conf);
    lcd_write_data(0x04, conf);
    lcd_write_cmd(0xC1, conf);
    lcd_write_data(0XC0, conf);
    lcd_write_cmd(0xC2, conf);
    lcd_write_data(0x0D, conf);
    lcd_write_data(0x00, conf);
    lcd_write_cmd(0xC3, conf);
    lcd_write_data(0x8D, conf);
    lcd_write_data(0x2A, conf);
    lcd_write_cmd(0xC4, conf);
    lcd_write_data(0x8D, conf);
    lcd_write_data(0xEE, conf);
	//---------------------------------End ST7735S Power Sequence-------------------------------------//
    lcd_write_cmd(0xC5, conf);
    lcd_write_data(0x1A, conf);
    lcd_write_cmd(0x36, conf);
    lcd_write_data(0x00, conf);
	//------------------------------------ST7735S Gamma Sequence---------------------------------//
	lcd_write_cmd(0xE0, conf);
    lcd_write_data(0x04, conf);
    lcd_write_data(0x22, conf);
    lcd_write_data(0x07, conf);
    lcd_write_data(0x0A, conf);
    lcd_write_data(0x2E, conf);
    lcd_write_data(0x30, conf);
    lcd_write_data(0x25, conf);
    lcd_write_data(0x2A, conf);
    lcd_write_data(0x28, conf);
    lcd_write_data(0x26, conf);
    lcd_write_data(0x2E, conf);
    lcd_write_data(0x3A, conf);
    lcd_write_data(0x00, conf);
    lcd_write_data(0x01, conf);
    lcd_write_data(0x03, conf);
    lcd_write_data(0x13, conf);
    lcd_write_cmd(0xE1, conf);
    lcd_write_data(0x04, conf);
    lcd_write_data(0x16, conf);
    lcd_write_data(0x06, conf);
    lcd_write_data(0x0D, conf);
    lcd_write_data(0x2D, conf);
    lcd_write_data(0x26, conf);
    lcd_write_data(0x23, conf);
    lcd_write_data(0x27, conf);
    lcd_write_data(0x27, conf);
    lcd_write_data(0x25, conf);
    lcd_write_data(0x2D, conf);
    lcd_write_data(0x3B, conf);
    lcd_write_data(0x00, conf);
    lcd_write_data(0x01, conf);
    lcd_write_data(0x04, conf);
    lcd_write_data(0x13, conf);

    lcd_write_cmd(0x3A, conf);
    lcd_write_data(0x05, conf);
    lcd_write_cmd(0x29, conf);
    return 0;
};

static int st7735_close(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}

// 暂时用不上
static int st7735_drawPoint(luat_lcd_conf_t* conf, uint16_t x, uint16_t y, uint32_t color) {
    return 0;
}

// 暂时用不上
static int st7735_fill(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color) {
    return 0;
}

// TODO 这里的color是ARGB, 需要转为lcd所需要的格式
static int st7735_draw(luat_lcd_conf_t* conf, uint16_t x_start, uint16_t y_start, uint16_t x_end, uint16_t y_end, uint32_t* color) {
    uint16_t i = 0, j = 0;
    uint32_t size = 0, size_remain = 0;
    uint8_t *fill_buf = NULL;
    size = (x_end - x_start+1) * (y_end - y_start+1) * 2;
    if (size > LCD_CLEAR_SEND_NUMBER)
    {
        /* the number of remaining to be filled */
        size_remain = size - LCD_CLEAR_SEND_NUMBER;
        size = LCD_CLEAR_SEND_NUMBER;
    }
    lcd_address_set(x_start, y_start, x_end, y_end, conf);
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
            if (size_remain > LCD_CLEAR_SEND_NUMBER)
            {
                size_remain = size_remain - LCD_CLEAR_SEND_NUMBER;
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
            for (j = x_start; j <= x_end; j++)lcd_write_half_word(color[i], conf);
        }
    }
    return 0;
}

static int st7735_sleep(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_timer_mdelay(5);
    lcd_write_cmd(0x10, conf);
    return 0;
}

static int st7735_wakeup(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_timer_mdelay(5);
    lcd_write_cmd(0x11, conf);
    //luat_timer_mdelay(120); // 外部休眠就好了吧
    return 0;
}

static int st7735_display_on(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    lcd_write_cmd(0x29, conf);
}

static int st7735_display_off(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
}

const luat_lcd_opts_t lcd_opts_st7735 = {
    .name = "st7735",
    .init = st7735_init,
    .close = st7735_close,
    .drawPoint = st7735_drawPoint,
    .fill = st7735_fill,
    .draw = st7735_draw,
    .sleep = st7735_sleep,
    .wakeup = st7735_wakeup,
    .display_on = st7735_display_on,
    .display_off = st7735_display_off,
};

