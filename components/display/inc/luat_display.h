#ifndef LUAT_DISPLAY_H
#define LUAT_DISPLAY_H

#include "luat_base.h"
#include "luat_gpio.h"

#ifdef LUAT_USE_DISPLAY

#define LUAT_DISPLAY_COMPONENT_COUNT (5)    //最大支持5个显示组件

#define LUAT_DISPLAY_DEFAULT_SLEEP   0x10
#define LUAT_DISPLAY_DEFAULT_WAKEUP  0x11

enum disp_rotate {
    LUAT_DISPLAY_ROTATE_0   = 0,
    LUAT_DISPLAY_ROTATE_90  = 1,
    LUAT_DISPLAY_ROTATE_180 = 2,
    LUAT_DISPLAY_ROTATE_270 = 3,
};

enum disp_format {
  LUAT_DISPLAY_FORMAT_ARGB8888 = 0,
  LUAT_DISPLAY_FORMAT_ABGR8888 = 1,
  LUAT_DISPLAY_FORMAT_RGBA8888 = 2,
  LUAT_DISPLAY_FORMAT_BGRA8888 = 3,
  LUAT_DISPLAY_FORMAT_RGB565 = 4,
  LUAT_DISPLAY_FORMAT_BGR565 = 5,
  LUAT_DISPLAY_FORMAT_RGB888 = 6,
  LUAT_DISPLAY_FORMAT_CUSTOM = 7,
};

enum display_ctrl_cmd {
    LUAT_DISPLAY_POWER_OFF   = 0,
    LUAT_DISPLAY_POWER_SLEEP = 1,
    LUAT_DISPLAY_POWER_ON    = 2,
};

enum display_flags {
	DISPLAY_FLAGS_HSYNC_LOW		= (1 << 0),
	DISPLAY_FLAGS_HSYNC_HIGH	= (1 << 1),
	DISPLAY_FLAGS_VSYNC_LOW		= (1 << 2),
	DISPLAY_FLAGS_VSYNC_HIGH	= (1 << 3),
    DISPLAY_FLAGS_PCLK_LOW	    = (1 << 4),
    DISPLAY_FLAGS_PCLK_HIGH	    = (1 << 5),
    DISPLAY_FLAGS_DE_LOW		= (1 << 6),
    DISPLAY_FLAGS_DE_HIGH	    = (1 << 7),
};

/*连接器类型*/
enum LUAT_DISPLAY_CONNECTOR_TYPE {
    LUAT_DISPLAY_CONNECTOR_DE   = 0x00,  /* display engine component */
    LUAT_DISPLAY_CONNECTOR_RGB  = 0x01,  /* rgb component */
    LUAT_DISPLAY_CONNECTOR_LVDS = 0x02,  /* lvds component */
    LUAT_DISPLAY_CONNECTOR_MIPI = 0x03,  /* mipi dsi component */
    LUAT_DISPLAY_CONNECTOR_DBI  = 0x04,  /* mipi dbi component （spi/8080）*/
};

enum rgb_data_order {
    RGB_ORDER = 0x0,
    BGR_ORDER = 0x1,
    BRG_ORDER = 0x2,
    GBR_ORDER = 0x3,
};

enum rgb_mode {
    PRGB = 0x0,
    SRGB = 0x1,
};

/*RGB参数*/
struct panel_rgb {
    enum rgb_mode mode;                 // PRGB/SRGB模式
    enum disp_format format;            // 显示格式、颜色深度
    enum rgb_data_order data_order;     // 数据顺序，RGB/BGR/BRG
    unsigned int data_mirror;           // 每组数据线是否镜像 R0-7 - > R7-0 
};

enum lvds_mode {
    NS          = 0x0,
    JEIDA_24BIT = 0x1,
    JEIDA_18BIT = 0x2
};

enum lvds_link_mode {
    SINGLE_LINK0  = 0x0,
    SINGLE_LINK1  = 0x1,
    DOUBLE_SCREEN = 0x2,
    DUAL_LINK     = 0x3
};

