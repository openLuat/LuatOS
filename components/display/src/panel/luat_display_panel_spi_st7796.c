#include "luat_base.h"
#include "luat_display_panel_comm.h"
#include "luat_rtos.h"


#define LUAT_LOG_TAG "st7789"
#include "luat_log.h"


#define panel_spi_send_seq(panel, ...) do {                         \
        static const unsigned char d[] = { __VA_ARGS__ };           \
        int ret;                                                    \
        ret = spilcd_panel_send_sequence(panel, d, ARRAY_SIZE(d));  \
        if (ret < 0)                                                \
            return ret;                                             \
    } while (0)


/*初始化面板*/
static int panel_init(struct luat_display_panel *panel) 
{
    /*使用默认的复位，如果复位时序不对，请使用自定义的*/
    luat_display_panel_reset(panel);

    panel_spi_send_seq(panel, 0x11);
    luat_rtos_task_sleep(120);

    panel_spi_send_seq(panel, 0xF0, 0xC3);
    panel_spi_send_seq(panel, 0xF0, 0x96);
    panel_spi_send_seq(panel, 0x36, 0x48);
    panel_spi_send_seq(panel, 0x3A, 0x05);

    panel_spi_send_seq(panel, 0xB1, 0x00, 0x10);  //FRMCTR1

    panel_spi_send_seq(panel, 0xE8, 0x40, 0x82, 0x07, 0x18, 0x27, 0x0A, 0xB6, 0x33);
    panel_spi_send_seq(panel, 0xC5, 0x27);
    panel_spi_send_seq(panel, 0xC2, 0xA7);

    panel_spi_send_seq(panel, 0xE0, 0xF0, 0x01, 0x06, 0x0F, 0x12, 0x1D, 0x36, 0x54, 0x44, 0x0C, 0x18, 0x16, 0x13, 0x15);
    panel_spi_send_seq(panel, 0xE1, 0xF0, 0x01, 0x05, 0x0A, 0x0B, 0x07, 0x32, 0x44, 0x44, 0x0C, 0x18, 0x17, 0x13, 0x16);

    panel_spi_send_seq(panel, 0xF0, 0x3C);
    panel_spi_send_seq(panel, 0xF0, 0x69);


    panel_spi_send_seq(panel, 0x35, 0x00);  //TE ON

    panel_spi_send_seq(panel, 0x29);
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
    /*如果有特殊命令请放在这里处理*/
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
struct luat_display_panel spi_panel_st7796 = {
    .name = "st7796",
    .desc = "spi_st7796",
    .connector_type = LUAT_DISPLAY_CONNECTOR_DBI,
    .dbi = &st7789_dbi,
    .panel_funcs = &panel_funcs_spi,
    .screen_win = &spi_screen_win,
};




