/**
 * @file yuv_rgb_565_pc.c
 * @brief PC simulator implementation of YUV_RGB_565() for luatos-ext-components/mp4player.
 *
 * mp4_decode.c (compiled under LUAT_USE_DISPLAY, i.e. the GUI builds) renders
 * decoded H.264 frames through YUV_RGB_565(), which is declared in
 * mp4player/video_decode/yuv_rgb_565.h but only implemented by the SoC C
 * library on real firmware — nothing in LuatOS provides it, so the PC link
 * fails with an unresolved external.
 *
 * The conversion itself already exists in the same library as
 * yuv420p_to_rgb565_thumb() (avcodec/h264_decode.c, BT.601 full range integer
 * approximation), so this stub just adapts the parameter struct instead of
 * duplicating the pixel math.
 *
 * Note: the buffer size is decided by the caller (mp4_decode.c's static
 * s_video_rgb_buf, 480x320); this function cannot range-check it because the
 * upstream API carries no size argument. Only that single caller exists.
 */

#include "yuv_rgb_565.h"

#include "avcodec/h264_decode.h"

void YUV_RGB_565(void *dst, int width, int height, YUV_RGB_Param *param)
{
    if (dst == NULL || param == NULL || width <= 0 || height <= 0) {
        return;
    }
    if (param->y_src == NULL || param->u_src == NULL || param->v_src == NULL) {
        return;
    }
    if (param->y_stride <= 0 || param->uv_stride <= 0) {
        return;
    }

    yuv420p_to_rgb565_thumb((uint8_t *)param->y_src,
                            (uint8_t *)param->u_src,
                            (uint8_t *)param->v_src,
                            (uint16_t *)dst,
                            width,
                            height,
                            param->y_stride,
                            param->uv_stride);
}
