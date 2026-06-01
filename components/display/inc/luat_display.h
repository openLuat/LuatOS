#ifndef LUAT_DISPLAY_H
#define LUAT_DISPLAY_H

#include "luat_base.h"
#include "luat_gpio.h"

#ifdef LUAT_USE_DISPLAY

#define LUAT_DISPLAY_CONF_COUNT (1)

#define LUAT_DISPLAY_DEFAULT_SLEEP   0x10
#define LUAT_DISPLAY_DEFAULT_WAKEUP  0x11

enum {
    LUAT_DISPLAY_ROTATE_0   = 0,
    LUAT_DISPLAY_ROTATE_90  = 1,
    LUAT_DISPLAY_ROTATE_180 = 2,
    LUAT_DISPLAY_ROTATE_270 = 3,
};

enum {
    LUAT_DISPLAY_FORMAT_RGB565   = 0,
    LUAT_DISPLAY_FORMAT_RGB888   = 1,
    LUAT_DISPLAY_FORMAT_ARGB8888 = 2,
};

enum {
    LUAT_DISPLAY_POWER_OFF   = 0,
    LUAT_DISPLAY_POWER_SLEEP = 1,
    LUAT_DISPLAY_POWER_ON    = 2,
};

typedef struct luat_display luat_display_t;
typedef struct luat_display_panel_ops luat_display_panel_ops_t;
typedef struct luat_display_if_ops luat_display_if_ops_t;

typedef struct luat_display_fb_info {
    void     *addr;          // FB 基地址
    void     *addr_ex;       // 第二缓冲地址
    uint32_t  size;          // 单个 buf 大小 (bytes)
    uint32_t  count;         // 缓冲区数量 (1/2)
    uint32_t  active_idx;    // 当前活跃缓冲区
    uint16_t  stride;        // 行步长
    uint8_t   format;        // luat_display_format_t
} luat_display_fb_info_t;

typedef struct luat_display_rgb_timing {
    uint16_t h_res;          // 水平有效像素
    uint16_t v_res;          // 垂直有效像素
    uint16_t hbp;            // 水平后廊
    uint16_t hfp;            // 水平前廊
    uint16_t hspw;           // 水平同步脉宽
    uint16_t vbp;            // 垂直后廊
    uint16_t vfp;            // 垂直前廊
    uint16_t vspw;           // 垂直同步脉宽
    uint8_t  hs_polarity;    // HSYNC 极性 (0=低有效, 1=高有效)
    uint8_t  vs_polarity;    // VSYNC 极性
    uint8_t  de_polarity;    // DE 极性
    uint8_t  pclk_polarity;  // PCLK 极性 (0=下降沿, 1=上升沿)
    uint32_t pclk_hz;        // 像素时钟频率
} luat_display_rgb_timing_t;

struct luat_display {
    uint8_t  id;
    char     name[16];

    const luat_display_panel_ops_t *panel_ops;
    const luat_display_if_ops_t    *if_ops;
    void                           *if_userdata;

    luat_display_fb_info_t  fb_info;
    luat_display_rgb_timing_t rgb_timing;

    uint8_t  rotation;
    uint8_t  power_state;
    uint8_t  is_initialized;
    uint8_t  auto_flush;

    uint16_t width;
    uint16_t height;

    uint8_t  pin_bl;
    uint8_t  pin_rst;
    uint8_t  pin_pwr;

    uint8_t  bpp;
    uint8_t  interface_mode;

    void    *userdata;
};

struct luat_display_panel_ops {
    const char *name;

    uint16_t        init_cmds_len;
    const uint16_t *init_cmds;

    uint8_t  sleep_cmd;
    uint8_t  wakeup_cmd;

    uint8_t  madctl_0;
    uint8_t  madctl_90;
    uint8_t  madctl_180;
    uint8_t  madctl_270;

    uint8_t  rb_swap;
    uint8_t  bpp;

    int (*user_ctrl_init)(luat_display_t *disp);
    int (*init)(luat_display_t *disp);
    int (*set_rotation)(luat_display_t *disp, uint8_t rotation);
};

struct luat_display_if_ops {
    const char *name;

    int (*write_cmd)(luat_display_t *disp, uint8_t cmd);
    int (*write_data)(luat_display_t *disp, const uint8_t *data, uint32_t len);
    int (*write_cmd_data)(luat_display_t *disp, uint8_t cmd,
                          const uint8_t *data, uint32_t len);

    int (*fb_flush)(luat_display_t *disp,
                    int16_t x1, int16_t y1, int16_t x2, int16_t y2,
                    const void *data);

    int (*pan_display)(luat_display_t *disp);

    int (*init)(luat_display_t *disp);
    int (*deinit)(luat_display_t *disp);
};

void luat_display_execute_cmds(luat_display_t *disp);

int luat_display_write_cmd(luat_display_t *disp, uint8_t cmd);
int luat_display_write_data(luat_display_t *disp, const uint8_t *data, uint32_t len);
int luat_display_write_cmd_data(luat_display_t *disp, uint8_t cmd,
                                const uint8_t *data, uint32_t len);

luat_display_t* luat_display_get_default(void);
int luat_display_register(luat_display_t *disp);
const char* luat_display_name(luat_display_t *disp);

int luat_display_init_default(luat_display_t *disp);
int luat_display_fb_probe_default(luat_display_t *disp, luat_display_fb_info_t *info);
int luat_display_fb_allocate_default(luat_display_t *disp, uint32_t num_buffers);
int luat_display_flush_default(luat_display_t *disp);

LUAT_WEAK int luat_display_init(luat_display_t *disp);

extern const luat_display_if_ops_t if_ops_rgb;
extern const luat_display_if_ops_t if_ops_sdl;
LUAT_WEAK int luat_display_fb_probe(luat_display_t *disp, luat_display_fb_info_t *info);
LUAT_WEAK int luat_display_fb_allocate(luat_display_t *disp, uint32_t num_buffers);
LUAT_WEAK int luat_display_flush(luat_display_t *disp);

int luat_display_close(luat_display_t *disp);
int luat_display_on(luat_display_t *disp);
int luat_display_off(luat_display_t *disp);
int luat_display_sleep(luat_display_t *disp);
int luat_display_wakeup(luat_display_t *disp);

int luat_display_set_rotation(luat_display_t *disp, uint8_t rotation);

#endif

#endif