/*LVDS参数*/
struct panel_lvds {
    enum lvds_mode mode;
    enum lvds_link_mode link_mode;
    unsigned int link_swap;
    unsigned int pols[2];
    unsigned int lanes[2];
};

/*DSI工作模式*/
enum dsi_mode {
    DSI_MOD_VID_PULSE        = (1 << 0),
    DSI_MOD_VID_EVENT        = (1 << 1),
    DSI_MOD_VID_BURST        = (1 << 2),
    DSI_MOD_CMD_MODE         = (1 << 3),
    DSI_CLOCK_NON_CONTINUOUS = (1 << 4),
};

/*DSI数据格式*/
enum dsi_format {
    DSI_FMT_RGB888 = 0,
    DSI_FMT_RGB666L = 1,
    DSI_FMT_RGB666 = 2,
    DSI_FMT_RGB565 = 3,
    DSI_FMT_MAX
};


struct luat_display;
struct luat_display_panel;

/*DSI参数*/
struct panel_dsi {
    enum dsi_mode mode;
    enum dsi_format format;
    unsigned int lane_num;  // 数据线数量

    unsigned int vc_num;
    unsigned int dc_inv;    //数据时钟是否反转
    unsigned int ln_polrs;  // 数据线极性
    unsigned int ln_assign; // 数据线分配
};

/*DBI参数*/
struct panel_dbi {

    //Type A Motorola 6800
    //Type B Intel 8080
    //Type C SPI
    unsigned int type;      // DBI类型 
    unsigned int format;    // 数据格式
};

/*引脚配置参数*/
struct panel_pin_device {
    
    /*配置参数用的SPI引脚*/
    uint8_t  cs;
    uint8_t  sdi;
    uint8_t  scl;

    /*控制引脚，用于复位、电源、背光*/
    uint8_t  rst;
    uint8_t  pwr;
    uint8_t  bl;
    uint8_t  dc;    //spi: data/command select

};

struct luat_display_area {
    int32_t x1;
    int32_t y1;
    int32_t x2;
    int32_t y2;
};

struct luat_display_rect {
    int32_t x;
    int32_t y;
    int32_t w;
    int32_t h;
};

struct luat_display_buf{

    void *buffer;       /*绘制缓冲区基地址*/
    uint32_t size;      /*显示缓冲区大小 (bytes)*/
    uint32_t stride;    /*绘制缓冲区行步长*/
    uint32_t count;     /*显示缓冲区数量*/
    enum disp_format format;    /*显示格式*/
    uint32_t width;          // 宽度
    uint32_t height;         // 高度
};

/*显示缓冲区信息*/
struct luat_display_fb_info {

    int inited;              // 是否初始化完成
    enum disp_format format; // 显示格式
    uint32_t bits_per_pixel; // 每像素位数(bpp值)
    uint32_t stride;         // 行步长
    void *fb_start;          // FB基地址，有多块FB 往后追加
    uint32_t fb_size;        // 单个 buf 大小 (bytes)
    uint32_t fb_count;       // FB数量
    uint32_t width;          // 宽度
    uint32_t height;         // 高度
    struct luat_display_buf draw_buf;   // 绘制缓冲区
};

/*显示层数据*/
struct luat_display_layer_data {

    uint32_t enable;    // 是否启用该层
    uint32_t layer_id;  // 层_id
    uint32_t area_id;   // 区域_id

    /*位置和尺寸*/
    struct luat_display_area area;

    /*显示缓冲区*/
    void *buffer;

    /*显示格式*/
    enum disp_format format;

};

/*显示时序参数*/
struct luat_display_timing {
    uint32_t pclk_hz;        // 像素时钟频率

    uint16_t hactive;        // 水平有效像素

    uint16_t hfp;            // 水平前廊
    uint16_t hbp;            // 水平后廊
    uint16_t hspw;           // 水平同步脉宽

    uint16_t vactive;        // 垂直有效像素

