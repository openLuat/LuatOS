
#ifndef LUAT_LCD
#define LUAT_LCD

#include "luat_base.h"
#include "luat_spi.h"
#include "u8g2.h"

#define LUAT_LCD_CONF_COUNT (1)

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
#error "no support color depth"
#endif

enum{
    LUAT_LCD_ROTATE_0 = 0,
    LUAT_LCD_ROTATE_90,
    LUAT_LCD_ROTATE_180,
    LUAT_LCD_ROTATE_270,
};

enum{
	LUAT_LCD_HW_ID_0    = 0x20,	//专用LCD接口 ID

    LUAT_LCD_SPI_DEVICE,
    LUAT_LCD_PORT_RGB,
    LUAT_LCD_PORT_8080,
    LUAT_LCD_PORT_ARM2D,
    LUAT_LCD_PORT_DMA2D,
    LUAT_LCD_PORT_MAX,
};

struct luat_lcd_opts;

#define LUAT_LCD_DEFAULT_SLEEP  0X10
#define LUAT_LCD_DEFAULT_WAKEUP 0X11

enum{
	LUAT_LCD_IM_3_WIRE_9_BIT_INTERFACE_I = 5,
	LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_I = 6,
	LUAT_LCD_IM_3_WIRE_9_BIT_INTERFACE_II = 13,
	LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_II = 14,
	LUAT_LCD_IM_2_DATA_LANE = 16,
	LUAT_LCD_IM_QSPI_MODE = 0x20,
	LUAT_LCD_IM_8080_MODE = 0x30,
};

typedef struct
{
	uint8_t write_4line_cmd;
	uint8_t vsync_reg;
	uint8_t hsync_cmd;
	uint8_t hsync_reg;
	uint8_t write_1line_cmd;
}luat_lcd_qspi_conf_t;

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
    // buff 相关
    int buff_ref;
    int16_t flush_y_min;
    int16_t flush_y_max;
    uint8_t is_init_done;
    uint8_t interface_mode;	// LUAT_LCD_IM_XXX
    uint8_t lcd_cs_pin;		//注意不用的时候写0xff
    uint8_t bpp;			//颜色bit，默认是RGB565 16bit，预留兼容ARGB888 32bit
    uint32_t flush_rate;	//刷新率，针对no ram的屏幕起效
    uint32_t bus_speed;
    uint16_t hbp;
    uint16_t hspw;
    uint16_t hfp;
    uint16_t vbp;
    uint16_t vspw;
    uint16_t vfp;
    luat_color_t* buff;
    luat_color_t* buff_ex;
    luat_color_t* buff_draw;
    struct luat_lcd_opts* opts;
    luat_spi_device_t* lcd_spi_device;
    int lcd_spi_ref;
    int lcd_use_lvgl;
    void* userdata;
    u8g2_t luat_lcd_u8g2 ;
} luat_lcd_conf_t;

typedef struct luat_lcd_opts {
    const char* name;
    uint8_t sleep_cmd;
    uint8_t wakeup_cmd;
    uint8_t direction0;
    uint8_t direction90;
    uint8_t direction180;
    uint8_t direction270;
    uint8_t rb_swap;
    uint8_t no_ram_mode;
    uint16_t init_cmds_len;
    uint16_t* init_cmds;
    int (*user_ctrl_init)(luat_lcd_conf_t* conf);
    int (*init)(luat_lcd_conf_t* conf);
    int (*write_cmd_data)(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len);
    int (*read_cmd_data)(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len, uint8_t dummy_bit);
    int (*lcd_draw)(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color);
} luat_lcd_opts_t;

extern luat_lcd_opts_t lcd_opts_gc9106l;
extern luat_lcd_opts_t lcd_opts_gc9306x;
extern luat_lcd_opts_t lcd_opts_gc9a01;
extern luat_lcd_opts_t lcd_opts_ili9341;
extern luat_lcd_opts_t lcd_opts_ili9486;
extern luat_lcd_opts_t lcd_opts_st7735;
extern luat_lcd_opts_t lcd_opts_st7735s;
extern luat_lcd_opts_t lcd_opts_st7735v;
extern luat_lcd_opts_t lcd_opts_st7789;
extern luat_lcd_opts_t lcd_opts_st7796;
extern luat_lcd_opts_t lcd_opts_nv3037;
extern luat_lcd_opts_t lcd_opts_h050iwv;
extern luat_lcd_opts_t lcd_opts_jd9261t_inited;

