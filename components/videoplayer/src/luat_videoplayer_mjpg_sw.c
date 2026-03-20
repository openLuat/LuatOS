/*
 * luat_videoplayer_mjpg_sw.c - MJPG software decoder using tjpgd
 *
 * Decodes individual JPEG frames to RGB565 using the TJpgDec library.
 */

#include "luat_videoplayer.h"

#ifdef LUAT_BUILD
#include "luat_base.h"
#include "luat_malloc.h"
#define VP_SW_MALLOC  luat_heap_malloc
#define VP_SW_FREE    luat_heap_free
#else
#include <stdlib.h>
#define VP_SW_MALLOC  malloc
#define VP_SW_FREE    free
#endif

#include "tjpgd.h"
#include <string.h>

/* Work buffer size for tjpgd */
#define TJPGD_WORK_SIZE  4096

/* Context for memory-based JPEG input */
typedef struct {
    const uint8_t *data;
    size_t size;
    size_t pos;
} mjpg_mem_input_t;

/* Context for output collection */
typedef struct {
    uint16_t *pixels;       /* Output RGB565 buffer */
    uint16_t width;
    uint16_t height;
} mjpg_output_ctx_t;

/* Software decoder context */
typedef struct {
    void *work_buf;         /* tjpgd work buffer */
} mjpg_sw_ctx_t;

/* tjpgd input function: read from memory buffer */
static size_t mjpg_sw_input_func(JDEC *jd, uint8_t *buff, size_t nbyte) {
    mjpg_mem_input_t *in = (mjpg_mem_input_t *)jd->device;
    size_t remain = in->size - in->pos;
    if (nbyte > remain) nbyte = remain;

    if (buff) {
        memcpy(buff, in->data + in->pos, nbyte);
    }
    in->pos += nbyte;
    return nbyte;
}

/* tjpgd output function: copy RGB565 pixels to output buffer */
static int mjpg_sw_output_func(JDEC *jd, void *bitmap, JRECT *rect) {
    mjpg_output_ctx_t *out = (mjpg_output_ctx_t *)jd->device;
    uint16_t *src = (uint16_t *)bitmap;
    uint16_t w = rect->right - rect->left + 1;
    uint16_t y;

    for (y = rect->top; y <= rect->bottom; y++) {
        if (y < out->height) {
            uint16_t copy_w = w;
            if (rect->left + copy_w > out->width) {
                copy_w = out->width - rect->left;
            }
            memcpy(&out->pixels[y * out->width + rect->left],
                   src, copy_w * sizeof(uint16_t));
        }
        src += w;
    }
    return 1;  /* Continue decompression */
}

/* ---- Decoder ops implementation ---- */

static int mjpg_sw_init(void **ctx) {
    mjpg_sw_ctx_t *sw = (mjpg_sw_ctx_t *)VP_SW_MALLOC(sizeof(mjpg_sw_ctx_t));
    if (!sw) return LUAT_VP_ERR_NOMEM;
    memset(sw, 0, sizeof(mjpg_sw_ctx_t));

    sw->work_buf = VP_SW_MALLOC(TJPGD_WORK_SIZE);
    if (!sw->work_buf) {
        VP_SW_FREE(sw);
        return LUAT_VP_ERR_NOMEM;
    }

    *ctx = sw;
    return LUAT_VP_OK;
}

static int mjpg_sw_decode(void *ctx, const uint8_t *data, size_t size,
                           luat_vp_frame_t *frame) {
    mjpg_sw_ctx_t *sw = (mjpg_sw_ctx_t *)ctx;
    if (!sw || !data || size == 0 || !frame) return LUAT_VP_ERR_PARAM;

    JDEC jdec;
    mjpg_mem_input_t input;
    input.data = data;
    input.size = size;
    input.pos = 0;

    /* Prepare JPEG decoder */
    JRESULT res = luat_jd_prepare(&jdec, mjpg_sw_input_func,
                                   sw->work_buf, TJPGD_WORK_SIZE, &input);
    if (res != JDR_OK) {
        return LUAT_VP_ERR_FORMAT;
    }

    uint16_t w = jdec.width;
    uint16_t h = jdec.height;

    /* Allocate output buffer (RGB565, 2 bytes per pixel) */
    size_t buf_size = (size_t)w * h * 2;
    uint16_t *pixels = (uint16_t *)VP_SW_MALLOC(buf_size);
    if (!pixels) {
        return LUAT_VP_ERR_NOMEM;
    }
    memset(pixels, 0, buf_size);

    /* Set up output context - we reuse the device pointer for output */
    mjpg_output_ctx_t out_ctx;
    out_ctx.pixels = pixels;
    out_ctx.width = w;
    out_ctx.height = h;

    /* Reset input position for decompression */
    input.pos = 0;

    /* Re-prepare with output context as device */
    res = luat_jd_prepare(&jdec, mjpg_sw_input_func,
                           sw->work_buf, TJPGD_WORK_SIZE, &input);
    if (res != JDR_OK) {
        VP_SW_FREE(pixels);
        return LUAT_VP_ERR_FORMAT;
    }

    /* Override device to point to output context for the output function */
    jdec.device = &out_ctx;

    /* Decompress */
    res = luat_jd_decomp(&jdec, mjpg_sw_output_func, 0);
    if (res != JDR_OK) {
        VP_SW_FREE(pixels);
        return LUAT_VP_ERR_DECODE;
    }

    frame->data = (uint8_t *)pixels;
    frame->width = w;
    frame->height = h;
    return LUAT_VP_OK;
}

static void mjpg_sw_deinit(void *ctx) {
    mjpg_sw_ctx_t *sw = (mjpg_sw_ctx_t *)ctx;
    if (!sw) return;

    if (sw->work_buf) {
        VP_SW_FREE(sw->work_buf);
    }
    VP_SW_FREE(sw);
}

const luat_vp_decoder_ops_t luat_vp_mjpg_sw_ops = {
    .init   = mjpg_sw_init,
    .decode = mjpg_sw_decode,
    .deinit = mjpg_sw_deinit,
};
