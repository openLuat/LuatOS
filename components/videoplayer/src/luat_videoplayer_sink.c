/**
 * @file luat_videoplayer_sink.c
 * @summary videoplayer 绘制调度：display → lcd，绑定层不依赖底层库
 */
#include "luat_videoplayer_sink.h"

int luat_videoplayer_sink_available(void)
{
    return luat_videoplayer_sink_display_present() || luat_videoplayer_sink_lcd_present();
}

int luat_videoplayer_sink_draw(luat_vp_frame_t *frame, int16_t x, int16_t y, uint8_t *consumed)
{
    int ret;

    if (consumed != NULL) {
        *consumed = 0;
    }
    ret = luat_videoplayer_sink_display_draw(frame, x, y, consumed);
    if (ret != LUAT_VP_ERR_NOIMPL) {
        return ret;
    }
    if (consumed != NULL) {
        *consumed = 0;
    }
    return luat_videoplayer_sink_lcd_draw(frame, x, y, consumed);
}
