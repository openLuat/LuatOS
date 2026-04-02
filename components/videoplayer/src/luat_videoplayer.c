/*
 * luat_videoplayer.c - Video player core implementation
 *
 * Handles MJPG stream parsing and decoder dispatching.
 */

#include "luat_videoplayer.h"

#ifdef __LUATOS__
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_fs.h"
#define VP_MALLOC  luat_heap_malloc
#define VP_FREE    luat_heap_free
#define VP_FOPEN   luat_fs_fopen
#define VP_FCLOSE  luat_fs_fclose
#define VP_FREAD   luat_fs_fread
#define VP_FSEEK   luat_fs_fseek
#define VP_FTELL   luat_fs_ftell
#else
#include <stdio.h>
#include <stdlib.h>
#define VP_MALLOC  malloc
#define VP_FREE    free
#define VP_FOPEN   fopen
#define VP_FCLOSE  fclose
#define VP_FREAD   fread
#define VP_FSEEK   fseek
#define VP_FTELL   ftell
#endif

#include <string.h>

/* Read buffer size for scanning MJPG stream */
#define VP_READ_BUF_SIZE  (32 * 1024)

/* Maximum single JPEG frame size (2 MB) */
#define VP_MAX_FRAME_SIZE (2 * 1024 * 1024)

/* JPEG markers */
#define JPEG_SOI_0  0xFF
#define JPEG_SOI_1  0xD8
#define JPEG_EOI_1  0xD9

/* Debug flag */
static int g_vp_debug = 0;

#ifdef __LUATOS__
#define LUAT_LOG_TAG "videoplayer"
#include "luat_log.h"
#define VP_LOGD(...) do { if (g_vp_debug) LLOGD(__VA_ARGS__); } while(0)
#define VP_LOGW(...) LLOGW(__VA_ARGS__)
#else
#include <stdio.h>
#define VP_LOGD(...) do { if (g_vp_debug) { printf("[VP] "); printf(__VA_ARGS__); printf("\n"); } } while(0)
#define VP_LOGW(...) do { printf("[VP WARN] "); printf(__VA_ARGS__); printf("\n"); } while(0)
#endif

/* ---- Player context ---- */
struct luat_vp_ctx {
    void *fp;                           /* File pointer */
    luat_vp_format_t format;
    luat_vp_decode_mode_t decode_mode;
    const luat_vp_decoder_ops_t *decoder_ops;
    void *decoder_ctx;
    uint16_t width;
    uint16_t height;
    uint8_t *read_buf;                  /* Buffer for reading JPEG frames */
    size_t read_buf_cap;                /* Capacity of read_buf */
    int eof;
};

/* ---- Internal: detect format from file extension ---- */
static luat_vp_format_t detect_format(const char *path) {
    if (!path) return LUAT_VP_FMT_MJPG;
    size_t len = strlen(path);
    if (len >= 5) {
        const char *ext = path + len - 5;
        if (strcmp(ext, ".mjpg") == 0 || strcmp(ext, ".MJPG") == 0)
            return LUAT_VP_FMT_MJPG;
    }
    if (len >= 4) {
        const char *ext = path + len - 4;
        if (strcmp(ext, ".avi") == 0 || strcmp(ext, ".AVI") == 0)
            return LUAT_VP_FMT_AVI_MJPG;
        if (strcmp(ext, ".mp4") == 0 || strcmp(ext, ".MP4") == 0)
            return LUAT_VP_FMT_MP4_H264;
        if (strcmp(ext, ".jpg") == 0 || strcmp(ext, ".JPG") == 0)
            return LUAT_VP_FMT_MJPG;
    }
    return LUAT_VP_FMT_MJPG;  /* Default to MJPG */
}

/* ---- Internal: initialize decoder for current mode ---- */
static int init_decoder(luat_vp_ctx_t *ctx) {
    if (ctx->decoder_ctx) {
        /* Deinit previous decoder */
        if (ctx->decoder_ops && ctx->decoder_ops->deinit) {
            ctx->decoder_ops->deinit(ctx->decoder_ctx);
        }
        ctx->decoder_ctx = NULL;
    }

    const luat_vp_decoder_ops_t *ops = NULL;
    if (ctx->decode_mode == LUAT_VP_DECODE_HW) {
        ops = &luat_vp_mjpg_hw_ops;
    } else {
        ops = &luat_vp_mjpg_sw_ops;
    }

    ctx->decoder_ops = ops;
    int ret = ops->init(&ctx->decoder_ctx);
    if (ret != LUAT_VP_OK) {
        /* If hardware decode is unavailable, fall back to software decode */
        if (ctx->decode_mode == LUAT_VP_DECODE_HW) {
            VP_LOGW("HW decoder init failed (%d), falling back to SW", ret);
            ops = &luat_vp_mjpg_sw_ops;
            ctx->decoder_ops = ops;
            ctx->decode_mode = LUAT_VP_DECODE_SW;
            ret = ops->init(&ctx->decoder_ctx);
            if (ret != LUAT_VP_OK) {
                VP_LOGW("SW decoder init also failed: %d", ret);
                return ret;
            }
        } else {
            VP_LOGW("decoder init failed: %d", ret);
            return ret;
        }
    }

    VP_LOGD("decoder initialized, mode=%s",
            ctx->decode_mode == LUAT_VP_DECODE_HW ? "HW" : "SW");
    return LUAT_VP_OK;
}

