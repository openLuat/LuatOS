
#ifndef LUAT_LCD
#define LUAT_LCD

#include "luat_base.h"

struct luat_lcd_opts;

typedef struct luat_lcd_conf {
    uint8_t port;
    uint8_t pin_cs;
    uint8_t pin_dc;
    uint8_t pin_pwr;
    uint8_t pin_rst;

    uint32_t w;
    uint32_t h;

    void* userdata;
    const struct luat_lcd_opts* opts;
} luat_lcd_conf_t;

typedef struct luat_lcd_opts {
    const char* name;
    int (*init)(luat_lcd_conf_t* conf);
    int (*close)(luat_lcd_conf_t* conf);
    int (*drawPoint)(luat_lcd_conf_t* conf, uint16_t x, uint16_t y, uint32_t color);
    int (*fill)(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color);
    int (*draw)(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t* color);
    int (*sleep)(luat_lcd_conf_t* conf);
    int (*wakeup)(luat_lcd_conf_t* conf);
    int (*display_on)(luat_lcd_conf_t* conf);
    int (*display_off)(luat_lcd_conf_t* conf);
} luat_lcd_opts_t;

luat_lcd_conf_t* luat_lcd_get_default(void);
const char* luat_lcd_name(luat_lcd_conf_t* conf);
int luat_lcd_init(luat_lcd_conf_t* conf);
int luat_lcd_close(luat_lcd_conf_t* conf);
int luat_lcd_drawPoint(luat_lcd_conf_t* conf, uint16_t x, uint16_t y, uint32_t color);
int luat_lcd_fill(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color);
int luat_lcd_draw(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t* color);
int luat_lcd_sleep(luat_lcd_conf_t* conf);
int luat_lcd_wakeup(luat_lcd_conf_t* conf);
int luat_lcd_display_on(luat_lcd_conf_t* conf);
int luat_lcd_display_off(luat_lcd_conf_t* conf);


#endif

