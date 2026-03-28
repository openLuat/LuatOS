/*
 * luat_videoplayer_mjpg_hw.c - MJPG hardware decoder (weak/stub)
 *
 * Default weak implementations that return LUAT_VP_ERR_NOIMPL.
 * Platform BSP can override these functions to provide actual
 * hardware JPEG decoding.
 */

#include "luat_videoplayer.h"

#ifdef __LUATOS__
#include "luat_base.h"
#include "luat_malloc.h"
#endif

/* Use project-wide LUAT_WEAK if available, else define per-compiler */
#ifndef LUAT_WEAK
#if defined(_MSC_VER) || (defined(_WIN32) && !defined(__GNUC__))
#define LUAT_WEAK
#elif defined(__GNUC__) || defined(__clang__)
#define LUAT_WEAK __attribute__((weak))
#else
#define LUAT_WEAK
#endif
#endif

/* EC718HM hardware decoder support */
#ifdef TYPE_EC718HM
#include "mm_jpeg_if.h"  

#define LUAT_LOG_TAG "videoplayer.hw.ec718hm"
#include "luat_log.h"

/* EC718HM hardware decoder context */
typedef struct {
    void *jpeg_decoder;         /* Hardware JPEG decoder handle */
    uint8_t *frame_buffer;      /* Frame output buffer */
    size_t buffer_size;         /* Buffer size */
    int initialized;            /* Initialization flag */
    uint32_t decode_count;      /* Decode frame count */
    uint32_t error_count;       /* Consecutive error count */
} ec718hm_hw_ctx_t;

/* Hardware decoder initialization for EC718HM */
static int luat_vp_mjpg_hw_init_ec718hm(void **ctx) {
    if (!ctx) {
        LLOGW("Invalid parameter: ctx is NULL");
        return LUAT_VP_ERR_PARAM;
    }
    
    ec718hm_hw_ctx_t *hw = (ec718hm_hw_ctx_t *)luat_heap_malloc(sizeof(ec718hm_hw_ctx_t));
    if (!hw) {
        LLOGW("Memory allocation failed: cannot allocate hardware decoder context");
        return LUAT_VP_ERR_NOMEM;
    }
    
    memset(hw, 0, sizeof(ec718hm_hw_ctx_t));
    
    /* Create hardware JPEG decoder */
    hw->jpeg_decoder = JpegD_Create();
    if (!hw->jpeg_decoder) {
        LLOGW("Hardware JPEG decoder creation failed");
        luat_heap_free(hw);
        return LUAT_VP_ERR_NOIMPL;
    }
    
    /* Pre-allocate output buffer (supports up to 720p) */
    hw->buffer_size = 1280 * 720 * 2;  // RGB565 format, 2 bytes per pixel
    hw->frame_buffer = (uint8_t *)luat_heap_malloc(hw->buffer_size);
    if (!hw->frame_buffer) {
        // If 720p buffer fails, try 480p
        hw->buffer_size = 640 * 480 * 2;
        hw->frame_buffer = (uint8_t *)luat_heap_malloc(hw->buffer_size);
        if (!hw->frame_buffer) {
            // If 480p buffer fails, try 240p
            hw->buffer_size = 320 * 240 * 2;
            hw->frame_buffer = (uint8_t *)luat_heap_malloc(hw->buffer_size);
            if (!hw->frame_buffer) {
                LLOGW("Output buffer allocation failed, size: %d", (int)hw->buffer_size);
                JpegD_Destroy(hw->jpeg_decoder);
                luat_heap_free(hw);
                return LUAT_VP_ERR_NOMEM;
            }
        }
    }
    
    hw->initialized = 1;
    *ctx = hw;
    
    LLOGD("EC718HM hardware JPEG decoder initialized successfully, buffer size: %d bytes", (int)hw->buffer_size);
    return LUAT_VP_OK;
}

