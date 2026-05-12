/*
 * luat_mp4_videoplayer.c
 *
 * PC-simulator MP4 video playback implementation.
 * Uses minimp4 for demuxing (via mp4_decode.c compiled symbols) and
 * h264_decode.c (AVCodec/FFmpeg bridge) for H.264 decoding.
 *
 * Only compiled when LUAT_USE_MP4PLAYER is defined.
 */
#include "luat_base.h"
#ifdef LUAT_USE_MP4PLAYER

#include "luat_mp4_videoplayer.h"
#include "luat_videoplayer.h"
/* minimp4 public API types — implementation symbols come from mp4_decode.c */
#include "mp4demux.h"
/* h264_decoder_init/deinit, h264_set_disp_callback, h264_decode_nal,
   yuv420p_to_rgb565_thumb */
#include "h264_decode.h"
/* ad_fopen, ad_fread, ad_fseek, ad_fclose, ad_fsize */
#include "plat_support.h"

#include <string.h>
#include <stdio.h>
#include <stdlib.h>  /* system malloc/free for large buffers (bypasses LuatOS heap limits) */

/* Large buffer helpers: use system malloc/free to avoid LuatOS 2MB heap limit.
   io_buf + annex_b_buf + rgb_buf can exceed 2.8MB for 1280x720 video. */
#define VP_SYS_MALLOC(sz)  malloc((sz))
#define VP_SYS_FREE(p)     free((p))

/* Maximum size of a single MP4 video sample (compressed AVCC data) */
#define MP4VP_NAL_BUF_SIZE  (512 * 1024)

/* Internal YUV frame snapshot captured from the decode callback.
   The pointers reference AVFrame memory valid until the next decode call. */
typedef struct {
    unsigned char *yuv[3];
    int linesize[3];
    int width;
    int height;
    int ready;
} mp4vp_yuv_frame_t;

struct luat_mp4_vctx_s {
    MP4D_demux_t    demux;
    ad_f_handle_t   file;
    unsigned        cur_frame;
    unsigned        total_frames;
    int             width;
    int             height;
    int             eof;
    uint8_t        *io_buf;           /* raw AVCC data read from MP4 */
    uint8_t        *annex_b_buf;      /* Annex B conversion buffer (io_buf + 4 bytes for start code) */
    mp4vp_yuv_frame_t yuv_frame;     /* last decoded YUV frame */
    uint16_t       *rgb_buf;         /* persistent RGB565 output buffer */
    int             rgb_buf_pixels;  /* allocated capacity in pixels */
};

/* Single-instance context pointer for the YUV decode callback */
static luat_mp4_vctx_t *g_mp4vp_ctx = NULL;

/* ---- minimp4 I/O callback ---- */
static int mp4vp_read_cb(int64_t offset, void *buf, size_t sz, void *token)
{
    ad_f_handle_t f = (ad_f_handle_t)token;
    ad_fseek(f, (uint32_t)offset);
    int n = ad_fread(f, buf, (uint32_t)sz);
    return n != (int)sz;  /* 0=success, nonzero=error */
}

/* ---- AVCodec YUV frame output callback ---- */
static void mp4vp_yuv_cb(unsigned char **yuv, int *linesize, int w, int h)
{
    luat_mp4_vctx_t *ctx = g_mp4vp_ctx;
    if (!ctx) return;
    /* Use container dims when decoder doesn't set frame dimensions */
    int use_w = w > 0 ? w : ctx->width;
    int use_h = h > 0 ? h : ctx->height;
    ctx->yuv_frame.yuv[0]      = yuv[0];
    ctx->yuv_frame.yuv[1]      = yuv[1];
    ctx->yuv_frame.yuv[2]      = yuv[2];
    ctx->yuv_frame.linesize[0] = linesize[0];
    ctx->yuv_frame.linesize[1] = linesize[1];
    ctx->yuv_frame.linesize[2] = linesize[2];
    ctx->yuv_frame.width       = use_w;
    ctx->yuv_frame.height      = use_h;
    ctx->yuv_frame.ready       = 1;
}

