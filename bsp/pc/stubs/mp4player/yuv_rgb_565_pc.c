/**
 * @file yuv_rgb_565_pc.c
 * @brief PC 模拟器版本的 YUV_RGB_565()。
 *
 * 设备侧这个符号由 mp4player/video_decode/yuv_rgb_565.s(Thumb-2 汇编, CCM42xx 专属)
 * 提供, PC 没有对应实现, 只有声明(video_decode/yuv_rgb_565.h), 而
 * components/mplayer/src/luat_mplayer.c 的 disp_output() 会调用它 -> PC 链接缺符号,
 * 所以这里补一个等价的 C 版本。
 *
 * 语义: YUV420P(分离平面) -> RGB565, BT.601 full range 的 8.8 定点近似
 *   R = Y + 1.402*(V-128)                  -> 359/256
 *   G = Y - 0.344*(U-128) - 0.714*(V-128)  ->  88/256, 183/256
 *   B = Y + 1.772*(U-128)                  -> 454/256
 * 颜色已核(2026-10-20): 经 stubs/mp4player/luat_display_pc.c 的无头 sink 落点,
 * 用 Lucy_480x320_aac.mp4 的第 1 帧 dump 成 BMP 目视比对, 肤色/发色自然,
 * 无 R/B 通道互换、无偏色, 与上式一致。仍未做与 yuv_rgb_565.s 的逐位对齐。
 *
 * 调用方(mp4_decode.c)的帧尺寸/步长来自解码器, 本函数不做越界校验:
 * 上游 API 不带缓冲大小参数, 且只有一个调用路径。
 */

#include "yuv_rgb_565.h"

#include <stdint.h>
#include <string.h>

#define YUV_RGB_565_CLAMP(v) ((v) < 0 ? 0 : ((v) > 255 ? 255 : (v)))

void YUV_RGB_565(void *dst, int width, int height, YUV_RGB_Param *param)
{
    const uint8_t *y_plane;
    const uint8_t *u_plane;
    const uint8_t *v_plane;
    uint16_t *out;
    int x, y;

    if (dst == NULL || param == NULL || width <= 0 || height <= 0) {
        return;
    }
    if (param->y_src == NULL || param->u_src == NULL || param->v_src == NULL) {
        return;
    }
    if (param->y_stride <= 0 || param->uv_stride <= 0) {
        return;
    }

    y_plane = (const uint8_t *)param->y_src;
    u_plane = (const uint8_t *)param->u_src;
    v_plane = (const uint8_t *)param->v_src;
    out = (uint16_t *)dst;

    for (y = 0; y < height; y++) {
        const uint8_t *yp = y_plane + (size_t)y * (size_t)param->y_stride;
        /* YUV420P: 色度平面垂直方向 2:1 采样, 同一色度行覆盖两行亮度 */
        const uint8_t *up = u_plane + (size_t)(y / 2) * (size_t)param->uv_stride;
        const uint8_t *vp = v_plane + (size_t)(y / 2) * (size_t)param->uv_stride;
        uint16_t *line = out + (size_t)y * (size_t)width;

        for (x = 0; x < width; x++) {
            int yy = (int)yp[x];
            int u = (int)up[x / 2] - 128;
            int v = (int)vp[x / 2] - 128;
            int r = yy + ((359 * v) >> 8);
            int g = yy - ((88 * u) >> 8) - ((183 * v) >> 8);
            int b = yy + ((454 * u) >> 8);

            line[x] = (uint16_t)(((YUV_RGB_565_CLAMP(r) & 0xF8) << 8) |
                                 ((YUV_RGB_565_CLAMP(g) & 0xFC) << 3) |
                                 ((YUV_RGB_565_CLAMP(b) & 0xF8) >> 3));
        }
    }
}
