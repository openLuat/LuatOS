#include "luat_airui_remote.h"

#if defined(LUAT_USE_AIRUI_REMOTE)

#include "luat_mem.h"
#include <string.h>
#include "tiny_jpeg.h"
#include <stdlib.h>

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
    size_t capacity;
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
    remote->capacity = 0;
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

#define REMOTE_JPEG_MAX_BYTES (64U * 1024U)

typedef struct {
    uint8_t *data;
    size_t capacity;
    size_t used;
    bool overflow;
} remote_jpeg_output_t;

static void write_jpeg(void *context, void *data, int len)
{
    remote_jpeg_output_t *out = context;
    if (len < 0 || (size_t)len > out->capacity - out->used) {
        out->overflow = true;
    }
    if (!out->overflow) {
        memcpy(out->data + out->used, data, (size_t)len);
        out->used += (size_t)len;
    }
}

static int encode_jpeg(const airui_remote_frame_t *frame, uint32_t scale,
                       uint32_t width, uint32_t height, remote_jpeg_output_t *out)
{
    uint8_t *strip = luat_heap_malloc((size_t)width * 8U * 3U);
    if (strip == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    void *encoder = jpeg_encode_init(write_jpeg, out, 1, width, height, 3);
    if (encoder == NULL) {
        luat_heap_free(strip);
        return AIRUI_ERR_NO_MEM;
    }

    uint16_t last_pixel = 0;
    uint8_t last_y = 0;
    uint8_t last_cb = 128;
    uint8_t last_cr = 128;
    for (uint32_t y = 0; y < height && !out->overflow; y += 8) {
        uint8_t *dest = strip;
        for (uint32_t row = y; row < y + 8; row++) {
            uint32_t source_y = row < height ? row : height - 1;
            const uint16_t *source = (const uint16_t *)(frame->pixels + source_y * scale * frame->stride);
            for (uint32_t x = 0; x < width; x++) {
                uint16_t pixel = source[x * scale];
                if (pixel != last_pixel) {
                    int r = (pixel >> 11) & 31;
                    int g = (pixel >> 5) & 63;
                    int b = pixel & 31;
                    r = (r << 3) | (r >> 2);
                    g = (g << 2) | (g >> 4);
                    b = (b << 3) | (b >> 2);
                    last_y = (uint8_t)((77 * r + 150 * g + 29 * b + 128) >> 8);
                    last_cb = (uint8_t)((32768 - 43 * r - 85 * g + 128 * b) >> 8);
                    last_cr = (uint8_t)((32768 + 128 * r - 107 * g - 21 * b) >> 8);
                    last_pixel = pixel;
                }
                *dest++ = last_y;
                *dest++ = last_cb;
                *dest++ = last_cr;
            }
        }
        jpeg_encode_run(encoder, strip);
    }
    jpeg_encode_end(encoder);
    free(encoder);
    luat_heap_free(strip);
    return out->overflow ? AIRUI_ERR_PLATFORM_ERROR : AIRUI_OK;
}

static int capture_frame(airui_ctx_t *ctx, uint32_t scale, uint32_t previous,
                         airui_remote_capture_info_t *info, bool jpeg)
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
        size_t capacity = len;
        if (jpeg && capacity > REMOTE_JPEG_MAX_BYTES) {
            capacity = REMOTE_JPEG_MAX_BYTES;
        }
        if (remote->pixels == NULL || remote->capacity != capacity) {
            release_frame(remote);
            remote->pixels = luat_heap_malloc(capacity);
            if (remote->pixels == NULL) {
                return AIRUI_ERR_NO_MEM;
            }
            remote->capacity = capacity;
        }
        luat_airui_remote_sync_fb(frame.pixels, (size_t)frame.stride * frame.height);
        if (jpeg) {
            remote_jpeg_output_t out = {.data = remote->pixels, .capacity = capacity};
            ret = encode_jpeg(&frame, scale, width, height, &out);
            if (ret != AIRUI_OK) {
                release_frame(remote);
                return ret;
            }
            len = out.used;
        } else {
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

int airui_remote_capture_rgb(airui_ctx_t *ctx, uint32_t scale, uint32_t previous,
                            airui_remote_capture_info_t *info)
{
    return capture_frame(ctx, scale, previous, info, false);
}

int airui_remote_capture_jpeg(airui_ctx_t *ctx, uint32_t scale, uint32_t previous,
                             airui_remote_capture_info_t *info)
{
    return capture_frame(ctx, scale, previous, info, true);
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
