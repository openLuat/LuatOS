#include "luat_airui_remote.h"

#if defined(LUAT_USE_AIRUI_REMOTE)

#include "luat_mem.h"
#include <string.h>

#define REMOTE_POINTER_QUEUE 16
#define REMOTE_POINTER_TIMEOUT_MS 1500
#define REMOTE_FRAME_TIMEOUT_MS 8000
#define REMOTE_READ_LIMIT 4000

typedef struct {
    lv_point_t point;
    bool pressed;
    uint8_t kind;
} remote_sample_t;

struct airui_remote {
    lv_indev_t *pointer;
    lv_timer_t *timer;
    lv_point_t point;
    remote_sample_t samples[REMOTE_POINTER_QUEUE];
    uint8_t head;
    uint8_t count;
    bool pressed;
    bool held;
    uint32_t input_tick;
    uint8_t *pixels;
    size_t len;
    uint32_t frame_id;
    uint32_t frame_tick;
};

static void release_frame(struct airui_remote *remote)
{
    if (remote->pixels != NULL) {
        luat_heap_free(remote->pixels);
        remote->pixels = NULL;
    }
    remote->len = 0;
}

void airui_remote_cancel_pointer(airui_ctx_t *ctx)
{
    struct airui_remote *remote = ctx != NULL ? ctx->remote : NULL;
    if (remote == NULL || (!remote->held && !remote->pressed && !remote->count)) {
        return;
    }
    remote->count = 0;
    remote->pressed = false;
    remote->held = false;
    /* A cancelled press must not be delivered as a click. */
    lv_indev_reset(remote->pointer, NULL);
}

static void read_pointer(lv_indev_t *indev, lv_indev_data_t *data)
{
    airui_ctx_t *ctx = lv_indev_get_user_data(indev);
    struct airui_remote *remote = ctx->remote;
    if (remote->count != 0) {
        const remote_sample_t *sample = &remote->samples[remote->head];
        remote->point = sample->point;
        remote->pressed = sample->pressed;
        remote->head = (remote->head + 1) % REMOTE_POINTER_QUEUE;
        remote->count--;
    }
    data->point = remote->point;
    data->state = remote->pressed ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    data->continue_reading = remote->count != 0;
}

static void expire_remote_state(lv_timer_t *timer)
{
    airui_ctx_t *ctx = lv_timer_get_user_data(timer);
    struct airui_remote *remote = ctx->remote;
    if ((remote->held || remote->pressed) &&
        (airui_is_sleeping(ctx) || lv_tick_elaps(remote->input_tick) >= REMOTE_POINTER_TIMEOUT_MS)) {
        airui_remote_cancel_pointer(ctx);
    }
    if (remote->pixels != NULL && lv_tick_elaps(remote->frame_tick) >= REMOTE_FRAME_TIMEOUT_MS) {
        release_frame(remote);
    }
}

void airui_remote_stop(airui_ctx_t *ctx)
{
    struct airui_remote *remote = ctx != NULL ? ctx->remote : NULL;
    if (remote == NULL) {
        return;
    }
    if (remote->timer != NULL) {
        lv_timer_delete(remote->timer);
    }
    if (remote->pointer != NULL) {
        airui_remote_cancel_pointer(ctx);
        lv_indev_delete(remote->pointer);
    }
    release_frame(remote);
    ctx->remote = NULL;
    luat_heap_free(remote);
}

