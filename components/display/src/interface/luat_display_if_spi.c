#include "luat_base.h"
#include "luat_display.h"

#define LUAT_LOG_TAG "display_rgb"
#include "luat_log.h"


/*通过SPI总线发送参数序列，请把第一个字节作为命令*/
LUAT_WEAK int spi_panel_send_sequence(struct luat_display_panel *panel, const unsigned char *data, uint32_t len)
{
    /*这里发送参数序列*/
    return 0;
}


LUAT_WEAK int spi_fb_probe(struct luat_display_fb_info *info)
{
    return 0;
}

LUAT_WEAK int spi_set_layer(struct luat_display_layer_data *layer_data)
{
    return 0;
}

LUAT_WEAK int spi_fb_flush(int32_t x1, int32_t y1, int32_t x2, int32_t y2, const void *data, enum disp_rotate rotation)
{
    return 0;
}

LUAT_WEAK int spi_wait_vsync(void)
{
    return 0;
}

LUAT_WEAK int spi_pan_display(int index)
{
    return 0;
}


struct luat_display_funcs spi_funcs = {
    .name = "spi",
    .fb_probe = spi_fb_probe,
    .set_layer = spi_set_layer,
    .fb_flush = spi_fb_flush,
    .wait_vsync = spi_wait_vsync,
    .pan_display = spi_pan_display,
};


