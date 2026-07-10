#include "luat_base.h"
#include "luat_display_panel_comm.h"


#define LUAT_LOG_TAG "ili9341"
#include "luat_log.h"


#define panel_spi_send_seq(panel, seq...) do {                      \
        static const unsigned char d[] = { seq };                   \
        int ret;                                                    \
        ret = spi_panel_send_sequence(panel, d, ARRAY_SIZE(d));     \
        if (ret < 0)                                                \
            return ret;                                             \
    } while (0)

/*初始化面板*/
static int panel_init(struct luat_display_panel *panel) 
{
    
    panel_spi_send_seq(panel, 0xCF, 0x00, 0xD9, 0x30);
    panel_spi_send_seq(panel, 0xED, 0x64, 0x03, 0x12, 0x81);
    panel_spi_send_seq(panel, 0xE8, 0x85, 0x10, 0x78);
    panel_spi_send_seq(panel, 0xCB, 0x39, 0x2C, 0x00, 0x34, 0x02);
    panel_spi_send_seq(panel, 0xF7, 0x20);
    panel_spi_send_seq(panel, 0xEA, 0x00, 0x00);
    panel_spi_send_seq(panel, 0xC0, 0x21);
    panel_spi_send_seq(panel, 0xC1, 0x12);
    panel_spi_send_seq(panel, 0xC5, 0x32, 0x3C);
    panel_spi_send_seq(panel, 0xC7, 0xC1);
    panel_spi_send_seq(panel, 0xC5, 0x1A);
    panel_spi_send_seq(panel, 0x36, 0x00);
    panel_spi_send_seq(panel, 0x3A, 0x55);
    panel_spi_send_seq(panel, 0xB1, 0x00, 0x18);
    panel_spi_send_seq(panel, 0xB6, 0x0A, 0xA2);
    panel_spi_send_seq(panel, 0xF2, 0x00);
    panel_spi_send_seq(panel, 0x26, 0x01);
    panel_spi_send_seq(panel, 0xE0, 0x0F, 0x20, 0x1E, 0x09, 0x12, 0x0B, 0x50, 0xBA, 0x44, 0x09, 0x14, 0x05, 0x23, 0x21, 0x00);
    panel_spi_send_seq(panel, 0xE1, 0x00, 0x19, 0x19, 0x00, 0x12, 0x07, 0x2D, 0x28, 0x3F, 0x02, 0x0A, 0x08, 0x25, 0x2D, 0x0F);

    return 0;
}

/*关闭面板*/
static int panel_deinit(struct luat_display_panel *panel) 
{
    return 0;
}

/*控制面板*/
static int panel_ctrl(struct luat_display_panel *panel, uint8_t state)
{
    return 0;
}

/*SPI面板操作接口*/
static struct luat_display_panel_funcs panel_funcs_spi = {
    .panel_init     = panel_init,
    .panel_deinit   = panel_deinit,
    .panel_ctrl     = panel_ctrl,
};

/*对接口的描述*/
static struct panel_dbi ili9341_dbi = {
    .type = 0,
    .format = 0,
};

/*对液晶面板的描述*/
struct luat_display_panel spi_panel_ili9341 = {
    .name = "BOE",
    .desc = "spi_ili9341",
    .connector_type = LUAT_DISPLAY_CONNECTOR_DBI,
    .dbi = &ili9341_dbi,
    .panel_funcs = &panel_funcs_spi,
};


