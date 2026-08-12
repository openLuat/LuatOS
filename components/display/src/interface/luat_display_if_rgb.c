#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_if_comm.h"

#define LUAT_LOG_TAG "display_rgb"
#include "luat_log.h"


/*通过SPI总线发送参数序列，请把第一个字节作为命令*/
LUAT_WEAK int rgb_spi_panel_send_sequence(struct luat_display_panel *panel, const unsigned char *data, uint32_t len)
{
    /*这里发送参数序列*/
    return -1;
}


/*显示缓冲区探测*/
LUAT_WEAK int rgb_fb_probe(struct luat_display_panel *panel, struct luat_display_fb_info *info)
{
    /*这里初始化RGB面板*/
    return -1;
}

/*初始化接口，在这里设置timing参数*/
LUAT_WEAK int rgb_inf_init(struct luat_display *disp)
{
    /*这里设置timing参数*/
    return -1;
}

/*设置显示层*/
LUAT_WEAK int rgb_set_layer(struct luat_display_layer_data *layer_data)
{
    /*这里设置显示层*/
    return -1;
}


/*刷新显示缓冲区*/
LUAT_WEAK int rgb_fb_flush(struct luat_display *disp, struct luat_display_rect *rect, const void *data, enum disp_rotate rotation)
{
    /*这里刷新显示缓冲区*/
    return -1;
}

/*垂直同步*/
LUAT_WEAK int rgb_wait_vsync(struct luat_display *disp)
{
    /*这里等待垂直同步*/
    return -1;
}

/*显示面板*/
LUAT_WEAK int rgb_pan_display(struct luat_display *disp, int index)
{
    /*这里显示面板*/
    return -1;
}

/*反初始化接口*/
LUAT_WEAK int rgb_deinit(struct luat_display *disp)
{
    return 0;
}


struct luat_display_funcs rgb_funcs = {
    .name = "rgb",
    .fb_probe = rgb_fb_probe,
    .inf_init = rgb_inf_init,
    .fb_flush = rgb_fb_flush,
    .set_layer = rgb_set_layer,
    .wait_vsync = rgb_wait_vsync,
    .pan_display = rgb_pan_display,
    .deinit = rgb_deinit,
};