luat_mp4_vctx_t *luat_mp4_vctx_open(const char *path)
{
    if (!path) return NULL;

    ad_f_handle_t file = ad_fopen(path, AD_MODE_READ);
    if (!file) return NULL;

    luat_mp4_vctx_t *ctx = (luat_mp4_vctx_t *)VP_SYS_MALLOC(sizeof(luat_mp4_vctx_t));
    if (!ctx) { ad_fclose(file); return NULL; }
    memset(ctx, 0, sizeof(luat_mp4_vctx_t));
    ctx->file = file;

    ctx->io_buf = (uint8_t *)VP_SYS_MALLOC(MP4VP_NAL_BUF_SIZE);
    if (!ctx->io_buf) { luat_mp4_vctx_close(ctx); return NULL; }

    /* +4 bytes for the Annex B start code prepended during conversion */
    ctx->annex_b_buf = (uint8_t *)VP_SYS_MALLOC(MP4VP_NAL_BUF_SIZE + 4);
    if (!ctx->annex_b_buf) { luat_mp4_vctx_close(ctx); return NULL; }

    uint32_t fsize = ad_fsize(file);

    if (!MP4D_open(&ctx->demux, mp4vp_read_cb, file, (int64_t)fsize)) {
        luat_mp4_vctx_close(ctx);
        return NULL;
    }

    /* Locate the video track (track 0 by convention) */
    if (ctx->demux.track_count > 0 &&
        ctx->demux.track[0].handler_type == MP4D_HANDLER_TYPE_VIDE)
    {
        ctx->total_frames = ctx->demux.track[0].sample_count;
        /* Cache dimensions from the MP4 container header (always available) */
        ctx->width  = (int)ctx->demux.track[0].SampleDescription.video.width;
        ctx->height = (int)ctx->demux.track[0].SampleDescription.video.height;
    }

    if (ctx->total_frames == 0) {
        luat_mp4_vctx_close(ctx);
        return NULL;
    }

    /* Initialize the H.264 AVCodec decoder */
    if (h264_decoder_init() != 0) {
        luat_mp4_vctx_close(ctx);
        return NULL;
    }

    /* Register YUV frame capture callback */
    g_mp4vp_ctx = ctx;
    h264_set_disp_callback(mp4vp_yuv_cb);

    /* Feed SPS and PPS so the decoder knows the video parameters.
       MP4D_read_sps/pps returns raw NAL data without start code or length prefix. */
    {
        int nal_bytes = 0;
        const void *nal_data;
        int i;
        uint8_t start_code[4] = {0, 0, 0, 1};

        for (i = 0; (nal_data = MP4D_read_sps(&ctx->demux, 0, i, &nal_bytes)) != NULL; i++) {
            if (nal_bytes + 4 > MP4VP_NAL_BUF_SIZE + 4) continue;
            memcpy(ctx->annex_b_buf, start_code, 4);
            memcpy(ctx->annex_b_buf + 4, nal_data, nal_bytes);
            h264_decode_nal(ctx->annex_b_buf, nal_bytes + 4);
        }
        for (i = 0; (nal_data = MP4D_read_pps(&ctx->demux, 0, i, &nal_bytes)) != NULL; i++) {
            if (nal_bytes + 4 > MP4VP_NAL_BUF_SIZE + 4) continue;
            memcpy(ctx->annex_b_buf, start_code, 4);
            memcpy(ctx->annex_b_buf + 4, nal_data, nal_bytes);
            h264_decode_nal(ctx->annex_b_buf, nal_bytes + 4);
        }
    }

    return ctx;
}

void luat_mp4_vctx_close(luat_mp4_vctx_t *ctx)
{
    if (!ctx) return;

    if (g_mp4vp_ctx == ctx) {
        g_mp4vp_ctx = NULL;
        h264_set_disp_callback(NULL);
    }

    h264_deinit();
    MP4D_close(&ctx->demux);

    if (ctx->file)       { ad_fclose(ctx->file);          ctx->file       = NULL; }
    if (ctx->io_buf)     { VP_SYS_FREE(ctx->io_buf);      ctx->io_buf     = NULL; }
    if (ctx->annex_b_buf){ VP_SYS_FREE(ctx->annex_b_buf); ctx->annex_b_buf= NULL; }
    if (ctx->rgb_buf)    { VP_SYS_FREE(ctx->rgb_buf);     ctx->rgb_buf    = NULL; }

    VP_SYS_FREE(ctx);
}

