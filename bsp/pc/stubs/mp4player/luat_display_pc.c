/**
 * @file luat_display_pc.c
 * @brief 非 GUI 的 PC 模拟器构建下, 给 mplayer 提供**无头视频层落点**(headless sink)。
 *
 * 背景: components/mplayer/src/luat_mplayer.c 通过
 *   display = luat_display_get_default();
 *   display->display_funcs->set_layer(&g_video_layer);
 * 提交视频层, 然后在 movie_render_task 里逐帧回调 disp_output() 把 YUV420P 转成
 * RGB565 写进 g_video_layer.buffer。PC 的 components/display 只在 GUI 构建里编译
 * (bsp/pc/xmake.lua 的 use_gui 分支), 所以非 GUI 构建缺 luat_display_get_default(),
 * mplayer 会链接失败 —— 本文件即为该符号的唯一提供方(仅 not use_gui 时编入)。
 *
 * 这里返回一个**不显示任何东西的假 display**:
 *   - 让 set_rect() 不再因 "display not ready" 直接失败, 从而真的分配视频层缓冲;
 *   - 于是 disp_output() / YUV_RGB_565() 会被真正执行(在此之前这段代码在 PC 上是死的);
 *   - set_layer() 在**关层**(enable=0)时对缓冲区做一次取证快照。
 *
 * 为什么关层那一刻能取证: mplayer_video_buf_release() 先关层(set_layer, enable=0)
 * 再 luat_heap_free(s_video_buf), 即回调时 buffer 仍指向视频层内存, 且解码线程已停,
 * 里面就是最后渲染完成的一帧。配合 mplayer_video_buf_prepare() 分配后 memset(0),
 * "非黑像素占比 > 0" 即可证明 YUV_RGB_565 真的写出过 RGB565 像素, 而不是残留数据。
 *
 * GUI 构建下必须由真正的 display 组件提供该符号, 故 xmake 里只在 not use_gui 时编入。
 */

#include "luat_display.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define LUAT_LOG_TAG "mplayer.sink"
#include "luat_log.h"

/* 名义 sink 面板尺寸: 仅用于 set_rect(-1,-1) 的居中计算, 与真实 PC 窗口无关 */
#define PC_SINK_PANEL_W 800
#define PC_SINK_PANEL_H 480

/* 默认 BMP 落点(相对进程 cwd); 可用 LUAT_MPLAYER_SINK_BMP 覆盖 */
#define PC_SINK_BMP_DEFAULT "mplayer_sink_frame.bmp"

static struct luat_display_fb_info s_sink_fb_info;
static struct luat_display s_sink_display;

static int s_dump_done = 0;