int airui_remote_start(airui_ctx_t *ctx)
{
    if (ctx == NULL || ctx->display == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    if (ctx->remote == NULL) {
        struct airui_remote *remote = luat_heap_zalloc(sizeof(*remote));
        if (remote == NULL) {
            return AIRUI_ERR_NO_MEM;
        }
        ctx->remote = remote;
        remote->pointer = lv_indev_create();
        remote->timer = lv_timer_create(expire_remote_state, 250, ctx);
        if (remote->pointer == NULL || remote->timer == NULL) {
            airui_remote_stop(ctx);
            return AIRUI_ERR_NO_MEM;
        }
        lv_indev_set_type(remote->pointer, LV_INDEV_TYPE_POINTER);
        lv_indev_set_display(remote->pointer, ctx->display);
        lv_indev_set_user_data(remote->pointer, ctx);
        lv_indev_set_read_cb(remote->pointer, read_pointer);
    }
    return AIRUI_OK;
}

int airui_remote_capture(airui_ctx_t *ctx, uint32_t scale, uint32_t previous,
                         airui_remote_capture_info_t *info)
{
    airui_remote_frame_t frame;
    if (ctx == NULL || ctx->remote == NULL || airui_is_sleeping(ctx)) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    if ((scale != 1 && scale != 2 && scale != 4) || info == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    int ret = airui_remote_framebuffer(ctx, &frame);
    if (ret != AIRUI_OK) {
        return ret;
    }
    uint32_t width = (frame.width + scale - 1) / scale;
    uint32_t height = (frame.height + scale - 1) / scale;
    size_t len = width * height * sizeof(uint16_t);
    struct airui_remote *remote = ctx->remote;
    if (frame.sequence == previous) {
        len = 0;
    } else {
        if (remote->pixels == NULL || remote->len != len) {
            release_frame(remote);
            remote->pixels = luat_heap_malloc(len);
            if (remote->pixels == NULL) {
                return AIRUI_ERR_NO_MEM;
            }
        }
        luat_airui_remote_sync_fb(frame.pixels, (size_t)frame.stride * frame.height);
        uint16_t *dest = (uint16_t *)remote->pixels;
        for (uint32_t y = 0; y < height; y++) {
            const uint16_t *row = (const uint16_t *)(frame.pixels + y * scale * frame.stride);
            if (scale == 1) {
                memcpy(dest, row, width * sizeof(uint16_t));
                dest += width;
            } else {
                for (uint32_t x = 0; x < width; x++) {
                    *dest++ = row[x * scale];
                }
            }
        }
        remote->len = len;
        remote->frame_id = frame.sequence;
        remote->frame_tick = lv_tick_get();
    }
    *info = (airui_remote_capture_info_t) {
        .frame_id = frame.sequence,
        .width = width,
        .height = height,
        .len = len,
        .screen_width = frame.width,
        .screen_height = frame.height,
    };
    return AIRUI_OK;
}

int airui_remote_read(airui_ctx_t *ctx, uint32_t frame_id, size_t offset, size_t len,
                    const uint8_t **data)
{
    struct airui_remote *remote = ctx != NULL ? ctx->remote : NULL;
    if (remote == NULL || remote->pixels == NULL || frame_id != remote->frame_id ||
        data == NULL || len == 0 || len > REMOTE_READ_LIMIT ||
        offset > remote->len || len > remote->len - offset) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    remote->frame_tick = lv_tick_get();
    *data = remote->pixels + offset;
    return AIRUI_OK;
}

int airui_remote_pointer(airui_ctx_t *ctx, airui_remote_pointer_kind_t kind, int32_t x, int32_t y)
{
    struct airui_remote *remote = ctx != NULL ? ctx->remote : NULL;
    if (remote == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    if (kind == AIRUI_REMOTE_POINTER_CANCEL) {
        airui_remote_cancel_pointer(ctx);
        return AIRUI_OK;
    }
    if (airui_is_sleeping(ctx) || kind < AIRUI_REMOTE_POINTER_DOWN || kind > AIRUI_REMOTE_POINTER_UP ||
        x < 0 || y < 0 || x >= lv_display_get_original_horizontal_resolution(ctx->display) ||
        y >= lv_display_get_original_vertical_resolution(ctx->display)) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    if (remote->held != (kind != AIRUI_REMOTE_POINTER_DOWN)) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    remote_sample_t sample = {.point = {x, y}, .pressed = kind != AIRUI_REMOTE_POINTER_UP, .kind = kind};
    uint8_t tail = (remote->head + remote->count) % REMOTE_POINTER_QUEUE;
    const uint8_t last = (tail + REMOTE_POINTER_QUEUE - 1) % REMOTE_POINTER_QUEUE;
    if (kind == AIRUI_REMOTE_POINTER_MOVE && remote->count != 0 &&
        remote->samples[last].kind == AIRUI_REMOTE_POINTER_MOVE) {
        remote->samples[last] = sample;
    } else if (remote->count == REMOTE_POINTER_QUEUE ||
               (kind == AIRUI_REMOTE_POINTER_MOVE && remote->count == REMOTE_POINTER_QUEUE - 1)) {
        return AIRUI_ERR_PLATFORM_ERROR;
    } else {
        remote->samples[tail] = sample;
        remote->count++;
    }
    remote->held = sample.pressed;
    remote->input_tick = lv_tick_get();
    return AIRUI_OK;
}

#endif