int luat_mp4_vctx_read_frame(luat_mp4_vctx_t *ctx, uint16_t **rgb_out, int *w, int *h)
{
    if (!ctx || !rgb_out || !w || !h) return LUAT_MP4VP_ERR;
    if (ctx->eof) return LUAT_MP4VP_EOF;

    *rgb_out = NULL;
    *w = 0;
    *h = 0;
    ctx->yuv_frame.ready = 0;

    /* Consume MP4 samples until the H.264 decoder produces a frame.
       The decoder may buffer 1-2 samples before emitting the first frame. */
    while (!ctx->yuv_frame.ready) {
        uint64_t stage_start_ms;
        uint64_t stage_end_ms;
        if (ctx->cur_frame >= ctx->total_frames) {
            ctx->eof = 1;
            return LUAT_MP4VP_EOF;
        }

        stage_start_ms = luat_videoplayer_prof_now_ms();
        unsigned frame_bytes = 0;
        unsigned timestamp = 0, duration = 0;
        MP4D_file_offset_t ofs = MP4D_frame_offset(
            &ctx->demux, 0, ctx->cur_frame,
            &frame_bytes, &timestamp, &duration);
        stage_end_ms = luat_videoplayer_prof_now_ms();
        luat_videoplayer_prof_add_time(LUAT_VP_PROF_T_DEMUX, (uint32_t)(stage_end_ms - stage_start_ms));
        ctx->cur_frame++;

        if (frame_bytes == 0 || frame_bytes > MP4VP_NAL_BUF_SIZE) continue;

        /* Read raw AVCC data from file */
        stage_start_ms = luat_videoplayer_prof_now_ms();
        ad_fseek(ctx->file, (uint32_t)ofs);
        int n = ad_fread(ctx->file, ctx->io_buf, frame_bytes);
        stage_end_ms = luat_videoplayer_prof_now_ms();
        luat_videoplayer_prof_add_time(LUAT_VP_PROF_T_READ, (uint32_t)(stage_end_ms - stage_start_ms));
        if (n != (int)frame_bytes) continue;

        /* Convert each AVCC NAL unit to Annex B in-place:
           AVCC:   [4-byte big-endian length][NAL data]
           Annex B:[0x00 0x00 0x00 0x01     ][NAL data] */
        uint8_t *nal_ptr   = ctx->io_buf;
        uint8_t *out_ptr   = ctx->annex_b_buf;
        int      out_size  = 0;
        int      remaining = (int)frame_bytes;

        stage_start_ms = luat_videoplayer_prof_now_ms();
        while (remaining > 4) {
            uint32_t nal_size = ((uint32_t)nal_ptr[0] << 24) |
                                ((uint32_t)nal_ptr[1] << 16) |
                                ((uint32_t)nal_ptr[2] <<  8) |
                                 (uint32_t)nal_ptr[3];
            if (nal_size == 0 || (int)(nal_size + 4) > remaining) break;
            if (out_size + (int)(nal_size + 4) > MP4VP_NAL_BUF_SIZE + 4) break;

            out_ptr[0] = 0; out_ptr[1] = 0; out_ptr[2] = 0; out_ptr[3] = 1;
            memcpy(out_ptr + 4, nal_ptr + 4, nal_size);
            out_ptr   += (int)nal_size + 4;
            out_size  += (int)nal_size + 4;
            nal_ptr   += (int)nal_size + 4;
            remaining -= (int)nal_size + 4;
        }
        stage_end_ms = luat_videoplayer_prof_now_ms();
        luat_videoplayer_prof_add_time(LUAT_VP_PROF_T_ANNEXB, (uint32_t)(stage_end_ms - stage_start_ms));

        if (out_size > 0) {
            h264_decode_nal(ctx->annex_b_buf, out_size);
        }
    }

    /* A decoded frame is ready — convert YUV420p to RGB565 */
    int fw = ctx->yuv_frame.width;
    int fh = ctx->yuv_frame.height;
    /* Fall back to container dimensions if decoder didn't set frame dims */
    if (fw <= 0 || fh <= 0) {
        fw = ctx->width;
        fh = ctx->height;
    }
    if (fw <= 0 || fh <= 0) return LUAT_MP4VP_ERR;

    /* Re-allocate persistent RGB565 buffer if dimensions changed */
    if (ctx->rgb_buf_pixels < fw * fh) {
        if (ctx->rgb_buf) VP_SYS_FREE(ctx->rgb_buf);
        ctx->rgb_buf = (uint16_t *)VP_SYS_MALLOC((size_t)fw * fh * 2);
        if (!ctx->rgb_buf) { ctx->rgb_buf_pixels = 0; return LUAT_MP4VP_ERR; }
        ctx->rgb_buf_pixels = fw * fh;
    }

    uint64_t yuv2rgb_start_ms = luat_videoplayer_prof_now_ms();
    yuv420p_to_rgb565_thumb(
        ctx->yuv_frame.yuv[0],
        ctx->yuv_frame.yuv[1],
        ctx->yuv_frame.yuv[2],
        ctx->rgb_buf,
        fw, fh,
        ctx->yuv_frame.linesize[0],
        ctx->yuv_frame.linesize[1]);
    luat_videoplayer_prof_add_time(LUAT_VP_PROF_T_YUV2RGB, (uint32_t)(luat_videoplayer_prof_now_ms() - yuv2rgb_start_ms));

    ctx->width  = fw;
    ctx->height = fh;
    *rgb_out = ctx->rgb_buf;
    *w = fw;
    *h = fh;
    return LUAT_MP4VP_OK;
}

