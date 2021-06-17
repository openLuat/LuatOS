#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"

#define LUAT_LOG_TAG "lcd"
#include "luat_log.h"

#define LUAT_LCD_CONF_COUNT (2)
static luat_lcd_conf_t* confs[LUAT_LCD_CONF_COUNT] = {0};

luat_lcd_conf_t* luat_lcd_get_default(void) {
    for (size_t i = 0; i < LUAT_LCD_CONF_COUNT; i++)
    {
        if (confs[i] != NULL) {
            return confs[i];
        }
    }
    return NULL;
}

const char* luat_lcd_name(luat_lcd_conf_t* conf) {
    return conf->opts->name;
}

int luat_lcd_init(luat_lcd_conf_t* conf) {
    int ret = conf->opts->init(conf);
    if (ret == 0) {
        for (size_t i = 0; i < LUAT_LCD_CONF_COUNT; i++)
        {
            if (confs[i] == NULL) {
                confs[i] = conf;
                break;
            }
        }
    }
    return ret;
}

int luat_lcd_close(luat_lcd_conf_t* conf) {
    return conf->opts->close(conf);
}

int luat_lcd_drawPoint(luat_lcd_conf_t* conf, uint16_t x, uint16_t y, uint32_t color) {
    return conf->opts->drawPoint(conf, x, y, color);
}

int luat_lcd_fill(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color) {
    return conf->opts->fill(conf, x1, y1, x2, y2, color);
}

int luat_lcd_draw(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t* color) {
    return conf->opts->draw(conf, x1, y1, x2, y2, color);
}

int luat_lcd_sleep(luat_lcd_conf_t* conf) {
    return conf->opts->sleep(conf);
}

int luat_lcd_wakeup(luat_lcd_conf_t* conf) {
    return conf->opts->wakeup(conf);
}

int luat_lcd_display_on(luat_lcd_conf_t* conf) {
    return conf->opts->display_on(conf);
}

int luat_lcd_display_off(luat_lcd_conf_t* conf){
    return conf->opts->display_off(conf);
}


int lcd_write_cmd(const uint8_t cmd, luat_lcd_conf_t* conf)
{
    size_t len;
    luat_gpio_set(conf->pin_dc, Luat_GPIO_LOW);
    len = luat_spi_send(conf->port, &cmd, 1);
    if (len != 1)
    {
        LLOGI("lcd_write_cmd error. %d", len);
        return -1;
    }
    else
    {
        return 0;
    }
}

int lcd_write_data(const uint8_t data, luat_lcd_conf_t* conf)
{
    size_t len;
    luat_gpio_set(conf->pin_dc, Luat_GPIO_HIGH);
    len = luat_spi_send(conf->port, &data, 1);
    if (len != 1)
    {
        LLOGI("lcd_write_data error. %d", len);
        return -1;
    }
    else
    {
        return 0;
    }
}

int lcd_write_half_word(const uint16_t da, luat_lcd_conf_t* conf)
{
    size_t len = 0;
    char data[2] = {0};
    data[0] = da >> 8;
    data[1] = da;
    luat_gpio_set(conf->pin_dc, Luat_GPIO_HIGH);
    len = luat_spi_send(conf->port, data, 2);
    if (len != 2)
    {
        LLOGI("lcd_write_half_word error. %d", len);
        return -1;
    }
    else
    {
        return 0;
    }
}

void lcd_address_set(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, luat_lcd_conf_t* conf)
{
    lcd_write_cmd(0x2a, conf);
    lcd_write_data(x1 >> 8, conf);
    lcd_write_data(x1, conf);
    lcd_write_data(x2 >> 8, conf);
    lcd_write_data(x2, conf);
    lcd_write_cmd(0x2b, conf);
    lcd_write_data(y1 >> 8, conf);
    lcd_write_data(y1, conf);
    lcd_write_data(y2 >> 8, conf);
    lcd_write_data(y2, conf);
    lcd_write_cmd(0x2C, conf);
}
