
#ifndef LUAT_LCD
#define LUAT_LCD

#include "luat_base.h"
#include "luat_spi.h"
#include "u8g2.h"

#define LCD_W 240
#define LCD_H 320
#define LCD_DIRECTION 0

#define LCD_WHITE            0xFFFF
#define LCD_BLACK            0x0000

#ifndef LUAT_LCD_COLOR_DEPTH
#define LUAT_LCD_COLOR_DEPTH 16
#endif

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
#define LUAT_LCD_HW_INFERFACE_ID 0x20	//专用LCD接口的SPI ID

struct luat_lcd_opts;

enum{

	LUAT_LCD_IM_3_WIRE_9_BIT_INTERFACE_I = 5,
	LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_I = 6,
	LUAT_LCD_IM_3_WIRE_9_BIT_INTERFACE_II = 13,
	LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_II = 14,
	LUAT_LCD_IM_2_DATA_LANE = 16,
};

typedef struct luat_lcd_conf {
    uint8_t port;
    uint8_t pin_dc;
    uint8_t pin_pwr;
    uint8_t pin_rst;

    int16_t w;
    int16_t h;
    uint32_t buffer_size;
    uint32_t dc_delay_us;
    uint8_t xoffset;//偏移
    uint8_t yoffset;//偏移
    uint8_t auto_flush;
    uint8_t direction;//方向
    u8g2_t luat_lcd_u8g2 ;
    struct luat_lcd_opts* opts;
    luat_spi_device_t* lcd_spi_device;
    int lcd_spi_ref;
    void* userdata;

    // buff 相关
    luat_color_t* buff;
    int buff_ref;
    int16_t flush_y_min;
    int16_t flush_y_max;
    uint8_t is_init_done;

    uint8_t interface_mode;	// LUAT_LCD_IM_XXX
    uint8_t lcd_cs_pin;		//注意不用的时候写0xff
} luat_lcd_conf_t;

typedef struct luat_lcd_opts {
    const char* name;
    uint8_t direction0;
    uint8_t direction90;
    uint8_t direction180;
    uint8_t direction270;
    uint16_t init_cmds_len;
    uint16_t* init_cmds;
    int (*init)(luat_lcd_conf_t* conf);
    int (*write_cmd_data)(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len);
    int (*read_cmd_data)(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len, uint8_t dummy_bit);
    int (*lcd_draw)(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color);
} luat_lcd_opts_t;

int lcd_write_cmd(luat_lcd_conf_t* conf,const uint8_t cmd);
int lcd_write_data(luat_lcd_conf_t* conf,const uint8_t data);

void luat_lcd_execute_cmds(luat_lcd_conf_t* conf);

int lcd_write_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len);
int lcd_read_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len, uint8_t dummy_bit);

luat_lcd_conf_t* luat_lcd_get_default(void);
const char* luat_lcd_name(luat_lcd_conf_t* conf);
int luat_lcd_init(luat_lcd_conf_t* conf);
int luat_lcd_close(luat_lcd_conf_t* conf);
int luat_lcd_display_on(luat_lcd_conf_t* conf);
int luat_lcd_display_off(luat_lcd_conf_t* conf);
int luat_lcd_sleep(luat_lcd_conf_t* conf);
int luat_lcd_wakeup(luat_lcd_conf_t* conf);
int luat_lcd_inv_off(luat_lcd_conf_t* conf);
int luat_lcd_inv_on(luat_lcd_conf_t* conf);
int luat_lcd_set_address(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2);
int luat_lcd_set_color(luat_color_t back, luat_color_t fore);
luat_color_t color_swap(luat_color_t color);
int luat_lcd_draw(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color);
int luat_lcd_flush(luat_lcd_conf_t* conf);
int luat_lcd_draw_no_block(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color, uint8_t last_flush);
int luat_lcd_clear(luat_lcd_conf_t* conf, luat_color_t color);
int luat_lcd_draw_fill(luat_lcd_conf_t* conf, int16_t x1,int16_t y1,int16_t x2,int16_t y2,luat_color_t color);
int luat_lcd_draw_point(luat_lcd_conf_t* conf, int16_t x, int16_t y, luat_color_t color);
int luat_lcd_draw_line(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t color);
int luat_lcd_draw_vline(luat_lcd_conf_t* conf, int16_t x, int16_t y,int16_t h, luat_color_t color);
int luat_lcd_draw_hline(luat_lcd_conf_t* conf, int16_t x, int16_t y,int16_t h, luat_color_t color);
int luat_lcd_draw_rectangle(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t color);
int luat_lcd_draw_circle(luat_lcd_conf_t* conf, int16_t x0, int16_t y0, uint8_t r, luat_color_t color);

/*
 * csdk适配用
 */
void luat_lcd_service_init(uint32_t pro);
void luat_lcd_service_run(void *api, void *data, uint32_t param, uint32_t timeout);
int luat_lcd_service_draw(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t *data, uint8_t is_static_buf);
uint32_t luat_lcd_service_cache_len(void);
void luat_lcd_IF_init(luat_lcd_conf_t* conf);
int luat_lcd_IF_write_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len);
int luat_lcd_IF_read_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, uint8_t *data, uint8_t data_len, uint8_t dummy_bit);
int luat_lcd_IF_draw(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color);

#endif

