#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_if_comm.h"

#define LUAT_LOG_TAG "display_spi"
#include "luat_log.h"


/*通过SPI总线发送参数序列，请把第一个字节作为命令*/
LUAT_WEAK int spilcd_panel_send_sequence(struct luat_display_panel *panel, const unsigned char *data, uint32_t len)
{
    /*这里发送参数序列*/
    return -1;
}

/*显示缓冲区探测*/
LUAT_WEAK int spilcd_fb_probe(struct luat_display_panel *panel, struct luat_display_fb_info *info)
{
    return -1;
}

/*设置timing*/
LUAT_WEAK int spilcd_inf_init(struct luat_display *disp)
{
    /*这里设置timing参数*/
    return -1;
}

/*设置显示层*/
LUAT_WEAK int spilcd_set_layer(struct luat_display_layer_data *layer_data)
{
    /*这里设置显示层*/
    return -1;
}

LUAT_WEAK int spilcd_fb_flush(struct luat_display *disp, struct luat_display_rect *rect, const void *data, enum disp_rotate rotation)
{
    return -1;
}

LUAT_WEAK int spilcd_wait_vsync(struct luat_display *disp)
{
    return -1;
}

LUAT_WEAK int spilcd_pan_display(struct luat_display *disp, int index)
{
    return -1;
}

LUAT_WEAK int spilcd_deinit(struct luat_display *disp)
{
    return 0;
}


struct luat_display_funcs spi_funcs = {
    .name = "spi",
    .fb_probe = spilcd_fb_probe,
    .inf_init = spilcd_inf_init,
    .fb_flush = spilcd_fb_flush,
    .set_layer = spilcd_set_layer,
    .wait_vsync = spilcd_wait_vsync,
    .pan_display = spilcd_pan_display,
    .deinit = spilcd_deinit,
};


