#ifndef LUAT_AIRUI_REMOTE_H
#define LUAT_AIRUI_REMOTE_H

#include "luat_airui.h"

#if defined(LUAT_USE_AIRUI_REMOTE)

typedef struct {
    const uint8_t *pixels;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t sequence;
} airui_remote_frame_t;

/* The view is borrowed for the duration of the current UI call. */
int airui_remote_framebuffer(airui_ctx_t *ctx, airui_remote_frame_t *frame);
void luat_airui_remote_sync_fb(const void *address, size_t len);

typedef struct {
    uint32_t frame_id;
    uint32_t width;
    uint32_t height;
    size_t len;
    uint32_t screen_width;
    uint32_t screen_height;
} airui_remote_capture_info_t;

typedef enum {
    AIRUI_REMOTE_POINTER_DOWN = 1,
    AIRUI_REMOTE_POINTER_MOVE,
    AIRUI_REMOTE_POINTER_UP,
    AIRUI_REMOTE_POINTER_CANCEL,
} airui_remote_pointer_kind_t;

int airui_remote_start(airui_ctx_t *ctx);
void airui_remote_stop(airui_ctx_t *ctx);
int airui_remote_capture(airui_ctx_t *ctx, uint32_t scale, uint32_t previous,
                         airui_remote_capture_info_t *info);
/* Copy the borrowed bytes before the next capture, timer callback, or stop. */
int airui_remote_read(airui_ctx_t *ctx, uint32_t frame_id, size_t offset, size_t len,
                    const uint8_t **data);
int airui_remote_pointer(airui_ctx_t *ctx, airui_remote_pointer_kind_t kind, int32_t x, int32_t y);
void airui_remote_cancel_pointer(airui_ctx_t *ctx);

#endif /* LUAT_USE_AIRUI_REMOTE */

#endif /* LUAT_AIRUI_REMOTE_H */
