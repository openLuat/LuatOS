/**
 * @file luat_videoplayer_sink_display.c
 * @summary videoplayer 绘制后端：新 display 库
 */
#include "luat_conf_bsp.h"
#include "luat_videoplayer_sink.h"

#if defined(LUAT_USE_DISPLAY)

#define DEFAULT_DISPLAY_LAYER 1

#include "luat_display.h"
#if DEFAULT_DISPLAY_LAYER == 0
#include "luat_display_surface.h"
#endif
#ifdef __LUATOS__
#include "luat_malloc.h"
#else
#include <stdlib.h>
#endif

#if DEFAULT_DISPLAY_LAYER
static struct luat_display_layer_data g_layer_data;
static uint8_t *s_vp_layer_prev = NULL;
#endif

int luat_videoplayer_sink_display_present(void)
{
    return 1;
}

int luat_videoplayer_sink_display_draw(luat_vp_frame_t *frame, int16_t x, int16_t y, uint8_t *consumed)
{
    struct luat_display *disp;

    if (frame == NULL || frame->data == NULL || frame->width == 0 || frame->height == 0) {
        return LUAT_VP_ERR_PARAM;
    }

    disp = luat_display_get_default();
    if (disp == NULL) {
        return LUAT_VP_ERR_NOIMPL;
    }

#if DEFAULT_DISPLAY_LAYER == 0
    SURFACE video_suf = {
        .w = frame->width,
        .h = frame->height,
        .bpp = 16,
        .pixels = frame->data,
        .pitch = frame->width * 2,
        .fmt = LUAT_DISPLAY_FORMAT_RGB565,
    };

    luat_draw_set_display_target(disp);
    luat_draw_surface(&video_suf, x, y);
    luat_display_flush(disp);
    if (consumed != NULL) {
        *consumed = 0;
    }
    return LUAT_VP_OK;
#else
    if (disp->display_funcs == NULL || disp->display_funcs->set_layer == NULL) {
        return LUAT_VP_ERR_NOIMPL;
    }

    if (g_layer_data.enable == 0) {
        g_layer_data.enable = 1;
        g_layer_data.layer_id = 1;
        g_layer_data.area.x1 = x;
        g_layer_data.area.y1 = y;
        g_layer_data.area.x2 = x + frame->width;
        g_layer_data.area.y2 = y + frame->height;
        g_layer_data.alpha = 255;
        g_layer_data.format = LUAT_DISPLAY_FORMAT_RGB565;
    }
    g_layer_data.buffer = frame->data;
    disp->display_funcs->set_layer(&g_layer_data);
    if (s_vp_layer_prev != NULL && s_vp_layer_prev != frame->data) {
#ifdef __LUATOS__
        luat_heap_free(s_vp_layer_prev);
#else
        free(s_vp_layer_prev);
#endif
    }
    s_vp_layer_prev = frame->data;
    if (consumed != NULL) {
        *consumed = 1;
    }
    return LUAT_VP_OK;
#endif
}

#else

int luat_videoplayer_sink_display_present(void)
{
    return 0;
}

int luat_videoplayer_sink_display_draw(luat_vp_frame_t *frame, int16_t x, int16_t y, uint8_t *consumed)
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