int luat_mp4_vctx_read_frame_to(luat_mp4_vctx_t *ctx, uint16_t *rgb_buf, int rgb_buf_pixels, int *w, int *h)
{
    if (!ctx || !rgb_buf || !w || !h) return LUAT_MP4VP_ERR;
    if (ctx->eof) return LUAT_MP4VP_EOF;

    *w = 0;
    *h = 0;
    ctx->yuv_frame.ready = 0;

    while (!ctx->yuv_frame.ready) {
        uint64_t stage_start_ms;
        uint64_t stage_end_ms;
        if (ctx->cur_frame >= ctx->total_frames) {
            ctx->eof = 1;
            return LUAT_MP4VP_EOF;
        }

        stage_start_ms = luat_videoplayer_prof_now_ms();
        unsigned frame_bytes = 0;
        unsigned timestamp = 0, duration = 0;
        MP4D_file_offset_t ofs = MP4D_frame_offset(
            &ctx->demux, 0, ctx->cur_frame,
            &frame_bytes, &timestamp, &duration);
        stage_end_ms = luat_videoplayer_prof_now_ms();
        luat_videoplayer_prof_add_time(LUAT_VP_PROF_T_DEMUX, (uint32_t)(stage_end_ms - stage_start_ms));
        ctx->cur_frame++;

        if (frame_bytes == 0 || frame_bytes > MP4VP_NAL_BUF_SIZE) continue;

        stage_start_ms = luat_videoplayer_prof_now_ms();
        ad_fseek(ctx->file, (uint32_t)ofs);
        int n = ad_fread(ctx->file, ctx->io_buf, frame_bytes);
        stage_end_ms = luat_videoplayer_prof_now_ms();
        luat_videoplayer_prof_add_time(LUAT_VP_PROF_T_READ, (uint32_t)(stage_end_ms - stage_start_ms));
        if (n != (int)frame_bytes) continue;

        uint8_t *nal_ptr = ctx->io_buf;
        uint8_t *out_ptr = ctx->annex_b_buf;
        int out_size = 0;
        int remaining = (int)frame_bytes;

        stage_start_ms = luat_videoplayer_prof_now_ms();
        while (remaining > 4) {
            uint32_t nal_size = ((uint32_t)nal_ptr[0] << 24) |
                                ((uint32_t)nal_ptr[1] << 16) |
                                ((uint32_t)nal_ptr[2] <<  8) |
                                 (uint32_t)nal_ptr[3];
            if (nal_size == 0 || (int)(nal_size + 4) > remaining) break;
            if (out_size + (int)(nal_size + 4) > MP4VP_NAL_BUF_SIZE + 4) break;

            out_ptr[0] = 0; out_ptr[1] = 0; out_ptr[2] = 0; out_ptr[3] = 1;
            memcpy(out_ptr + 4, nal_ptr + 4, nal_size);
            out_ptr += (int)nal_size + 4;
            out_size += (int)nal_size + 4;
            nal_ptr += (int)nal_size + 4;
            remaining -= (int)nal_size + 4;
        }
        stage_end_ms = luat_videoplayer_prof_now_ms();
        luat_videoplayer_prof_add_time(LUAT_VP_PROF_T_ANNEXB, (uint32_t)(stage_end_ms - stage_start_ms));

        if (out_size > 0) {
            h264_decode_nal(ctx->annex_b_buf, out_size);
        }
    }

    {
        int fw = ctx->yuv_frame.width;
        int fh = ctx->yuv_frame.height;
        uint64_t yuv2rgb_start_ms;

        if (fw <= 0 || fh <= 0) {
            fw = ctx->width;
            fh = ctx->height;
        }
        if (fw <= 0 || fh <= 0) return LUAT_MP4VP_ERR;
        if (rgb_buf_pixels < fw * fh) return LUAT_MP4VP_ERR;

        yuv2rgb_start_ms = luat_videoplayer_prof_now_ms();
        yuv420p_to_rgb565_thumb(
            ctx->yuv_frame.yuv[0],
            ctx->yuv_frame.yuv[1],
            ctx->yuv_frame.yuv[2],
            rgb_buf,
            fw, fh,
            ctx->yuv_frame.linesize[0],
            ctx->yuv_frame.linesize[1]);
        luat_videoplayer_prof_add_time(LUAT_VP_PROF_T_YUV2RGB, (uint32_t)(luat_videoplayer_prof_now_ms() - yuv2rgb_start_ms));

        ctx->width = fw;
        ctx->height = fh;
        *w = fw;
        *h = fh;
        return LUAT_MP4VP_OK;
    }
}

void luat_mp4_vctx_get_dims(luat_mp4_vctx_t *ctx, int *w, int *h)
{
    if (!ctx || !w || !h) return;
    *w = ctx->width;
    *h = ctx->height;
}

#endif /* LUAT_USE_MP4PLAYER */

uint64_t sys_get_time(void)
{
    return luat_mcu_tick64_ms();
}

uint64_t sys_get_time_elaps(uint64_t prev_tick)
{
    uint64_t tnow = luat_mcu_tick64_ms();
    return tnow - prev_tick;
}
