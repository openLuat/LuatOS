#include "luat_base.h"
#include "luat_display_panel_comm.h"
#include "luat_rtos.h"


#define LUAT_LOG_TAG "nv3052c"
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
    
    // Page Select 0x01
    panel_spi_send_seq(panel, 0xFF, 0x30, 0x52, 0x01);
    // 0xE3, 0x00
    panel_spi_send_seq(panel, 0xE3, 0x00);
    // 0x0A, 0x01
    panel_spi_send_seq(panel, 0x0A, 0x01);
    // 0x23, 0xA2
    panel_spi_send_seq(panel, 0x23, 0xA2);
    // 0x24, 0x10
    panel_spi_send_seq(panel, 0x24, 0x10);
    // 0x25, 0x0A
    panel_spi_send_seq(panel, 0x25, 0x0A);
    // 0x26, 0x3C
    panel_spi_send_seq(panel, 0x26, 0x3C);
    // 0x27, 0x46
    panel_spi_send_seq(panel, 0x27, 0x46);
    // 0x38, 0x9C
    panel_spi_send_seq(panel, 0x38, 0x9C);
    // 0x39, 0xA7
    panel_spi_send_seq(panel, 0x39, 0xA7);
    // 0x3A, 0x47
    panel_spi_send_seq(panel, 0x3A, 0x47);
    // 0x91, 0x77
    panel_spi_send_seq(panel, 0x91, 0x77);
    // 0x92, 0x77
    panel_spi_send_seq(panel, 0x92, 0x77);
    // 0x99, 0x51
    panel_spi_send_seq(panel, 0x99, 0x51);
    // 0x9B, 0x59
    panel_spi_send_seq(panel, 0x9B, 0x59);
    // 0xA0, 0x55
    panel_spi_send_seq(panel, 0xA0, 0x55);
    // 0xA1, 0x50
    panel_spi_send_seq(panel, 0xA1, 0x50);
    // 0xA4, 0x9C
    panel_spi_send_seq(panel, 0xA4, 0x9C);
    // 0xA7, 0x02
    panel_spi_send_seq(panel, 0xA7, 0x02);
    // 0xA8, 0x01
    panel_spi_send_seq(panel, 0xA8, 0x01);
    // 0xA9, 0x01
    panel_spi_send_seq(panel, 0xA9, 0x01);
    // 0xAA, 0xFC
    panel_spi_send_seq(panel, 0xAA, 0xFC);
    // 0xAB, 0x28
    panel_spi_send_seq(panel, 0xAB, 0x28);
    // 0xAC, 0x06
    panel_spi_send_seq(panel, 0xAC, 0x06);
    // 0xAD, 0x06
    panel_spi_send_seq(panel, 0xAD, 0x06);
    // 0xAE, 0x06
    panel_spi_send_seq(panel, 0xAE, 0x06);
    // 0xAF, 0x03
    panel_spi_send_seq(panel, 0xAF, 0x03);
    // 0xB0, 0x08
    panel_spi_send_seq(panel, 0xB0, 0x08);
    // 0xB1, 0x26
    panel_spi_send_seq(panel, 0xB1, 0x26);
    // 0xB2, 0x28
    panel_spi_send_seq(panel, 0xB2, 0x28);
    // 0xB3, 0x28
    panel_spi_send_seq(panel, 0xB3, 0x28);
    // 0xB4, 0x03
    panel_spi_send_seq(panel, 0xB4, 0x03);
    // 0xB5, 0x08
    panel_spi_send_seq(panel, 0xB5, 0x08);
    // 0xB6, 0x26
    panel_spi_send_seq(panel, 0xB6, 0x26);
    // 0xB7, 0x08
    panel_spi_send_seq(panel, 0xB7, 0x08);
    // 0xB8, 0x26
    panel_spi_send_seq(panel, 0xB8, 0x26);

    // Page Select 0x02
    panel_spi_send_seq(panel, 0xFF, 0x30, 0x52, 0x02);
    // 0xB0~0xE1
    panel_spi_send_seq(panel, 0xB0, 0x01);
    panel_spi_send_seq(panel, 0xB1, 0x12);
    panel_spi_send_seq(panel, 0xB2, 0x09);
    panel_spi_send_seq(panel, 0xB3, 0x2B);
    panel_spi_send_seq(panel, 0xB4, 0x2F);
    panel_spi_send_seq(panel, 0xB5, 0x30);
    panel_spi_send_seq(panel, 0xB6, 0x19);
    panel_spi_send_seq(panel, 0xB7, 0x35);
    panel_spi_send_seq(panel, 0xB8, 0x0D);
    panel_spi_send_seq(panel, 0xB9, 0x03);
    panel_spi_send_seq(panel, 0xBA, 0x12);
    panel_spi_send_seq(panel, 0xBB, 0x12);
    panel_spi_send_seq(panel, 0xBC, 0x14);
    panel_spi_send_seq(panel, 0xBD, 0x15);
    panel_spi_send_seq(panel, 0xBE, 0x18);
    panel_spi_send_seq(panel, 0xBF, 0x0F);
    panel_spi_send_seq(panel, 0xC0, 0x17);
    panel_spi_send_seq(panel, 0xC1, 0x08);
    panel_spi_send_seq(panel, 0xD0, 0x0F);
    panel_spi_send_seq(panel, 0xD1, 0x12);
    panel_spi_send_seq(panel, 0xD2, 0x1A);
    panel_spi_send_seq(panel, 0xD3, 0x38);
    panel_spi_send_seq(panel, 0xD4, 0x36);
    panel_spi_send_seq(panel, 0xD5, 0x3A);
    panel_spi_send_seq(panel, 0xD6, 0x22);
    panel_spi_send_seq(panel, 0xD7, 0x40);
    panel_spi_send_seq(panel, 0xD8, 0x0D);
    panel_spi_send_seq(panel, 0xD9, 0x03);
    panel_spi_send_seq(panel, 0xDA, 0x11);
    panel_spi_send_seq(panel, 0xDB, 0x10);
    panel_spi_send_seq(panel, 0xDC, 0x12);
    panel_spi_send_seq(panel, 0xDD, 0x13);
    panel_spi_send_seq(panel, 0xDE, 0x18);
    panel_spi_send_seq(panel, 0xDF, 0x10);
    panel_spi_send_seq(panel, 0xE0, 0x17);
    panel_spi_send_seq(panel, 0xE1, 0x08);

    // Page Select 0x03
    panel_spi_send_seq(panel, 0xFF, 0x30, 0x52, 0x03);
    // 0x00~0xCD
    panel_spi_send_seq(panel, 0x00, 0x2A);
    panel_spi_send_seq(panel, 0x01, 0x2A);
    panel_spi_send_seq(panel, 0x02, 0x2A);
    panel_spi_send_seq(panel, 0x03, 0x2A);
    panel_spi_send_seq(panel, 0x08, 0x02);
    panel_spi_send_seq(panel, 0x09, 0x03);
    panel_spi_send_seq(panel, 0x0A, 0x04);
    panel_spi_send_seq(panel, 0x0B, 0x05);
    panel_spi_send_seq(panel, 0x30, 0x2A);
    panel_spi_send_seq(panel, 0x31, 0x2A);
    panel_spi_send_seq(panel, 0x32, 0x2A);
    panel_spi_send_seq(panel, 0x33, 0x2A);
    panel_spi_send_seq(panel, 0x34, 0x81);
    panel_spi_send_seq(panel, 0x35, 0x26);
    panel_spi_send_seq(panel, 0x37, 0x13);
    panel_spi_send_seq(panel, 0x40, 0x03);
    panel_spi_send_seq(panel, 0x41, 0x04);
    panel_spi_send_seq(panel, 0x42, 0x05);
    panel_spi_send_seq(panel, 0x43, 0x06);
    panel_spi_send_seq(panel, 0x45, 0x08);
    panel_spi_send_seq(panel, 0x46, 0x09);
    panel_spi_send_seq(panel, 0x48, 0x0A);
    panel_spi_send_seq(panel, 0x49, 0x0B);
    panel_spi_send_seq(panel, 0x50, 0x07);
    panel_spi_send_seq(panel, 0x51, 0x08);
    panel_spi_send_seq(panel, 0x52, 0x09);
    panel_spi_send_seq(panel, 0x53, 0x0A);
    panel_spi_send_seq(panel, 0x55, 0x0C);
    panel_spi_send_seq(panel, 0x56, 0x0D);
    panel_spi_send_seq(panel, 0x58, 0x0E);
    panel_spi_send_seq(panel, 0x59, 0x0F);
    panel_spi_send_seq(panel, 0x80, 0x00);
    panel_spi_send_seq(panel, 0x81, 0x00);
    panel_spi_send_seq(panel, 0x82, 0x04);
    panel_spi_send_seq(panel, 0x83, 0x02);
    panel_spi_send_seq(panel, 0x84, 0x0E);
    panel_spi_send_seq(panel, 0x85, 0x10);
    panel_spi_send_seq(panel, 0x86, 0x0A);
    panel_spi_send_seq(panel, 0x87, 0x0C);
    panel_spi_send_seq(panel, 0x91, 0x00);
    panel_spi_send_seq(panel, 0x92, 0x00);
    panel_spi_send_seq(panel, 0x93, 0x00);
    panel_spi_send_seq(panel, 0x94, 0x1F);
    panel_spi_send_seq(panel, 0x95, 0x1F);
    panel_spi_send_seq(panel, 0x96, 0x00);
    panel_spi_send_seq(panel, 0x97, 0x00);
    panel_spi_send_seq(panel, 0x98, 0x03);
    panel_spi_send_seq(panel, 0x99, 0x01);
    panel_spi_send_seq(panel, 0x9A, 0x0D);
    panel_spi_send_seq(panel, 0x9B, 0x0F);
    panel_spi_send_seq(panel, 0x9C, 0x09);
    panel_spi_send_seq(panel, 0x9D, 0x0B);
    panel_spi_send_seq(panel, 0xA7, 0x00);
    panel_spi_send_seq(panel, 0xA8, 0x00);
    panel_spi_send_seq(panel, 0xA9, 0x00);
    panel_spi_send_seq(panel, 0xAA, 0x1F);
    panel_spi_send_seq(panel, 0xAB, 0x1F);
    panel_spi_send_seq(panel, 0xB0, 0x00);
    panel_spi_send_seq(panel, 0xB1, 0x1F);
    panel_spi_send_seq(panel, 0xB2, 0x01);
    panel_spi_send_seq(panel, 0xB3, 0x03);
    panel_spi_send_seq(panel, 0xB4, 0x0B);
    panel_spi_send_seq(panel, 0xB5, 0x09);
    panel_spi_send_seq(panel, 0xB6, 0x0F);
    panel_spi_send_seq(panel, 0xB7, 0x0D);
    panel_spi_send_seq(panel, 0xC1, 0x00);
    panel_spi_send_seq(panel, 0xC2, 0x00);
    panel_spi_send_seq(panel, 0xC3, 0x00);
    panel_spi_send_seq(panel, 0xC4, 0x1F);
    panel_spi_send_seq(panel, 0xC5, 0x00);
    panel_spi_send_seq(panel, 0xC6, 0x00);
    panel_spi_send_seq(panel, 0xC7, 0x1F);
    panel_spi_send_seq(panel, 0xC8, 0x02);
    panel_spi_send_seq(panel, 0xC9, 0x04);
    panel_spi_send_seq(panel, 0xCA, 0x0C);
    panel_spi_send_seq(panel, 0xCB, 0x0A);
    panel_spi_send_seq(panel, 0xCC, 0x10);
    panel_spi_send_seq(panel, 0xCD, 0x0E);
    panel_spi_send_seq(panel, 0xD7, 0x00);
    panel_spi_send_seq(panel, 0xD8, 0x00);
    panel_spi_send_seq(panel, 0xD9, 0x00);
    panel_spi_send_seq(panel, 0xDA, 0x1F);
    panel_spi_send_seq(panel, 0xDB, 0x00);

    // Page Select 0x00
    panel_spi_send_seq(panel, 0xFF, 0x30, 0x52, 0x00);
    // 0x36, 0x0A (显示方向)
    panel_spi_send_seq(panel, 0x36, 0x0A);

    // 退出睡眠模式
    panel_spi_send_seq(panel, 0x11, 0x00);
    luat_rtos_task_sleep(200);

    // 显示开启
    panel_spi_send_seq(panel, 0x29, 0x00);
    luat_rtos_task_sleep(100);

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
    return 0;
}

