#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_if_comm.h"

#define LUAT_LOG_TAG "display_spi"
#include "luat_log.h"


/*通过SPI总线发送参数序列，请把第一个字节作为命令*/
LUAT_WEAK int spi_panel_send_sequence(struct luat_display_panel *panel, const unsigned char *data, uint32_t len)
{
    /*这里发送参数序列*/
    return -1;
}

/*显示缓冲区探测*/
LUAT_WEAK int spi_fb_probe(struct luat_display_panel *panel, struct luat_display_fb_info *info)
{
    return -1;
}

/*设置timing*/
LUAT_WEAK int spi_inf_init(struct luat_display_panel *panel)
{
    /*这里设置timing参数*/
    return -1;
}

/*设置显示层*/
LUAT_WEAK int spi_set_layer(struct luat_display_layer_data *layer_data)
{
    /*这里设置显示层*/
    return -1;
}

LUAT_WEAK int spi_fb_flush(struct luat_display_rect *rect, const void *data, enum disp_rotate rotation)
{
    return -1;
}

LUAT_WEAK int spi_wait_vsync(void)
{
    return -1;
}

LUAT_WEAK int spi_pan_display(int index)
{
    return -1;
}


struct luat_display_funcs spi_funcs = {
    .name = "spi",
    .fb_probe = spi_fb_probe,
    .inf_init = spi_inf_init,
    .set_layer = spi_set_layer,
    .fb_flush = spi_fb_flush,
    .wait_vsync = spi_wait_vsync,
    .pan_display = spi_pan_display,
};