    uint16_t vfp;            // 垂直前廊
    uint16_t vbp;            // 垂直后廊
    uint16_t vspw;           // 垂直同步脉宽

    unsigned int flags;     // 显示标志位 enum display_flags
    
};

struct luat_display;

/*显示面板操作接口*/
struct luat_display_panel_funcs {

    /*初始化面板*/
    int (*panel_init)(struct luat_display_panel *panel);

    /*反初始化面板*/
    int (*panel_deinit)(struct luat_display_panel *panel);

    /*面板控制接口*/
    int (*panel_ctrl)(struct luat_display_panel *panel, enum display_ctrl_cmd cmd, void *arg);

};

/*显示面板*/
struct luat_display_panel
{
    const char *name;  //显示面板名称
    const char *desc;  //显示面板描述

    struct luat_display_panel_funcs *panel_funcs;
    struct luat_display_timing *timing;             // 显示时序参数
    struct luat_display_rect *screen_win;            // 屏幕窗口

    union {
        struct panel_rgb  *rgb;
        struct panel_lvds *lvds;
        struct panel_dsi  *dsi;
        struct panel_dbi  *dbi;
    };

    /*引脚配置参数*/
    struct panel_pin_device *pin;

    unsigned int connector_type; // 连接器类型 RGB/LVDS/DSI/DBI
};

/*显示操作接口*/
struct luat_display_funcs {

    const char *name;

    /*探测显示缓冲区,调用前先将 info 实例化，不能为 NULL，探测成功后，info 中会填充显示缓冲区信息*/
    int (*fb_probe)(struct luat_display_panel *panel, struct luat_display_fb_info *info);

    /*初始化接口，在这里设置接口参数、设置timing参数*/
    int (*inf_init)(struct luat_display *disp);

    /*刷新显示缓冲区*/
    int (*fb_flush)(struct luat_display *disp, struct luat_display_rect *rect, const void *data, enum disp_rotate rotation);

    /*设置显示层*/
    int (*set_layer)(struct luat_display_layer_data *layer_data);
    
    /*垂直同步*/
    int (*wait_vsync)(struct luat_display *disp);

    /*交换缓冲区*/
    int (*pan_display)(struct luat_display *disp, int index);

    /*反初始化接口，释放接口相关资源*/
    int (*deinit)(struct luat_display *disp);

};

/*显示图形操作接口*/
struct luat_display_graphics_funcs {
    void *reserved; /*TODO: 占位*/
};

struct luat_display {
    /*显示组件ID*/
    uint8_t  id;

    /*显示组件名称*/
    char name[16];

    /*显示面板*/
    struct luat_display_panel *panel;

    /*显示缓冲区信息*/
    struct luat_display_fb_info *fb_info;

    /*显示接口操作*/
    struct luat_display_funcs *display_funcs;

    /*显示图形操作接口*/
    struct luat_display_graphics_funcs *graphics_funcs;

    /*lua显示格式，没用，占位*/
    int bpp;

    /*显示旋转角度*/
    enum disp_rotate rotation;

    void    *userdata;

};

struct luat_display* luat_display_get_default(void);
struct luat_display* luat_display_get_by_id(uint8_t id);
int luat_display_register(struct luat_display *disp);
int luat_display_register_with_id(struct luat_display *disp, uint8_t id);
void luat_display_unregister(struct luat_display *disp);
int luat_display_init(struct luat_display *disp);
int luat_display_destroy(struct luat_display *disp);
int luat_display_on(struct luat_display *disp);
int luat_display_off(struct luat_display *disp);
int luat_display_close(struct luat_display_panel *panel);
int luat_display_layer_setup(struct luat_display *disp);
int luat_display_init_pin(struct panel_pin_device *pin);

int luat_display_power_on(struct luat_display *disp);
int luat_display_power_off(struct luat_display *disp);
int luat_display_panel_reset(struct luat_display_panel *panel);


#endif

#endif  /* __LUAT_DISPLAY_H__ */
