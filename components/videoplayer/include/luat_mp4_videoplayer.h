#ifndef LUAT_MP4_VIDEOPLAYER_H
#define LUAT_MP4_VIDEOPLAYER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Return codes */
#define LUAT_MP4VP_OK   0
#define LUAT_MP4VP_ERR  (-1)
#define LUAT_MP4VP_EOF  (-2)

typedef struct luat_mp4_vctx_s luat_mp4_vctx_t;

/* Open an MP4 file for H.264 video playback. Returns NULL on failure. */
luat_mp4_vctx_t *luat_mp4_vctx_open(const char *path);

/* Close and free the MP4 context. */
void luat_mp4_vctx_close(luat_mp4_vctx_t *ctx);

/*
 * Decode the next video frame.
 * On success: returns LUAT_MP4VP_OK, *rgb_out points to an internal RGB565
 *             buffer, *w and *h are set to the frame dimensions.
 * The buffer is owned by ctx and valid until the next call or luat_mp4_vctx_close.
 * Returns LUAT_MP4VP_ERR on decode error, LUAT_MP4VP_EOF at end of stream.
 */
int luat_mp4_vctx_read_frame(luat_mp4_vctx_t *ctx,
                              uint16_t **rgb_out,
                              int *w, int *h);

/*
 * Decode the next video frame to a user-provided buffer.
 * On success: returns LUAT_MP4VP_OK, *w and *h are set to the frame dimensions.
 * The buffer is owned by the caller and valid until the next call or luat_mp4_vctx_close.
 * Returns LUAT_MP4VP_ERR on decode error, LUAT_MP4VP_EOF at end of stream.
 */
int luat_mp4_vctx_read_frame_to(luat_mp4_vctx_t *ctx,
                                uint16_t *rgb_buf,
                                int rgb_buf_pixels,
                                int *w, int *h);

/* Get video dimensions (0 if not yet decoded). */
void luat_mp4_vctx_get_dims(luat_mp4_vctx_t *ctx, int *w, int *h);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_MP4_VIDEOPLAYER_H */