static void sink_dump_frame(int width, int height, const uint16_t *px)
{
    if (width <= 0 || height <= 0 || px == NULL) {
        LLOGW("sink: skip frame dump (bad geometry %dx%d, buf=%p)", width, height, (const void *)px);
        return;
    }

    size_t count = (size_t)width * (size_t)height;
    size_t nonzero = 0;
    uint32_t sum = 0;
    uint32_t xorsum = 0;
    uint16_t min_v = 0xFFFF, max_v = 0;

    for (size_t i = 0; i < count; i++) {
        uint16_t v = px[i];
        if (v) nonzero++;
        sum += v;
        xorsum = (xorsum << 1) ^ (xorsum >> 31) ^ v;   /* 轻度混淆的滚动异或 */
        if (v < min_v) min_v = v;
        if (v > max_v) max_v = v;
    }

    LLOGI("sink: frame %dx%d nonzero=%zu/%zu (%zu%%) sum=0x%08X xorsum=0x%08X min=0x%04X max=0x%04X",
          width, height, nonzero, count, count ? (nonzero * 100 / count) : 0,
          sum, xorsum, min_v, max_v);
    LLOGI("sink: sample px[0]=0x%04X px[mid]=0x%04X px[last]=0x%04X",
          px[0], px[count / 2], px[count - 1]);

    const char *path = getenv("LUAT_MPLAYER_SINK_BMP");
    if (path == NULL || path[0] == 0) {
        path = PC_SINK_BMP_DEFAULT;
    }

    /* 24bit BMP: 自底向上, BGR 序, 行按 4 字节对齐 */
    uint32_t row_raw = (uint32_t)width * 3U;
    uint32_t row_pad = (row_raw + 3U) & ~3U;
    uint32_t pix_size = row_pad * (uint32_t)height;

    FILE *fp = fopen(path, "wb");
    if (fp == NULL) {
        LLOGW("sink: cannot open %s for BMP dump", path);
        return;
    }

    uint8_t file_hdr[14] = { 'B', 'M', 0 };
    uint32_t file_size = 14 + 40 + pix_size;
    memcpy(file_hdr + 2, &file_size, 4);
    uint32_t pix_off = 14 + 40;
    memcpy(file_hdr + 10, &pix_off, 4);
    fwrite(file_hdr, 1, sizeof(file_hdr), fp);

    uint8_t info_hdr[40] = { 0 };
    uint32_t bi_size = 40;
    int32_t bi_w = width;
    int32_t bi_h = height;
    uint16_t bi_planes = 1, bi_bpp = 24;
    memcpy(info_hdr + 0, &bi_size, 4);
    memcpy(info_hdr + 4, &bi_w, 4);
    memcpy(info_hdr + 8, &bi_h, 4);
    memcpy(info_hdr + 12, &bi_planes, 2);
    memcpy(info_hdr + 14, &bi_bpp, 2);
    memcpy(info_hdr + 20, &pix_size, 4);
    fwrite(info_hdr, 1, sizeof(info_hdr), fp);

    uint8_t *row = (uint8_t *)malloc(row_pad);
    if (row == NULL) {
        fclose(fp);
        return;
    }
    for (int y = height - 1; y >= 0; y--) {
        const uint16_t *src = px + (size_t)y * (size_t)width;
        for (int x = 0; x < width; x++) {
            uint16_t v = src[x];
            /* RGB565 -> 8bit: R5/G6/B5 各扩到 255 */
            row[x * 3 + 0] = (uint8_t)(((v & 0x1FU) * 255U) / 31U);          /* B */
            row[x * 3 + 1] = (uint8_t)((((v >> 5) & 0x3FU) * 255U) / 63U);  /* G */
            row[x * 3 + 2] = (uint8_t)((((v >> 11) & 0x1FU) * 255U) / 31U); /* R */
        }
        memset(row + row_raw, 0, row_pad - row_raw);
        fwrite(row, 1, row_pad, fp);
    }
    free(row);
    fclose(fp);

    LLOGI("sink: BMP written to %s (%ux%u)", path, (unsigned)width, (unsigned)height);
}

static int sink_set_layer(struct luat_display_layer_data *layer_data)
{
    if (layer_data == NULL) {
        return -1;
    }

    int w = (int)(layer_data->area.x2 - layer_data->area.x1);
    int h = (int)(layer_data->area.y2 - layer_data->area.y1);

    if (layer_data->enable) {
        LLOGI("sink: video layer ON id=%u fmt=%u %dx%d at (%d,%d) buf=%p",
              (unsigned)layer_data->layer_id, (unsigned)layer_data->format,
              w, h, (int)layer_data->area.x1, (int)layer_data->area.y1, layer_data->buffer);
        return 0;
    }

    /* 关层: buffer 仍是最后渲染完成的一帧, 做取证快照(只做一次) */
    if (!s_dump_done && layer_data->buffer != NULL) {
        s_dump_done = 1;
        sink_dump_frame(w, h, (const uint16_t *)layer_data->buffer);
    }
    else {
        LLOGI("sink: video layer OFF (buf=%p)", layer_data->buffer);
    }
    return 0;
}

static struct luat_display_funcs s_sink_funcs = {
    .name = "pc-headless-sink",
    .set_layer = sink_set_layer,
};

struct luat_display *luat_display_get_default(void)
{
    if (s_sink_display.display_funcs == NULL) {
        s_sink_fb_info.format = LUAT_DISPLAY_FORMAT_RGB565;
        s_sink_fb_info.bits_per_pixel = 16;
        s_sink_fb_info.stride = PC_SINK_PANEL_W * 2;
        s_sink_fb_info.width = PC_SINK_PANEL_W;
        s_sink_fb_info.height = PC_SINK_PANEL_H;

        memset(&s_sink_display, 0, sizeof(s_sink_display));
        snprintf(s_sink_display.name, sizeof(s_sink_display.name), "pc-headless-sink");
        s_sink_display.fb_info = &s_sink_fb_info;
        s_sink_display.display_funcs = &s_sink_funcs;
    }
    return &s_sink_display;
}