/* Scan buffer size for buffered marker search */
#define VP_SCAN_BUF_SIZE  512

/* Helper: ensure frame buffer has room for at least one more byte */
static int ensure_frame_buf(luat_vp_ctx_t *ctx, size_t frame_size) {
    if (frame_size < ctx->read_buf_cap) return LUAT_VP_OK;
    if (frame_size >= VP_MAX_FRAME_SIZE) {
        VP_LOGW("frame too large (%d bytes), skipping", (int)frame_size);
        return LUAT_VP_ERR_FORMAT;
    }
    size_t new_cap = ctx->read_buf_cap * 2;
    if (new_cap > VP_MAX_FRAME_SIZE) new_cap = VP_MAX_FRAME_SIZE;
    uint8_t *new_buf = (uint8_t *)VP_MALLOC(new_cap);
    if (!new_buf) return LUAT_VP_ERR_NOMEM;
    memcpy(new_buf, ctx->read_buf, frame_size);
    VP_FREE(ctx->read_buf);
    ctx->read_buf = new_buf;
    ctx->read_buf_cap = new_cap;
    return LUAT_VP_OK;
}

/* ---- Internal: read next JPEG frame from MJPG stream ---- */
static int read_next_mjpg_frame(luat_vp_ctx_t *ctx,
                                 uint8_t **out_data, size_t *out_size) {
    if (ctx->eof) return LUAT_VP_ERR_EOF;

    /* Scan for SOI marker (0xFF 0xD8) using buffered reads */
    int found_soi = 0;
    int prev_byte = -1;
    int c, ret;
    uint8_t scan_buf[VP_SCAN_BUF_SIZE];
    size_t bytes_in_buf = 0;
    size_t scan_pos = 0;

    while (!found_soi) {
        if (scan_pos >= bytes_in_buf) {
            bytes_in_buf = VP_FREAD(scan_buf, 1, sizeof(scan_buf), ctx->fp);
            if (bytes_in_buf == 0) {
                ctx->eof = 1;
                return LUAT_VP_ERR_EOF;
            }
            scan_pos = 0;
        }
        c = scan_buf[scan_pos++];
        if (prev_byte == JPEG_SOI_0 && c == JPEG_SOI_1) {
            found_soi = 1;
        }
        prev_byte = c;
    }

    /* Start collecting JPEG data from SOI */
    size_t frame_size = 2;  /* SOI already found */
    if (frame_size > ctx->read_buf_cap) {
        return LUAT_VP_ERR_NOMEM;
    }
    ctx->read_buf[0] = JPEG_SOI_0;
    ctx->read_buf[1] = JPEG_SOI_1;

    /* Copy any remaining bytes from the SOI scan buffer into the frame */
    int found_eoi = 0;
    while (scan_pos < bytes_in_buf && !found_eoi) {
        c = scan_buf[scan_pos++];
        ret = ensure_frame_buf(ctx, frame_size);
        if (ret != LUAT_VP_OK) return ret;
        ctx->read_buf[frame_size++] = (uint8_t)c;
        if (prev_byte == JPEG_SOI_0 && c == JPEG_EOI_1) {
            found_eoi = 1;
        }
        prev_byte = c;
    }

    /* Read until EOI marker (0xFF 0xD9) using buffered reads */
    while (!found_eoi) {
        bytes_in_buf = VP_FREAD(scan_buf, 1, sizeof(scan_buf), ctx->fp);
        if (bytes_in_buf == 0) {
            /* Unexpected EOF inside a frame */
            ctx->eof = 1;
            if (frame_size > 2) {
                /* Return partial frame - decoder will handle error */
                break;
            }
            return LUAT_VP_ERR_EOF;
        }

        for (scan_pos = 0; scan_pos < bytes_in_buf && !found_eoi; scan_pos++) {
            c = scan_buf[scan_pos];
            ret = ensure_frame_buf(ctx, frame_size);
            if (ret != LUAT_VP_OK) return ret;
            ctx->read_buf[frame_size++] = (uint8_t)c;
            if (prev_byte == JPEG_SOI_0 && c == JPEG_EOI_1) {
                found_eoi = 1;
            }
            prev_byte = c;
        }
    }

    VP_LOGD("MJPG frame: %d bytes", (int)frame_size);
    *out_data = ctx->read_buf;
    *out_size = frame_size;
    return LUAT_VP_OK;
}

/* ---- Public API ---- */