/*RGB面板操作接口*/
static struct luat_display_panel_funcs panel_funcs_rgb = {
    .panel_init     = panel_init,
    .panel_deinit   = panel_deinit,
    .panel_ctrl     = panel_ctrl,
};

/*RGB面板时序参数*/
static struct luat_display_timing nv3052c_timing = {
    
    .pclk_hz = 30 * 1000 * 1000,

    .hactive = 480,
    .hfp = 30,
    .hbp = 30,
    .hspw = 10,

    .vactive = 854,
    .vfp = 8,
    .vbp = 16,
    .vspw = 2,

    .flags = DISPLAY_FLAGS_HSYNC_LOW | DISPLAY_FLAGS_VSYNC_LOW,
};

/*RGB接口参数*/
struct panel_rgb nv3052c_rgb = 
{
    .mode = PRGB,
    .format = LUAT_DISPLAY_FORMAT_RGB565,
    .data_order = RGB_ORDER,
    .data_mirror = 0,
};

/*对RGB面板的描述*/
struct luat_display_panel rgb_panel_nv3052c = {
    .name = "NV3052C",
    .desc = "spi+rgb",
    .connector_type = LUAT_DISPLAY_CONNECTOR_RGB,
    .rgb = &nv3052c_rgb,
    .panel_funcs = &panel_funcs_rgb,
    .timing = &nv3052c_timing,
    .screen_win = NULL,
};


