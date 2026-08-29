#include "luat_base.h"
#include "luat_display_panel_comm.h"
#include "luat_rtos.h"


#define LUAT_LOG_TAG "st7701s"
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
    
    panel_spi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x13);
    panel_spi_send_seq(panel, 0xEF, 0x08);
    panel_spi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x10);
    panel_spi_send_seq(panel, 0xC0, 0xE9, 0x03);
    panel_spi_send_seq(panel, 0xC1, 0x11, 0x02);
    panel_spi_send_seq(panel, 0xC2, 0x01, 0x08);
    panel_spi_send_seq(panel, 0xCC, 0x18);
    panel_spi_send_seq(panel, 0xB0, 0x00, 0x0D, 0x14, 0x0D, 0x10, 0x05, 0x02, 0x08, 0x08, 0x1E, 0x05, 0x13, 0x11, 0xA3, 0x29, 0x18);
    panel_spi_send_seq(panel, 0xB1, 0x00, 0x0C, 0x14, 0x0C, 0x10, 0x05, 0x03, 0x08, 0x07, 0x20, 0x05, 0x13, 0x11, 0xA4, 0x29, 0x18);
    panel_spi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x11);
    panel_spi_send_seq(panel, 0xB0, 0x6C);
    panel_spi_send_seq(panel, 0xB1, 0x43);
    panel_spi_send_seq(panel, 0xB2, 0x87);
    panel_spi_send_seq(panel, 0xB3, 0x80);
    panel_spi_send_seq(panel, 0xB5, 0x47);
    panel_spi_send_seq(panel, 0xB7, 0x85);
    panel_spi_send_seq(panel, 0xB8, 0x20);
    panel_spi_send_seq(panel, 0xB9, 0x10);
    panel_spi_send_seq(panel, 0xC1, 0x78);
    panel_spi_send_seq(panel, 0xC2, 0x78);
    panel_spi_send_seq(panel, 0xD0, 0x88);
    luat_rtos_task_sleep(100);

    panel_spi_send_seq(panel, 0xE0, 0x00, 0x00, 0x02);
    panel_spi_send_seq(panel, 0xE1, 0x08, 0x00, 0x0A, 0x00, 0x07, 0x00, 0x09, 0x00, 0x00, 0x33, 0x33);
    panel_spi_send_seq(panel, 0xE2, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
    panel_spi_send_seq(panel, 0xE3, 0x00, 0x00, 0x33, 0x33);
    panel_spi_send_seq(panel, 0xE4, 0x44, 0x44);
    panel_spi_send_seq(panel, 0xE5, 0x0E, 0x60, 0xA0, 0xA0, 0x10, 0x60, 0xA0, 0xA0, 0x0A, 0x60, 0xA0, 0xA0, 0x0C, 0x60, 0xA0, 0xA0);
    panel_spi_send_seq(panel, 0xE6, 0x00, 0x00, 0x33, 0x33);
    panel_spi_send_seq(panel, 0xE7, 0x44, 0x44);
    panel_spi_send_seq(panel, 0xE8, 0x0D, 0x60, 0xA0, 0xA0, 0x0F, 0x60, 0xA0, 0xA0, 0x09, 0x60, 0xA0, 0xA0, 0x0B, 0x60, 0xA0, 0xA0);
    panel_spi_send_seq(panel, 0xEB, 0x02, 0x01, 0xE4, 0xE4, 0x44, 0x00, 0x40);
    panel_spi_send_seq(panel, 0xEC, 0x02, 0x01);
    panel_spi_send_seq(panel, 0xED, 0xAB, 0x89, 0x76, 0x54, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x10, 0x45, 0x67, 0x98, 0xBA);
    panel_spi_send_seq(panel, 0xEF, 0x08, 0x08, 0x08, 0x45, 0x3F, 0x54);
    panel_spi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x13);
    panel_spi_send_seq(panel, 0xE8, 0x00, 0x0E);
    panel_spi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x00);
    panel_spi_send_seq(panel, 0x11);
    luat_rtos_task_sleep(120);

    panel_spi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x13);
    panel_spi_send_seq(panel, 0xE8, 0x00, 0x0C);
    luat_rtos_task_sleep(10);

    panel_spi_send_seq(panel, 0xE8, 0x00, 0x00);
    panel_spi_send_seq(panel, 0xFF, 0x77, 0x01, 0x00, 0x00, 0x00);
    panel_spi_send_seq(panel, 0x29);
    panel_spi_send_seq(panel, 0x3A, 0x77);
    panel_spi_send_seq(panel, 0x36, 0x08);
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
    return 0;
}

/*RGB面板操作接口*/
static struct luat_display_panel_funcs panel_funcs_rgb = {
    .panel_init     = panel_init,
    .panel_deinit   = panel_deinit,
    .panel_ctrl     = panel_ctrl,
};

/*RGB面板时序参数*/
static struct luat_display_timing st7701s_timing = {
    
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
struct panel_rgb st7701s_rgb = 
{
    .mode = PRGB,
    .format = LUAT_DISPLAY_FORMAT_RGB565,
    .data_order = RGB_ORDER,
    .data_mirror = 0,
};

/*对RGB面板的描述*/
struct luat_display_panel rgb_panel_st7701s = {
    .name = "BOE",
    .desc = "spi+rgb",
    .connector_type = LUAT_DISPLAY_CONNECTOR_RGB,
    .rgb = &st7701s_rgb,
    .panel_funcs = &panel_funcs_rgb,
    .timing = &st7701s_timing,
    .screen_win = NULL,
};