/* Hardware JPEG decoding for EC718HM */
static int luat_vp_mjpg_hw_decode_ec718hm(void *ctx, const uint8_t *data, size_t size, 
                                           luat_vp_frame_t *frame) {
    if (!ctx || !data || size == 0 || !frame) {
        LLOGW("Invalid parameters: ctx=%p, data=%p, size=%d, frame=%p", 
               ctx, data, (int)size, frame);
        return LUAT_VP_ERR_PARAM;
    }
    
    ec718hm_hw_ctx_t *hw = (ec718hm_hw_ctx_t *)ctx;
    if (!hw->initialized || !hw->jpeg_decoder) {
        LLOGW("Hardware decoder not initialized or invalid");
        return LUAT_VP_ERR_PARAM;
    }
    
    /* Verify JPEG format */
    if (size < 2 || data[0] != 0xFF || data[1] != 0xD8) {
        LLOGW("Invalid JPEG format: header error");
        return LUAT_VP_ERR_FORMAT;
    }
    
    JPEG_INFO info;
    memset(&info, 0, sizeof(info));
    
    /* Get JPEG image info */
    int32_t res = JpegD_DecodeInfo(hw->jpeg_decoder, data, size, &info);
    if (res != 0) {
        LLOGW("JPEG info decode failed: %d", res);
        return LUAT_VP_ERR_DECODE;
    }
    
    /* Verify image size */
    uint32_t width = info.uWidth;
    uint32_t height = info.uHeight;
    if (width == 0 || height == 0) {
        LLOGW("Invalid image size: %dx%d", width, height);
        return LUAT_VP_ERR_DECODE;
    }
    
    /* Use edged width and height for buffer allocation */
    uint32_t edged_width = info.uEdgedWidth;
    uint32_t edged_height = info.uEdgedHeight;
    if (edged_width < width || edged_height < height) {
        LLOGW("Invalid edged size: %dx%d, using original size %dx%d", 
               edged_width, edged_height, width, height);
        edged_width = width;
        edged_height = height;
    }
    
    /* Check if buffer is sufficient, resize if needed */
    size_t required_size = edged_width * edged_height * 2;  // RGB565
    if (required_size > hw->buffer_size) {
        LLOGD("Resizing buffer: %d bytes -> %d bytes for %dx%d image (edged: %dx%d)", 
               (int)hw->buffer_size, (int)required_size, width, height, edged_width, edged_height);
        
        /* Allocate new buffer first */
        uint8_t *new_buffer = (uint8_t *)luat_heap_malloc(required_size);
        if (!new_buffer) {
            LLOGW("Output buffer allocation failed, size: %d", (int)required_size);
            return LUAT_VP_ERR_NOMEM;
        }
        
        /* Free old buffer and update pointer */
        if (hw->frame_buffer) {
            luat_heap_free(hw->frame_buffer);
        }
        hw->frame_buffer = new_buffer;
        hw->buffer_size = required_size;
        
        LLOGD("Buffer resized successfully to %d bytes", (int)hw->buffer_size);
    }
    
    /* Configure hardware decode output */
    JPEG_IMAGE_BUF ibuf;
    memset(&ibuf, 0, sizeof(ibuf));
    ibuf.eFmt = JPEG_COLOR_FMT_RGB565;
    ibuf.uWidth = width;
    ibuf.uHeight = height;
    ibuf.pData[0] = hw->frame_buffer;
    
    /* Execute hardware decoding */
    res = JpegD_DecodeImage(hw->jpeg_decoder, &ibuf);
    if (res != 0) {
        LLOGW("Hardware JPEG decode failed: res=%d, width=%u, height=%u, buffer_size=%zu", 
               res, width, height, hw->buffer_size);
        
        /* Increment error count */
        hw->error_count++;
        
        /* If consecutive errors exceed threshold, reinitialize decoder */
        if (hw->error_count >= 3) {
            LLOGW("Too many consecutive errors, reinitializing decoder");
            
            /* Destroy current decoder */
            if (hw->jpeg_decoder) {
                JpegD_Destroy(hw->jpeg_decoder);
                hw->jpeg_decoder = NULL;
            }
            
            /* Create new decoder */
            hw->jpeg_decoder = JpegD_Create();
            if (!hw->jpeg_decoder) {
                LLOGW("Failed to reinitialize decoder");
                return LUAT_VP_ERR_NOIMPL;
            }
            
            LLOGD("Decoder reinitialized successfully");
            hw->error_count = 0;
        }
        
        return LUAT_VP_ERR_DECODE;
    }
    
    /* Reset error count on success */
    hw->error_count = 0;
    
    /* Allocate output frame memory for actual image size */
    size_t actual_size = width * height * 2;
    uint8_t *frame_data = (uint8_t *)luat_heap_malloc(actual_size);
    if (!frame_data) {
        LLOGW("Frame data memory allocation failed: %d bytes", (int)actual_size);
        return LUAT_VP_ERR_NOMEM;
    }
    
    /* Copy only the actual image data (not the edged part) */
    memcpy(frame_data, hw->frame_buffer, actual_size);
    
    /* Set output frame info */
    frame->data = frame_data;
    frame->width = width;
    frame->height = height;
    
    hw->decode_count++;
    
    LLOGD("Hardware decode success: frame %d, size %dx%d, data size %d bytes (edged: %dx%d)", 
           hw->decode_count, width, height, (int)actual_size, edged_width, edged_height);
    
    return LUAT_VP_OK;
}

