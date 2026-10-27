#include "luat_base.h"
#include "luat_display_panel_comm.h"

#ifdef LUAT_USE_MIPI_INF
#include "luat_rtos.h"


#define LUAT_LOG_TAG "ili9881c"
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

    panel_dsi_send_seq(panel, 0xFF, 0x98, 0x81, 0x03);
    panel_dsi_send_seq(panel, 0x01, 0x00);
    panel_dsi_send_seq(panel, 0x02, 0x00);
    panel_dsi_send_seq(panel, 0x03, 0x73);
    panel_dsi_send_seq(panel, 0x04, 0x00);
    panel_dsi_send_seq(panel, 0x05, 0x00);
    panel_dsi_send_seq(panel, 0x06, 0x0C);
    panel_dsi_send_seq(panel, 0x07, 0x00);
    panel_dsi_send_seq(panel, 0x08, 0x00);
    panel_dsi_send_seq(panel, 0x09, 0x01);
    panel_dsi_send_seq(panel, 0x0A, 0x01);
    panel_dsi_send_seq(panel, 0x0B, 0x01);
    panel_dsi_send_seq(panel, 0x0C, 0x01);
    panel_dsi_send_seq(panel, 0x0D, 0x01);
    panel_dsi_send_seq(panel, 0x0E, 0x01);
    panel_dsi_send_seq(panel, 0x0F, 0x00);
    panel_dsi_send_seq(panel, 0x10, 0x00);
    panel_dsi_send_seq(panel, 0x11, 0x00);
    panel_dsi_send_seq(panel, 0x12, 0x00);
    panel_dsi_send_seq(panel, 0x13, 0x00);
    panel_dsi_send_seq(panel, 0x14, 0x00);
    panel_dsi_send_seq(panel, 0x15, 0x00);
    panel_dsi_send_seq(panel, 0x16, 0x00);
    panel_dsi_send_seq(panel, 0x17, 0x00);
    panel_dsi_send_seq(panel, 0x18, 0x00);
    panel_dsi_send_seq(panel, 0x19, 0x00);
    panel_dsi_send_seq(panel, 0x1A, 0x00);
    panel_dsi_send_seq(panel, 0x1B, 0x00);
    panel_dsi_send_seq(panel, 0x1C, 0x00);
    panel_dsi_send_seq(panel, 0x1D, 0x00);
    panel_dsi_send_seq(panel, 0x1E, 0x44);
    panel_dsi_send_seq(panel, 0x1F, 0xC0);
    panel_dsi_send_seq(panel, 0x20, 0x0A);
    panel_dsi_send_seq(panel, 0x21, 0x03);
    panel_dsi_send_seq(panel, 0x22, 0x0A);
    panel_dsi_send_seq(panel, 0x23, 0x00);
    panel_dsi_send_seq(panel, 0x24, 0x8C);
    panel_dsi_send_seq(panel, 0x25, 0x8C);
    panel_dsi_send_seq(panel, 0x26, 0x00);
    panel_dsi_send_seq(panel, 0x27, 0x00);
    panel_dsi_send_seq(panel, 0x28, 0x3B);
    panel_dsi_send_seq(panel, 0x29, 0x03);
    panel_dsi_send_seq(panel, 0x2A, 0x00);
    panel_dsi_send_seq(panel, 0x2B, 0x00);
    panel_dsi_send_seq(panel, 0x2C, 0x00);
    panel_dsi_send_seq(panel, 0x2D, 0x00);
    panel_dsi_send_seq(panel, 0x2E, 0x00);
    panel_dsi_send_seq(panel, 0x2F, 0x00);
    panel_dsi_send_seq(panel, 0x30, 0x00);
    panel_dsi_send_seq(panel, 0x31, 0x00);
    panel_dsi_send_seq(panel, 0x32, 0x00);
    panel_dsi_send_seq(panel, 0x33, 0x00);
    panel_dsi_send_seq(panel, 0x34, 0x00);
    panel_dsi_send_seq(panel, 0x35, 0x00);
    panel_dsi_send_seq(panel, 0x36, 0x00);
    panel_dsi_send_seq(panel, 0x37, 0x00);
    panel_dsi_send_seq(panel, 0x38, 0x00);
    panel_dsi_send_seq(panel, 0x39, 0x00);
    panel_dsi_send_seq(panel, 0x3A, 0x00);
    panel_dsi_send_seq(panel, 0x3B, 0x00);
    panel_dsi_send_seq(panel, 0x3C, 0x00);
    panel_dsi_send_seq(panel, 0x3D, 0x00);
    panel_dsi_send_seq(panel, 0x3E, 0x00);
    panel_dsi_send_seq(panel, 0x3F, 0x00);
    panel_dsi_send_seq(panel, 0x40, 0x00);
    panel_dsi_send_seq(panel, 0x41, 0x00);
    panel_dsi_send_seq(panel, 0x42, 0x00);
    panel_dsi_send_seq(panel, 0x43, 0x00);
    panel_dsi_send_seq(panel, 0x44, 0x00);
    panel_dsi_send_seq(panel, 0x50, 0x01);
    panel_dsi_send_seq(panel, 0x51, 0x23);
    panel_dsi_send_seq(panel, 0x52, 0x45);
    panel_dsi_send_seq(panel, 0x53, 0x67);
    panel_dsi_send_seq(panel, 0x54, 0x89);
    panel_dsi_send_seq(panel, 0x55, 0xAB);
    panel_dsi_send_seq(panel, 0x56, 0x01);
    panel_dsi_send_seq(panel, 0x57, 0x23);
    panel_dsi_send_seq(panel, 0x58, 0x45);
    panel_dsi_send_seq(panel, 0x59, 0x67);
    panel_dsi_send_seq(panel, 0x5A, 0x89);
    panel_dsi_send_seq(panel, 0x5B, 0xAB);
    panel_dsi_send_seq(panel, 0x5C, 0xCD);
    panel_dsi_send_seq(panel, 0x5D, 0xEF);
    panel_dsi_send_seq(panel, 0x5E, 0x11);
    panel_dsi_send_seq(panel, 0x5F, 0x0C);
    panel_dsi_send_seq(panel, 0x60, 0x0D);
    panel_dsi_send_seq(panel, 0x61, 0x0E);
    panel_dsi_send_seq(panel, 0x62, 0x0F);
    panel_dsi_send_seq(panel, 0x63, 0x06);
    panel_dsi_send_seq(panel, 0x64, 0x07);
    panel_dsi_send_seq(panel, 0x65, 0x02);
    panel_dsi_send_seq(panel, 0x66, 0x02);
    panel_dsi_send_seq(panel, 0x67, 0x02);
    panel_dsi_send_seq(panel, 0x68, 0x02);
    panel_dsi_send_seq(panel, 0x69, 0x02);
    panel_dsi_send_seq(panel, 0x6A, 0x02);
    panel_dsi_send_seq(panel, 0x6B, 0x02);
    panel_dsi_send_seq(panel, 0x6C, 0x02);
    panel_dsi_send_seq(panel, 0x6D, 0x02);
    panel_dsi_send_seq(panel, 0x6E, 0x02);
    panel_dsi_send_seq(panel, 0x6F, 0x02);
    panel_dsi_send_seq(panel, 0x70, 0x02);
    panel_dsi_send_seq(panel, 0x71, 0x02);
    panel_dsi_send_seq(panel, 0x72, 0x02);
    panel_dsi_send_seq(panel, 0x73, 0x01);
    panel_dsi_send_seq(panel, 0x74, 0x00);
    panel_dsi_send_seq(panel, 0x75, 0x0C);
    panel_dsi_send_seq(panel, 0x76, 0x0D);
    panel_dsi_send_seq(panel, 0x77, 0x0E);
    panel_dsi_send_seq(panel, 0x78, 0x0F);
    panel_dsi_send_seq(panel, 0x79, 0x06);
    panel_dsi_send_seq(panel, 0x7A, 0x07);
    panel_dsi_send_seq(panel, 0x7B, 0x02);
    panel_dsi_send_seq(panel, 0x7C, 0x02);
    panel_dsi_send_seq(panel, 0x7D, 0x02);
    panel_dsi_send_seq(panel, 0x7E, 0x02);
    panel_dsi_send_seq(panel, 0x7F, 0x02);
    panel_dsi_send_seq(panel, 0x80, 0x02);
    panel_dsi_send_seq(panel, 0x81, 0x02);
    panel_dsi_send_seq(panel, 0x82, 0x02);
    panel_dsi_send_seq(panel, 0x83, 0x02);
    panel_dsi_send_seq(panel, 0x84, 0x02);
    panel_dsi_send_seq(panel, 0x85, 0x02);
    panel_dsi_send_seq(panel, 0x86, 0x02);
    panel_dsi_send_seq(panel, 0x87, 0x02);
    panel_dsi_send_seq(panel, 0x88, 0x02);
    panel_dsi_send_seq(panel, 0x89, 0x01);
    panel_dsi_send_seq(panel, 0x8A, 0x00);

    /* Page 4: GAMMA */
    panel_dsi_send_seq(panel, 0xFF, 0x98, 0x81, 0x04);
    panel_dsi_send_seq(panel, 0x38, 0x01);
    panel_dsi_send_seq(panel, 0x39, 0x00);
    panel_dsi_send_seq(panel, 0x00, 0x80);
    panel_dsi_send_seq(panel, 0x6C, 0x15);
    panel_dsi_send_seq(panel, 0x6E, 0x1A);
    panel_dsi_send_seq(panel, 0x6F, 0xA5);
    panel_dsi_send_seq(panel, 0x3A, 0x24);
    panel_dsi_send_seq(panel, 0x8D, 0x1F);
    panel_dsi_send_seq(panel, 0x87, 0xBA);
    panel_dsi_send_seq(panel, 0x26, 0x76);
    panel_dsi_send_seq(panel, 0xB2, 0xD1);
    panel_dsi_send_seq(panel, 0xB5, 0x06);
    panel_dsi_send_seq(panel, 0x3A, 0x24);
    panel_dsi_send_seq(panel, 0x3B, 0x98);
    panel_dsi_send_seq(panel, 0x35, 0x1F);
    panel_dsi_send_seq(panel, 0x32, 0x05);
    panel_dsi_send_seq(panel, 0x33, 0x00);
    panel_dsi_send_seq(panel, 0x7A, 0x0F);

    /* Page 1: power / GIP */
    panel_dsi_send_seq(panel, 0xFF, 0x98, 0x81, 0x01);
    panel_dsi_send_seq(panel, 0x22, 0x0A);
    panel_dsi_send_seq(panel, 0x31, 0x00);
    panel_dsi_send_seq(panel, 0x40, 0x33);
    panel_dsi_send_seq(panel, 0x42, 0x33);
    panel_dsi_send_seq(panel, 0x53, 0x55);
    panel_dsi_send_seq(panel, 0x55, 0x55);
    panel_dsi_send_seq(panel, 0xB7, 0x03);
    panel_dsi_send_seq(panel, 0x50, 0xA6);
    panel_dsi_send_seq(panel, 0x51, 0xA6);
    panel_dsi_send_seq(panel, 0x60, 0x06);
    panel_dsi_send_seq(panel, 0x61, 0x01);
    panel_dsi_send_seq(panel, 0x62, 0x19);
    panel_dsi_send_seq(panel, 0x63, 0x10);
    panel_dsi_send_seq(panel, 0xA0, 0x08);
    panel_dsi_send_seq(panel, 0xA1, 0x16);
    panel_dsi_send_seq(panel, 0xA2, 0x20);
    panel_dsi_send_seq(panel, 0xA3, 0x13);
    panel_dsi_send_seq(panel, 0xA4, 0x14);
    panel_dsi_send_seq(panel, 0xA5, 0x26);
    panel_dsi_send_seq(panel, 0xA6, 0x18);
    panel_dsi_send_seq(panel, 0xA7, 0x1C);
    panel_dsi_send_seq(panel, 0xA8, 0x6B);
    panel_dsi_send_seq(panel, 0xA9, 0x1C);
    panel_dsi_send_seq(panel, 0xAA, 0x27);
    panel_dsi_send_seq(panel, 0xAB, 0x66);
    panel_dsi_send_seq(panel, 0xAC, 0x19);
    panel_dsi_send_seq(panel, 0xAD, 0x16);
    panel_dsi_send_seq(panel, 0xAE, 0x4C);
    panel_dsi_send_seq(panel, 0xAF, 0x22);
    panel_dsi_send_seq(panel, 0xB0, 0x27);
    panel_dsi_send_seq(panel, 0xB1, 0x56);
    panel_dsi_send_seq(panel, 0xB2, 0x66);
    panel_dsi_send_seq(panel, 0xB3, 0x39);
    panel_dsi_send_seq(panel, 0xC0, 0x08);
    panel_dsi_send_seq(panel, 0xC1, 0x16);
    panel_dsi_send_seq(panel, 0xC2, 0x20);
    panel_dsi_send_seq(panel, 0xC3, 0x13);
    panel_dsi_send_seq(panel, 0xC4, 0x14);
    panel_dsi_send_seq(panel, 0xC5, 0x26);
    panel_dsi_send_seq(panel, 0xC6, 0x18);
    panel_dsi_send_seq(panel, 0xC7, 0x1C);
    panel_dsi_send_seq(panel, 0xC8, 0x6B);
    panel_dsi_send_seq(panel, 0xC9, 0x1C);
    panel_dsi_send_seq(panel, 0xCA, 0x27);
    panel_dsi_send_seq(panel, 0xCB, 0x66);
    panel_dsi_send_seq(panel, 0xCC, 0x19);
    panel_dsi_send_seq(panel, 0xCD, 0x16);
    panel_dsi_send_seq(panel, 0xCE, 0x4C);
    panel_dsi_send_seq(panel, 0xCF, 0x22);
    panel_dsi_send_seq(panel, 0xD0, 0x27);
    panel_dsi_send_seq(panel, 0xD1, 0x56);
    panel_dsi_send_seq(panel, 0xD2, 0x66);
    panel_dsi_send_seq(panel, 0xD3, 0x39);

    /* 回到 Page 0 */
    panel_dsi_send_seq(panel, 0xFF, 0x98, 0x81, 0x00);

    /* 与 panel_zc50289.c 的 panel_init 尾部一致：Sleep Out -> Display On */
    panel_dsi_send_seq(panel, 0x11);
    luat_rtos_task_sleep(120);
    panel_dsi_send_seq(panel, 0x29);
    luat_rtos_task_sleep(20);

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

/*DSI面板时序参数：720x1280、2-lane、30Hz
  left_margin=100 right_margin=100 hsync_len=10,
  upper_margin=30 lower_margin=20 vsync_len=2*/
static struct luat_display_timing ili9881c_timing = {
    .pclk_hz = 37162800,    /* (720+100+100+10) * (1280+30+20+2) * 30Hz */

    .hactive = 720,
    .hfp = 100,
    .hbp = 100,
    .hspw = 10,

    .vactive = 1280,
    .vfp = 20,
    .vbp = 30,
    .vspw = 2,
};

/*DSI接口参数：*/
struct panel_dsi ili9881c_dsi = 
{
    .mode = DSI_MOD_VID_BURST,
    .format = DSI_FMT_RGB888,
    .lane_num = 2,
    .vc_num = 0,
};

/*对DSI面板的描述*/
struct luat_display_panel dsi_panel_ili9881c = {
    .name = "BOE",
    .desc = "dsi",
    .connector_type = LUAT_DISPLAY_CONNECTOR_MIPI,
    .dsi = &ili9881c_dsi,
    .panel_funcs = &panel_funcs_dsi,
    .timing = &ili9881c_timing,
    .screen_win = NULL,
};

#endif /* LUAT_USE_MIPI_INF */


