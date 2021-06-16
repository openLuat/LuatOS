
#include "luat_base.h"
#include "luat_lcd.h"

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