luat_vp_ctx_t* luat_videoplayer_open(const char *path) {
    if (!path) return NULL;

    luat_vp_format_t fmt = detect_format(path);

    /* Currently only MJPG is supported */
    if (fmt != LUAT_VP_FMT_MJPG) {
        VP_LOGW("unsupported format for: %s", path);
        return NULL;
    }

    void *fp = VP_FOPEN(path, "rb");
    if (!fp) {
        VP_LOGW("failed to open: %s", path);
        return NULL;
    }

    luat_vp_ctx_t *ctx = (luat_vp_ctx_t *)VP_MALLOC(sizeof(luat_vp_ctx_t));
    if (!ctx) {
        VP_FCLOSE(fp);
        return NULL;
    }
    memset(ctx, 0, sizeof(luat_vp_ctx_t));

    ctx->fp = fp;
    ctx->format = fmt;
    ctx->decode_mode = LUAT_VP_DECODE_SW;  /* Default to software decode */
    ctx->eof = 0;

    /* Allocate read buffer */
    ctx->read_buf = (uint8_t *)VP_MALLOC(VP_READ_BUF_SIZE);
    if (!ctx->read_buf) {
        VP_FCLOSE(fp);
        VP_FREE(ctx);
        return NULL;
    }
    ctx->read_buf_cap = VP_READ_BUF_SIZE;

    /* Initialize decoder */
    if (init_decoder(ctx) != LUAT_VP_OK) {
        VP_FREE(ctx->read_buf);
        VP_FCLOSE(fp);
        VP_FREE(ctx);
        return NULL;
    }

    VP_LOGD("opened %s, format=%d", path, (int)fmt);
    return ctx;
}

void luat_videoplayer_close(luat_vp_ctx_t *ctx) {
    if (!ctx) return;

    if (ctx->decoder_ops && ctx->decoder_ctx) {
        ctx->decoder_ops->deinit(ctx->decoder_ctx);
        ctx->decoder_ctx = NULL;
    }

    if (ctx->fp) {
        VP_FCLOSE(ctx->fp);
        ctx->fp = NULL;
    }

    if (ctx->read_buf) {
        VP_FREE(ctx->read_buf);
        ctx->read_buf = NULL;
    }

    VP_FREE(ctx);
}

int luat_videoplayer_read_frame(luat_vp_ctx_t *ctx, luat_vp_frame_t *frame) {
    if (!ctx || !frame) return LUAT_VP_ERR_PARAM;

    memset(frame, 0, sizeof(luat_vp_frame_t));

    if (ctx->format == LUAT_VP_FMT_MJPG) {
        uint8_t *jpeg_data = NULL;
        size_t jpeg_size = 0;

        int ret = read_next_mjpg_frame(ctx, &jpeg_data, &jpeg_size);
        if (ret != LUAT_VP_OK) return ret;

        if (!ctx->decoder_ops || !ctx->decoder_ops->decode) {
            return LUAT_VP_ERR_NOIMPL;
        }

        ret = ctx->decoder_ops->decode(ctx->decoder_ctx,
                                        jpeg_data, jpeg_size, frame);
        if (ret != LUAT_VP_OK) {
            VP_LOGW("decode failed: %d", ret);
            return ret;
        }

        /* Update video dimensions from first decoded frame */
        if (ctx->width == 0 && frame->width > 0) {
            ctx->width = frame->width;
            ctx->height = frame->height;
            VP_LOGD("video size: %dx%d", ctx->width, ctx->height);
        }

        return LUAT_VP_OK;
    }

    return LUAT_VP_ERR_FORMAT;
}

void luat_videoplayer_frame_free(luat_vp_frame_t *frame) {
    if (frame && frame->data) {
        VP_FREE(frame->data);
        frame->data = NULL;
    }
}

int luat_videoplayer_get_info(luat_vp_ctx_t *ctx, luat_vp_info_t *info) {
    if (!ctx || !info) return LUAT_VP_ERR_PARAM;

    /* If dimensions are unknown, try to decode first frame to get them */
    if (ctx->width == 0 && ctx->format == LUAT_VP_FMT_MJPG) {
        /* Save current file position */
        long file_pos = VP_FTELL(ctx->fp);
        if (file_pos != -1) {
            luat_vp_frame_t frame;
            int ret = luat_videoplayer_read_frame(ctx, &frame);
            if (ret == LUAT_VP_OK) {
                ctx->width = frame.width;
                ctx->height = frame.height;
                luat_videoplayer_frame_free(&frame);
                VP_LOGD("video size: %dx%d", ctx->width, ctx->height);
            }
            
            /* Reset file position to original */
            VP_FSEEK(ctx->fp, file_pos, SEEK_SET);
            ctx->eof = 0;  /* Reset EOF flag */
        }
    }

    info->width = ctx->width;
    info->height = ctx->height;
    info->format = ctx->format;
    info->decode_mode = ctx->decode_mode;
    return LUAT_VP_OK;
}

int luat_videoplayer_set_decode_mode(luat_vp_ctx_t *ctx,
                                     luat_vp_decode_mode_t mode) {
    if (!ctx) return LUAT_VP_ERR_PARAM;
    if (mode != LUAT_VP_DECODE_SW && mode != LUAT_VP_DECODE_HW)
        return LUAT_VP_ERR_PARAM;

    if (ctx->decode_mode == mode) return LUAT_VP_OK;

    ctx->decode_mode = mode;
    return init_decoder(ctx);
}

void luat_videoplayer_set_debug(int enable) {
    g_vp_debug = enable ? 1 : 0;
}
