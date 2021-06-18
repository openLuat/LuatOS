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
#define LCD_CLEAR_SEND_NUMBER LCD_W*LCD_H/10//5760


static int st7789_init(luat_lcd_conf_t* conf) {

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

    /* Memory Data Access Control */
    lcd_write_cmd(0x36, conf);
    lcd_write_data(0x00, conf);
    /* RGB 5-6-5-bit  */
    lcd_write_cmd(0x3A, conf);
    lcd_write_data(0x65, conf);
    /* Porch Setting */
    lcd_write_cmd(0xB2, conf);
    lcd_write_data(0x0C, conf);
    lcd_write_data(0x0C, conf);
    lcd_write_data(0x00, conf);
    lcd_write_data(0x33, conf);
    lcd_write_data(0x33, conf);
    /*  Gate Control */
    lcd_write_cmd(0xB7, conf);
    lcd_write_data(0x35, conf);
    /* VCOM Setting */
    lcd_write_cmd(0xBB, conf);
    lcd_write_data(0x19, conf);
    /* LCM Control */
    lcd_write_cmd(0xC0, conf);
    lcd_write_data(0x2C, conf);
    /* VDV and VRH Command Enable */
    lcd_write_cmd(0xC2, conf);
    lcd_write_data(0x01, conf);
    /* VRH Set */
    lcd_write_cmd(0xC3, conf);
    lcd_write_data(0x12, conf);
    /* VDV Set */
    lcd_write_cmd(0xC4, conf);
    lcd_write_data(0x20, conf);
    /* Frame Rate Control in Normal Mode */
    lcd_write_cmd(0xC6, conf);
    lcd_write_data(0x0F, conf);
    /* Power Control 1 */
    lcd_write_cmd(0xD0, conf);
    lcd_write_data(0xA4, conf);
    lcd_write_data(0xA1, conf);
    /* Positive Voltage Gamma Control */
    lcd_write_cmd(0xE0, conf);
    lcd_write_data(0xD0, conf);
    lcd_write_data(0x04, conf);
    lcd_write_data(0x0D, conf);
    lcd_write_data(0x11, conf);
    lcd_write_data(0x13, conf);
    lcd_write_data(0x2B, conf);
    lcd_write_data(0x3F, conf);
    lcd_write_data(0x54, conf);
    lcd_write_data(0x4C, conf);
    lcd_write_data(0x18, conf);
    lcd_write_data(0x0D, conf);
    lcd_write_data(0x0B, conf);
    lcd_write_data(0x1F, conf);
    lcd_write_data(0x23, conf);
    /* Negative Voltage Gamma Control */
    lcd_write_cmd(0xE1, conf);
    lcd_write_data(0xD0, conf);
    lcd_write_data(0x04, conf);
    lcd_write_data(0x0C, conf);
    lcd_write_data(0x11, conf);
    lcd_write_data(0x13, conf);
    lcd_write_data(0x2C, conf);
    lcd_write_data(0x3F, conf);
    lcd_write_data(0x44, conf);
    lcd_write_data(0x51, conf);
    lcd_write_data(0x2F, conf);
    lcd_write_data(0x1F, conf);
    lcd_write_data(0x1F, conf);
    lcd_write_data(0x20, conf);
    lcd_write_data(0x23, conf);
    /* Display Inversion On */
    lcd_write_cmd(0x21, conf);
    /* Sleep Out */
    lcd_write_cmd(0x11, conf);
    /* wait for power stability */
    //luat_timer_mdelay(100);
    //lcd_clear(WHITE);
    /* display on */
    //lcd_display_on();
    return 0;
};

static int st7789_close(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}

// 暂时用不上
static int st7789_drawPoint(luat_lcd_conf_t* conf, uint16_t x, uint16_t y, uint32_t color) {
    return 0;
}

// 暂时用不上
static int st7789_fill(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color) {
    return 0;
}

// TODO 这里的color是ARGB, 需要转为lcd所需要的格式
static int st7789_draw(luat_lcd_conf_t* conf, uint16_t x_start, uint16_t y_start, uint16_t x_end, uint16_t y_end, uint32_t* color) {
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

static int st7789_sleep(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_timer_mdelay(5);
    lcd_write_cmd(0x10, conf);
    return 0;
}

static int st7789_wakeup(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_timer_mdelay(5);
    lcd_write_cmd(0x11, conf);
    //luat_timer_mdelay(120); // 外部休眠就好了吧
    return 0;
}

static int st7789_display_on(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    lcd_write_cmd(0x29, conf);
}

static int st7789_display_off(luat_lcd_conf_t* conf) {
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
}

const luat_lcd_opts_t lcd_opts_st7789 = {
    .name = "st7789",
    .init = st7789_init,
    .close = st7789_close,
    .drawPoint = st7789_drawPoint,
    .fill = st7789_fill,
    .draw = st7789_draw,
    .sleep = st7789_sleep,
    .wakeup = st7789_wakeup,
    .display_on = st7789_display_on,
    .display_off = st7789_display_off,
};

