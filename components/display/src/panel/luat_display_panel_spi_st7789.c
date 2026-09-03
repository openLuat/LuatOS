#include "luat_base.h"
#include "luat_display_panel_comm.h"


#define LUAT_LOG_TAG "st7789"
#include "luat_log.h"


#define panel_spi_send_seq(panel, ...) do {                         \
        static const unsigned char d[] = { __VA_ARGS__ };           \
        int ret;                                                    \
        ret = spi_panel_send_sequence(panel, d, ARRAY_SIZE(d));     \
        if (ret < 0)                                                \
            return ret;                                             \
    } while (0)


/*初始化面板*/
static int panel_init(struct luat_display_panel *panel) 
{
    /*使用默认的复位，如果复位时序不对，请使用自定义的*/
    luat_display_panel_reset(panel);
    
    panel_spi_send_seq(panel, 0x3A, 0x05);
    panel_spi_send_seq(panel, 0xB2, 0x0C, 0x0C, 0x00, 0x33, 0x33);
    panel_spi_send_seq(panel, 0xB7, 0x35);
    panel_spi_send_seq(panel, 0xBB, 0x32);
    panel_spi_send_seq(panel, 0xC2, 0x01);
    panel_spi_send_seq(panel, 0xC3, 0x15);
    panel_spi_send_seq(panel, 0xC4, 0x20);
    panel_spi_send_seq(panel, 0xC6, 0x0F);
    panel_spi_send_seq(panel, 0xD0, 0xA4, 0xA1);
    panel_spi_send_seq(panel, 0xE0, 0xD0, 0x08, 0x0E, 0x09, 0x09, 0x05, 0x31, 0x33, 0x48, 0x17, 0x14, 0x15, 0x31, 0x34);
    panel_spi_send_seq(panel, 0xE1, 0xD0, 0x08, 0x0E, 0x09, 0x09, 0x15, 0x31, 0x33, 0x48, 0x17, 0x14, 0x15, 0x31, 0x34);
    panel_spi_send_seq(panel, 0x21);

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

/*SPI面板操作接口*/
static struct luat_display_panel_funcs panel_funcs_spi = {
    .panel_init     = panel_init,
    .panel_deinit   = panel_deinit,
    .panel_ctrl     = panel_ctrl,
};

/*SPI面板显示窗口*/
static struct luat_display_rect spi_screen_win = {
    .x = 0,
    .y = 0,
    .w = 240,
    .h = 320,
};

/*对接口的描述*/
static struct panel_dbi st7789_dbi = {
    .type = 0,
    .format = 0,
};

/*对液晶面板的描述*/
struct luat_display_panel spi_panel_st7789 = {
    .name = "BOE",
    .desc = "spi_st7789",
    .connector_type = LUAT_DISPLAY_CONNECTOR_DBI,
    .dbi = &st7789_dbi,
    .panel_funcs = &panel_funcs_spi,
    .screen_win = &spi_screen_win,
};




