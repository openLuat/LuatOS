#ifndef LUAT_VIDEOPLAYER_H
#define LUAT_VIDEOPLAYER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Error codes ---- */
#define LUAT_VP_OK           0
#define LUAT_VP_ERR_PARAM   (-1)
#define LUAT_VP_ERR_NOMEM   (-2)
#define LUAT_VP_ERR_IO      (-3)
#define LUAT_VP_ERR_FORMAT  (-4)
#define LUAT_VP_ERR_EOF     (-5)
#define LUAT_VP_ERR_DECODE  (-6)
#define LUAT_VP_ERR_NOIMPL  (-7)

/* ---- Decode mode ---- */
typedef enum {
    LUAT_VP_DECODE_SW = 0,  /* Software decode (tjpgd) */
    LUAT_VP_DECODE_HW = 1,  /* Hardware decode (platform specific) */
} luat_vp_decode_mode_t;

/* ---- Video format ---- */
typedef enum {
    LUAT_VP_FMT_MJPG      = 0,  /* Raw MJPG stream */
    LUAT_VP_FMT_AVI_MJPG  = 1,  /* AVI container with MJPG (reserved) */
    LUAT_VP_FMT_MP4_H264  = 2,  /* MP4 container with H264 (reserved) */
} luat_vp_format_t;

/* ---- Decoded frame ---- */
typedef struct {
    uint8_t  *data;     /* RGB565 pixel data, row-major, 2 bytes per pixel */
    uint16_t  width;    /* Frame width in pixels */
    uint16_t  height;   /* Frame height in pixels */
} luat_vp_frame_t;

/* ---- Video information ---- */
typedef struct {
    uint16_t width;     /* Video width in pixels (0 if unknown before first frame) */
    uint16_t height;    /* Video height in pixels (0 if unknown before first frame) */
    luat_vp_format_t format;
    luat_vp_decode_mode_t decode_mode;
} luat_vp_info_t;

/* ---- Decoder operations interface ---- */
typedef struct luat_vp_decoder_ops {
    /**
     * Initialize decoder context.
     * @param ctx  Output: opaque decoder context pointer.
     * @return LUAT_VP_OK on success, negative error code otherwise.
     */
    int (*init)(void **ctx);

    /**
     * Decode a single JPEG frame from memory.
     * @param ctx   Decoder context from init().
     * @param data  Pointer to JPEG data.
     * @param size  Size of JPEG data in bytes.
     * @param frame Output: decoded frame (RGB565). Caller must free frame->data.
     * @return LUAT_VP_OK on success, negative error code otherwise.
     */
    int (*decode)(void *ctx, const uint8_t *data, size_t size,
                  luat_vp_frame_t *frame);

    /**
     * Release decoder context and all associated resources.
     * @param ctx  Decoder context from init().
     */
    void (*deinit)(void *ctx);
} luat_vp_decoder_ops_t;

typedef enum {
    LUAT_VP_PROF_T_DEMUX = 0,
    LUAT_VP_PROF_T_READ,
    LUAT_VP_PROF_T_ANNEXB,
    LUAT_VP_PROF_T_DECODE,
    LUAT_VP_PROF_T_YUV2RGB,
    LUAT_VP_PROF_T_COPY,
    LUAT_VP_PROF_T_DRAW,
    LUAT_VP_PROF_T_FLUSH,
    LUAT_VP_PROF_T_COUNT
} luat_vp_prof_stage_t;

/* ---- Player context (opaque) ---- */
typedef struct luat_vp_ctx luat_vp_ctx_t;

/* ---- Core API ---- */

/**
 * Open a video file for playback.
 * Currently supports raw MJPG streams (.mjpg).
 * @param path  File path (e.g. "/sdcard/video.mjpg").
 * @return Player context, or NULL on failure.
 */
luat_vp_ctx_t* luat_videoplayer_open(const char *path);

/**
 * Close the player and release all resources.
 * @param ctx  Player context from luat_videoplayer_open().
 */
void luat_videoplayer_close(luat_vp_ctx_t *ctx);

/**
 * Read and decode the next video frame.
 * The caller must call luat_videoplayer_frame_free() on the frame data
 * when done.
 * @param ctx   Player context.
 * @param frame Output: decoded frame (RGB565 data).
 * @return LUAT_VP_OK on success, LUAT_VP_ERR_EOF at end, negative on error.
 */
int luat_videoplayer_read_frame(luat_vp_ctx_t *ctx, luat_vp_frame_t *frame);

/**
 * Read and decode the next video frame, optionally borrowing backend-owned
 * frame memory to avoid an extra copy on direct draw paths.
 * @param ctx       Player context.
 * @param frame     Output: decoded frame.
 * @param borrowed  Output: 1 when frame->data is backend-owned and must not be
 *                  freed by the caller, 0 when caller owns frame->data and
 *                  should free it with luat_videoplayer_frame_free().
 * @return LUAT_VP_OK on success, LUAT_VP_ERR_EOF at end, negative on error.
 */
int luat_videoplayer_read_frame_ref(luat_vp_ctx_t *ctx, luat_vp_frame_t *frame, uint8_t *borrowed);

int luat_videoplayer_read_frame_to(luat_vp_ctx_t *ctx, luat_vp_frame_t *frame, uint8_t *out_buf, size_t out_buf_size);

/**
 * Free frame data allocated by luat_videoplayer_read_frame().
 * @param frame  Frame to free. frame->data is set to NULL after freeing.
 */
void luat_videoplayer_frame_free(luat_vp_frame_t *frame);

/**
 * Get video information.
 * @param ctx   Player context.
 * @param info  Output: video info structure.
 * @return LUAT_VP_OK on success.
 */
int luat_videoplayer_get_info(luat_vp_ctx_t *ctx, luat_vp_info_t *info);

/**
 * Set decode mode (software or hardware).
 * Can be called at any time during playback.
 * @param ctx   Player context.
 * @param mode  LUAT_VP_DECODE_SW or LUAT_VP_DECODE_HW.
 * @return LUAT_VP_OK on success.
 */
int luat_videoplayer_set_decode_mode(luat_vp_ctx_t *ctx,
                                     luat_vp_decode_mode_t mode);

/* ---- Debug ---- */

/**
 * Enable or disable debug output.
 * @param enable  1 to enable, 0 to disable.
 */
void luat_videoplayer_set_debug(int enable);

uint64_t luat_videoplayer_prof_now_ms(void);
void luat_videoplayer_prof_add_time(luat_vp_prof_stage_t stage, uint32_t elapsed_ms);
void luat_videoplayer_prof_mark_frame(void);

/* ---- Decoder backends (provided by src/) ---- */

/** Software MJPG decoder operations (tjpgd based) */
extern const luat_vp_decoder_ops_t luat_vp_mjpg_sw_ops;

/** Hardware MJPG decoder operations (weak, platform overridable) */
extern const luat_vp_decoder_ops_t luat_vp_mjpg_hw_ops;

/* ---- Hardware decode weak functions (for platform BSP to override) ---- */

int luat_vp_mjpg_hw_init(void **ctx);
int luat_vp_mjpg_hw_decode(void *ctx, const uint8_t *data, size_t size,
                            luat_vp_frame_t *frame);
void luat_vp_mjpg_hw_deinit(void *ctx);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_VIDEOPLAYER_H */
