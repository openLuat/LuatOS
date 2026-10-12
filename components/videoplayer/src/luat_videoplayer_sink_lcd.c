/**
 * @file luat_videoplayer_sink_lcd.c
 * @summary videoplayer 绘制后端：旧 lcd 库
 */
#include "luat_conf_bsp.h"
#include "luat_videoplayer_sink.h"

#if defined(LUAT_USE_LCD)

#include "luat_lcd.h"

int luat_videoplayer_sink_lcd_present(void)
{
    return 1;
}

int luat_videoplayer_sink_lcd_draw(luat_vp_frame_t *frame, int16_t x, int16_t y, uint8_t *consumed)
{
    luat_lcd_conf_t *conf;

    if (consumed != NULL) {
        *consumed = 0;
    }
    if (frame == NULL || frame->data == NULL || frame->width == 0 || frame->height == 0) {
        return LUAT_VP_ERR_PARAM;
    }

    conf = luat_lcd_get_default();
    if (conf == NULL) {
        return LUAT_VP_ERR_NOIMPL;
    }

    luat_lcd_draw(conf, x, y, (int16_t)(x + frame->width - 1), (int16_t)(y + frame->height - 1),
                  (luat_color_t *)frame->data);
    luat_lcd_flush(conf);
    return LUAT_VP_OK;
}

#else

int luat_videoplayer_sink_lcd_present(void)
{
    return 0;
}

int luat_videoplayer_sink_lcd_draw(luat_vp_frame_t *frame, int16_t x, int16_t y, uint8_t *consumed)
{
    (void)frame;
    (void)x;
    (void)y;
    if (consumed != NULL) {
        *consumed = 0;
    }
    return LUAT_VP_ERR_NOIMPL;
}

#endif
