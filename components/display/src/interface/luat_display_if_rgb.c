#include "luat_base.h"
#include "luat_display.h"

#define LUAT_LOG_TAG "display_rgb"
#include "luat_log.h"


/*通过SPI总线发送参数序列，请把第一个字节作为命令*/
LUAT_WEAK int rgb_spi_panel_send_sequence(struct luat_display_panel *panel, const unsigned char *data, uint32_t len)
{
    /*这里发送参数序列*/
    return 0;
}


/*显示缓冲区探测*/
LUAT_WEAK int rgb_fb_probe(struct luat_display_fb_info *info)
{
    /*这里初始化RGB面板*/
    return 0;
}

/*设置显示层*/
LUAT_WEAK int rgb_set_layer(struct luat_display_layer_data *layer_data)
{
    /*这里设置显示层*/
    return 0;
}


/*刷新显示缓冲区*/
LUAT_WEAK int rgb_fb_flush(int32_t x1, int32_t y1, int32_t x2, int32_t y2, void *data, enum disp_rotate rotation)
{
    /*这里刷新显示缓冲区*/
    return 0;
}

/*垂直同步*/
LUAT_WEAK int rgb_wait_vsync(void)
{
    /*这里等待垂直同步*/
    return 0;
}

/*显示面板*/
LUAT_WEAK int rgb_pan_display(int index)
{
    /*这里显示面板*/
    return 0;
}


struct luat_display_funcs rgb_funcs = {
    .name = "rgb",
    .fb_probe = rgb_fb_probe,
    .set_layer = rgb_set_layer,
    .fb_flush = rgb_fb_flush,
    .wait_vsync = rgb_wait_vsync,
    .pan_display = rgb_pan_display,
};




