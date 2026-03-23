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
