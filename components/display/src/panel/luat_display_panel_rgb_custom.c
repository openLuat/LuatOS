#include "luat_base.h"
#include "luat_display_panel_comm.h"


#define LUAT_LOG_TAG "rgb_custom"
#include "luat_log.h"


#define panel_spi_send_seq(panel, ...) do {                         \
        static const unsigned char d[] = { __VA_ARGS__ };           \
        int ret;                                                    \
        ret = rgb_spi_panel_send_sequence(panel, d, ARRAY_SIZE(d)); \
        if (ret < 0)                                                \
            return ret;                                             \
    } while (0)

/*初始化面板*/
static int panel_init(struct luat_display_panel *panel) 
{
    /*使用默认的复位，如果复位时序不对，请使用自定义的*/
    luat_display_panel_reset(panel);

    /*发送 Lua 自定义初始化命令序列（custom_cmds，无则不发送）*/
    return luat_display_panel_send_custom_cmds(panel);
}

/*关闭面板*/
static int panel_deinit(struct luat_display_panel *panel) 
{
    return 0;
}

/*控制面板*/
static int panel_ctrl(struct luat_display_panel *panel, enum display_ctrl_cmd cmd, void *arg)
{
    return luat_display_panel_ctrl(panel, cmd, arg);
}

/*RGB面板操作接口*/
static struct luat_display_panel_funcs panel_funcs_rgb = {
    .panel_init     = panel_init,
    .panel_deinit   = panel_deinit,
    .panel_ctrl     = panel_ctrl,
};

/*RGB面板时序参数*/
static struct luat_display_timing custom_timing = {
    .pclk_hz = 9000000,

    .hactive = 480,
    .hfp = 30,
    .hbp = 30,
    .hspw = 10,

    .vactive = 272,
    .vfp = 8,
    .vbp = 16,
    .vspw = 2,
    
    .flags = DISPLAY_FLAGS_HSYNC_LOW | DISPLAY_FLAGS_VSYNC_LOW,
};

/*RGB接口参数*/
struct panel_rgb rgb_custom_rgb = 
{
    .mode = PRGB,
    .format = LUAT_DISPLAY_FORMAT_RGB565,
    .data_order = RGB_ORDER,
    .data_mirror = 0,
};

/*对RGB面板的描述*/
struct luat_display_panel rgb_panel_custom = {
    .name = "custom",
    .desc = "general",
    .connector_type = LUAT_DISPLAY_CONNECTOR_RGB,
    .rgb = &rgb_custom_rgb,
    .panel_funcs = &panel_funcs_rgb,
    .timing = &custom_timing,
    .screen_win = NULL,
};