static inline luat_color_t color_swap(luat_color_t color) {
    luat_color_t tmp = (color >> 8) + ((color & 0xFF) << 8);
    return tmp;
}

int lcd_write_cmd(luat_lcd_conf_t* conf,const uint8_t cmd);
int lcd_write_data(luat_lcd_conf_t* conf,const uint8_t data);

void luat_lcd_execute_cmds(luat_lcd_conf_t* conf);

int lcd_write_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len);
int lcd_read_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len, uint8_t dummy_bit);

// xxx_default 一般为通用spi设备使用
int luat_lcd_init_default(luat_lcd_conf_t* conf);
int luat_lcd_flush_default(luat_lcd_conf_t* conf);
int luat_lcd_draw_default(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color);

luat_lcd_conf_t* luat_lcd_get_default(void);
const char* luat_lcd_name(luat_lcd_conf_t* conf);
int luat_lcd_init(luat_lcd_conf_t* conf);
int luat_lcd_setup_buff(luat_lcd_conf_t* conf);
int luat_lcd_close(luat_lcd_conf_t* conf);
int luat_lcd_display_on(luat_lcd_conf_t* conf);
int luat_lcd_display_off(luat_lcd_conf_t* conf);
int luat_lcd_sleep(luat_lcd_conf_t* conf);
int luat_lcd_wakeup(luat_lcd_conf_t* conf);
int luat_lcd_inv_off(luat_lcd_conf_t* conf);
int luat_lcd_inv_on(luat_lcd_conf_t* conf);
int luat_lcd_set_address(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2);
int luat_lcd_set_color(luat_color_t back, luat_color_t fore);
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
int luat_lcd_set_direction(luat_lcd_conf_t* conf, uint8_t direction);
/*
 * csdk适配用
 */
void luat_lcd_service_init(uint32_t pro);
int luat_lcd_service_draw(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t *data, uint8_t is_static_buf);
int luat_lcd_service_set_mem_type(uint8_t type);
uint32_t luat_lcd_service_cache_len(void);
void luat_lcd_IF_init(luat_lcd_conf_t* conf);
int luat_lcd_IF_write_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len);
int luat_lcd_IF_read_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, uint8_t *data, uint8_t data_len, uint8_t dummy_bit);
int luat_lcd_IF_draw(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color);
/**
 * @brief luat_lcd_init放到service里跑，避免luat_lcd_init里漫长的delay带来的影响
 * @param conf lcd配置
 * @return 0无异常，其他失败
 */
int luat_lcd_init_in_service(luat_lcd_conf_t* conf);

typedef struct
{
	uint16_t top_cut_lines;
	uint16_t bottom_cut_lines;
	uint16_t left_cut_lines;
	uint16_t right_cut_lines;
	uint16_t w_scale;	//宽度比例缩小，0不缩
	uint16_t h_scale;	//高度度比例缩小，0不缩
}camera_cut_info_t;

/**
 * @brief 摄像头启动预览
 * @param camera_info camera配置，里面有lcd配置
 * @param cut_info 剪裁配置，可以留空
 * @param start_x 起始位置x
 * @param start_y 起始位置y
 * @return 0无异常，其他失败
 */
int luat_lcd_show_camera_in_service(void *camera_info, camera_cut_info_t *cut_info, uint16_t start_x, uint16_t start_y);

/**
 * @brief 停止摄像头预览
 * @return 0无异常，其他失败
 */
int luat_lcd_stop_show_camera(void);

int luat_lcd_qspi_config(luat_lcd_conf_t* conf, luat_lcd_qspi_conf_t *qspi_config);
int luat_lcd_qspi_auto_flush_on_off(luat_lcd_conf_t* conf, uint8_t on_off);
typedef void (*luat_lcd_api)(void *param, uint32_t param_len);
int luat_lcd_run_api_in_service(luat_lcd_api api, void *param, uint32_t param_len);
#endif

