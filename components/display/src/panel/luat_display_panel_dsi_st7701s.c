#include "luat_base.h"
#include "luat_display_panel_comm.h"


#define LUAT_LOG_TAG "st7701s"
#include "luat_log.h"


#define panel_dsi_send_seq(panel, ...) do {                         \
        static const unsigned char d[] = { __VA_ARGS__ };           \
        int ret;                                                    \
        ret = dsi_panel_send_sequence(panel, d, ARRAY_SIZE(d));     \
        if (ret < 0)                                                \
            return ret;                                             \
    } while (0)

/*初始化面板*/
static int panel_init(struct luat_display_panel *panel) 
{
    /*使用默认的复位，如果复位时序不对，请使用自定义的*/
    luat_display_panel_reset(panel);
    /*
    panel_dsi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x13);
    panel_dsi_send_seq(panel, 0xEF, 0x08);
    panel_dsi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x10);
    panel_dsi_send_seq(panel, 0xC0, 0x77, 0x00);
    panel_dsi_send_seq(panel, 0xC1, 0x09, 0x08);
    panel_dsi_send_seq(panel, 0xC2, 0x07, 0x02);
    panel_dsi_send_seq(panel, 0xCC, 0x10);
    panel_dsi_send_seq(panel, 0xB0, 0x40, 0x14, 0x59, 0x10, 0x12, 0x08, 0x03, 0x09, 0x05, 0x1E, 0x05, 0x14, 0x10, 0x68, 0x33, 0x15);
    panel_dsi_send_seq(panel, 0xB1, 0x40, 0x08, 0x53, 0x09, 0x11, 0x09, 0x02, 0x07, 0x09, 0x1A, 0x04, 0x12, 0x12, 0x64, 0x29, 0x2);
    */
   
    return 0;
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

/*DSI面板操作接口*/
static struct luat_display_panel_funcs panel_funcs_dsi = {
    .panel_init     = panel_init,
    .panel_deinit   = panel_deinit,
    .panel_ctrl     = panel_ctrl,
};

/*DSI面板时序参数*/
static struct luat_display_timing st7701s_timing = {
    .pclk_hz = 20000000,
    
    .hactive = 480,
    .hfp = 30,
    .hbp = 30,
    .hspw = 10,

    .vactive = 854,
    .vfp = 8,
    .vbp = 16,
    .vspw = 2,
};

/*DSI接口参数*/
struct panel_dsi st7701s_dsi = 
{
    .mode = DSI_MOD_VID_PULSE,
    .format = DSI_FMT_RGB565,
    .lane_num = 2,
};

/*对DSI面板的描述*/
struct luat_display_panel dsi_panel_st7701s = {
    .name = "BOE",
    .desc = "dsi",
    .connector_type = LUAT_DISPLAY_CONNECTOR_MIPI,
    .dsi = &st7701s_dsi,
    .panel_funcs = &panel_funcs_dsi,
    .timing = &st7701s_timing,
    .screen_win = NULL,
};


