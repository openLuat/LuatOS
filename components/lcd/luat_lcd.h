
#ifndef LUAT_LCD
#define LUAT_LCD

#include "luat_base.h"
#include "u8g2.h"

#define WHITE            0xFFFF
#define BLACK            0x0000
#define BLUE             0x001F
#define BRED             0XF81F
#define GRED             0XFFE0
#define GBLUE            0X07FF
#define RED              0xF800
#define MAGENTA          0xF81F
#define GREEN            0x07E0
#define CYAN             0x7FFF
#define YELLOW           0xFFE0
#define BROWN            0XBC40
#define BRRED            0XFC07
#define GRAY             0X8430
#define GRAY175          0XAD75
#define GRAY151          0X94B2
#define GRAY187          0XBDD7
#define GRAY240          0XF79E

#define LUAT_LCD_COLOR_DEPTH 32

#if (LUAT_LCD_COLOR_DEPTH == 32)
#define luat_color_t uint32_t
#elif (LUAT_LCD_COLOR_DEPTH == 16)
#define luat_color_t uint16_t
#elif (LUAT_LCD_COLOR_DEPTH == 8)
#define luat_color_t uint8_t
#else
#error "no supprt color depth"
#endif

#define LUAT_LCD_SPI_DEVICE 255

struct luat_lcd_opts;

typedef struct luat_lcd_conf {
    uint8_t port;
    uint8_t pin_dc;
    uint8_t pin_pwr;
    uint8_t pin_rst;

    uint8_t direction;//方向
    uint32_t w;
    uint32_t h;
    uint32_t buffer_size;
    uint32_t dc_delay_us;
    uint8_t xoffset;//偏移
    uint8_t yoffset;//偏移

    u8g2_t luat_lcd_u8g2 ;
    void* userdata;
    struct luat_lcd_opts* opts;
} luat_lcd_conf_t;

typedef struct luat_lcd_opts {
    const char* name;
    int (*init)(luat_lcd_conf_t* conf);
    int (*close)(luat_lcd_conf_t* conf);
    int (*sleep)(luat_lcd_conf_t* conf);
    int (*wakeup)(luat_lcd_conf_t* conf);
} luat_lcd_opts_t;

int lcd_write_cmd(luat_lcd_conf_t* conf,const uint8_t cmd);
int lcd_write_data(luat_lcd_conf_t* conf,const uint8_t data);
int lcd_write_half_word(luat_lcd_conf_t* conf,const uint32_t da);

luat_lcd_conf_t* luat_lcd_get_default(void);
const char* luat_lcd_name(luat_lcd_conf_t* conf);
int luat_lcd_init(luat_lcd_conf_t* conf);
int luat_lcd_close(luat_lcd_conf_t* conf);
int luat_lcd_display_on(luat_lcd_conf_t* conf);
int luat_lcd_display_off(luat_lcd_conf_t* conf);
int luat_lcd_sleep(luat_lcd_conf_t* conf);
int luat_lcd_wakeup(luat_lcd_conf_t* conf);
int luat_lcd_set_address(luat_lcd_conf_t* conf,uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2);
int luat_lcd_set_color(uint32_t back, uint32_t fore);
int luat_lcd_draw(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, luat_color_t* color);
int luat_lcd_draw_no_block(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, luat_color_t* color, uint8_t last_flush);
int luat_lcd_clear(luat_lcd_conf_t* conf,uint32_t color);
int luat_lcd_draw_fill(luat_lcd_conf_t* conf,uint16_t x1,uint16_t y1,uint16_t x2,uint16_t y2,uint32_t color);
int luat_lcd_draw_point(luat_lcd_conf_t* conf, uint16_t x, uint16_t y, uint32_t color);
int luat_lcd_draw_line(luat_lcd_conf_t* conf,uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color);
int luat_lcd_draw_vline(luat_lcd_conf_t* conf, uint16_t x, uint16_t y,uint16_t h, uint32_t color);
int luat_lcd_draw_hline(luat_lcd_conf_t* conf, uint16_t x, uint16_t y,uint16_t h, uint32_t color);
int luat_lcd_draw_rectangle(luat_lcd_conf_t* conf,uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint32_t color);
int luat_lcd_draw_circle(luat_lcd_conf_t* conf,uint16_t x0, uint16_t y0, uint8_t r, uint32_t color);

void luat_lcd_execute_cmds(luat_lcd_conf_t* conf, uint32_t* cmds, uint32_t count);

typedef struct luat_lcd_custom {
    uint32_t init_cmd_count;
    uint32_t sleepcmd;
    uint32_t wakecmd;
    uint32_t initcmd[1]; // 实际命令长度与init_cmd_count相同
}luat_lcd_custom_t;

#endif