/* Release hardware decoder resources for EC718HM */
static void luat_vp_mjpg_hw_deinit_ec718hm(void *ctx) {
    if (!ctx) return;
    
    ec718hm_hw_ctx_t *hw = (ec718hm_hw_ctx_t *)ctx;
    
    LLOGD("Releasing EC718HM hardware decoder resources, decoded %d frames", hw->decode_count);
    
    if (hw->jpeg_decoder) {
        JpegD_Destroy(hw->jpeg_decoder);
        hw->jpeg_decoder = NULL;
    }
    
    if (hw->frame_buffer) {
        luat_heap_free(hw->frame_buffer);
        hw->frame_buffer = NULL;
    }
    
    luat_heap_free(hw);
}

/* Override weak functions for EC718HM platform */
int luat_vp_mjpg_hw_init(void **ctx) {
    return luat_vp_mjpg_hw_init_ec718hm(ctx);
}

int luat_vp_mjpg_hw_decode(void *ctx, const uint8_t *data, size_t size, 
                           luat_vp_frame_t *frame) {
    return luat_vp_mjpg_hw_decode_ec718hm(ctx, data, size, frame);
}

void luat_vp_mjpg_hw_deinit(void *ctx) {
    luat_vp_mjpg_hw_deinit_ec718hm(ctx);
}

#else

/*
 * Initialize hardware JPEG decoder.
 * Override this function in your BSP to set up hardware JPEG decode.
 */
LUAT_WEAK int luat_vp_mjpg_hw_init(void **ctx) {
    (void)ctx;
    return LUAT_VP_ERR_NOIMPL;
}

/*
 * Decode a JPEG frame using hardware decoder.
 * Override this function in your BSP to perform hardware JPEG decode.
 * The implementation should allocate frame->data with RGB565 pixel data.
 */
LUAT_WEAK int luat_vp_mjpg_hw_decode(void *ctx, const uint8_t *data,
                                      size_t size, luat_vp_frame_t *frame) {
    (void)ctx;
    (void)data;
    (void)size;
    (void)frame;
    return LUAT_VP_ERR_NOIMPL;
}

/*
 * Release hardware JPEG decoder resources.
 * Override this function in your BSP.
 */
LUAT_WEAK void luat_vp_mjpg_hw_deinit(void *ctx) {
    (void)ctx;
}

#endif /* TYPE_EC718HM */

/* Wrap weak functions into decoder ops */
static int hw_init_wrapper(void **ctx) {
    return luat_vp_mjpg_hw_init(ctx);
}

static int hw_decode_wrapper(void *ctx, const uint8_t *data, size_t size,
                              luat_vp_frame_t *frame) {
    return luat_vp_mjpg_hw_decode(ctx, data, size, frame);
}

static void hw_deinit_wrapper(void *ctx) {
    luat_vp_mjpg_hw_deinit(ctx);
}

const luat_vp_decoder_ops_t luat_vp_mjpg_hw_ops = {
    .init   = hw_init_wrapper,
    .decode = hw_decode_wrapper,
    .deinit = hw_deinit_wrapper,
};
