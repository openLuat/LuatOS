/*
 * luat_videoplayer_mjpg_sw.c - MJPG software decoder using tjpgd
 *
 * Decodes individual JPEG frames to RGB565 using the TJpgDec library.
 */

#include "luat_videoplayer.h"

#ifdef __LUATOS__
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

/* Combined context shared by both input and output callbacks via jd->device */
typedef struct {
    /* Input state */
    const uint8_t *in_data;
    size_t in_size;
    size_t in_pos;
    /* Output state (set after jd_prepare, before jd_decomp) */
    uint16_t *out_pixels;
    uint16_t out_width;
    uint16_t out_height;
} mjpg_sw_device_t;

/* Software decoder context */
typedef struct {
    void *work_buf;         /* tjpgd work buffer */
} mjpg_sw_ctx_t;

/* tjpgd input function: read from memory buffer */
static size_t mjpg_sw_input_func(JDEC *jd, uint8_t *buff, size_t nbyte) {
    mjpg_sw_device_t *dev = (mjpg_sw_device_t *)jd->device;
    size_t remain = dev->in_size - dev->in_pos;
    if (nbyte > remain) nbyte = remain;

    if (buff) {
        memcpy(buff, dev->in_data + dev->in_pos, nbyte);
    }
    dev->in_pos += nbyte;
    return nbyte;
}

/* tjpgd output function: copy RGB565 pixels to output buffer */
static int mjpg_sw_output_func(JDEC *jd, void *bitmap, JRECT *rect) {
    mjpg_sw_device_t *dev = (mjpg_sw_device_t *)jd->device;
    if (!dev || !dev->out_pixels || !bitmap) return 0;

    uint16_t *src = (uint16_t *)bitmap;
    if (rect->right < rect->left || rect->bottom < rect->top) return 1;
    uint16_t w = rect->right - rect->left + 1;
    uint16_t y;

    for (y = rect->top; y <= rect->bottom; y++) {
        if (y < dev->out_height && rect->left < dev->out_width) {
            uint16_t copy_w = w;
            if (rect->left + copy_w > dev->out_width) {
                copy_w = dev->out_width - rect->left;
            }
            memcpy(&dev->out_pixels[y * dev->out_width + rect->left],
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
    mjpg_sw_device_t dev;
    memset(&dev, 0, sizeof(dev));
    dev.in_data = data;
    dev.in_size = size;
    dev.in_pos = 0;

    /* Prepare JPEG decoder - both input and output callbacks read from dev */
    JRESULT res = luat_jd_prepare(&jdec, mjpg_sw_input_func,
                                   sw->work_buf, TJPGD_WORK_SIZE, &dev);
    if (res != JDR_OK) {
        return LUAT_VP_ERR_FORMAT;
    }

    uint16_t w = jdec.width;
    uint16_t h = jdec.height;

    /* Validate dimensions and check for integer overflow (RGB565, 2 bytes/pixel) */
    if (w == 0 || h == 0) {
        return LUAT_VP_ERR_FORMAT;
    }
    size_t pixel_count = (size_t)w * h;
    if (pixel_count / w != (size_t)h) {
        return LUAT_VP_ERR_NOMEM;  /* overflow */
    }
    size_t buf_size = pixel_count * 2;
    if (buf_size / 2 != pixel_count) {
        return LUAT_VP_ERR_NOMEM;  /* overflow */
    }
    uint16_t *pixels = (uint16_t *)VP_SW_MALLOC(buf_size);
    if (!pixels) {
        return LUAT_VP_ERR_NOMEM;
    }
    memset(pixels, 0, buf_size);

    /* Set up output fields in the shared device context */
    dev.out_pixels = pixels;
    dev.out_width = w;
    dev.out_height = h;

    /* Decompress - input callback continues reading via dev.in_* fields */
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
