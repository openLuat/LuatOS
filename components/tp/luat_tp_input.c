#include "luat_tp_input.h"
#ifdef LUAT_USE_INPUT_TOUCH
#include "luat_input_touch.h"
#include "luat_malloc.h"
#include <string.h>
#include <limits.h>

typedef struct {
    luat_input_touch_t *touch;
    luat_tp_data_t previous[LUAT_TP_TOUCH_MAX];
    luat_input_touch_point_t active[LUAT_TP_TOUCH_MAX];
    uint32_t next_tracking;
    uint16_t slots;
    uint8_t previous_valid;
} tp_input_t;

static const luat_tp_sink_ops_t input_sink;

uint32_t luat_tp_input_id(const luat_tp_config_t *cfg)
{
    return cfg && cfg->sink_ops == &input_sink ?
        __atomic_load_n(&cfg->sink_id, __ATOMIC_ACQUIRE) : 0;
}

int luat_tp_input_init(luat_tp_config_t *cfg)
{
    if (cfg->sink_context) return LUAT_INPUT_EBUSY;
    if (!luat_input_service_is_ready()) return LUAT_INPUT_SERVICE_ENOTREADY;
    unsigned slots = cfg->tp_num ? cfg->tp_num : LUAT_TP_TOUCH_MAX;
    if (slots > LUAT_TP_TOUCH_MAX || cfg->w <= 0 || cfg->h <= 0) return LUAT_INPUT_EINVAL;
    size_t bytes = luat_input_touch_size(slots);
    tp_input_t *ctx = luat_heap_calloc(1, sizeof(*ctx) + bytes);
    if (!ctx) return LUAT_INPUT_SERVICE_ENOMEM;
    ctx->touch = (void *)(ctx + 1);
    ctx->slots = slots;
    int32_t w, h;
    luat_tp_dimensions(cfg, &w, &h);
    luat_input_touch_config_t desc = {
        .name = cfg->opts->name, .slots = slots, .bus = 0x18, /* I2C */
        .maximum_x = w - 1, .maximum_y = h - 1, .maximum_touch_major = UINT8_MAX
    };
    luat_input_service_lock();
    int ret = luat_input_touch_init(ctx->touch, bytes, luat_input_service_core(), &desc, NULL, NULL);
    if (!ret) {
        luat_input_handle_t handle = luat_input_touch_handle(ctx->touch);
        ret = luat_input_service_attach(handle);
        if (ret) luat_input_touch_deinit(ctx->touch, luat_mcu_ticks());
        else {
            cfg->sink_context = ctx;
            __atomic_store_n(&cfg->sink_id, handle.id, __ATOMIC_RELEASE);
        }
    }
    luat_input_service_unlock();
    if (ret) luat_heap_free(ctx);
    return ret;
}

void luat_tp_input_reset(luat_tp_config_t *cfg)
{
    tp_input_t *ctx = cfg->sink_context;
    if (!ctx) return;
    luat_input_service_lock();
    luat_input_touch_reset(ctx->touch, luat_mcu_ticks());
    luat_input_service_unlock();
    memset(ctx->active, 0, sizeof(ctx->active));
    if (ctx->next_tracking == INT32_MAX) ctx->next_tracking = 0;
    /* Do not replay an unchanged, stale driver snapshot after a reset. */
    memcpy(ctx->previous, cfg->tp_data, sizeof(ctx->previous));
    ctx->previous_valid = 1;
}

void luat_tp_input_deinit(luat_tp_config_t *cfg)
{
    tp_input_t *ctx = cfg->sink_context;
    if (!ctx) return;
    luat_input_service_lock();
    __atomic_store_n(&cfg->sink_id, 0, __ATOMIC_RELEASE);
    luat_input_service_detach(luat_input_touch_handle(ctx->touch));
    luat_input_touch_deinit(ctx->touch, luat_mcu_ticks());
    luat_input_service_unlock();
    cfg->sink_context = NULL;
    luat_heap_free(ctx);
}

void luat_tp_input_suspend(luat_tp_config_t *cfg, int suspended)
{
    tp_input_t *ctx = cfg->sink_context;
    if (!ctx) return;
    luat_tp_input_reset(cfg);
    (void)suspended; /* The TP driver owns running/suspended state. */
}

int luat_tp_input_feed(luat_tp_config_t *cfg, luat_tp_data_t *normalized)
{
    tp_input_t *ctx = cfg->sink_context;
    if (!ctx) return LUAT_INPUT_ESTALE;
    if (ctx->previous_valid && !memcmp(ctx->previous, cfg->tp_data, sizeof(ctx->previous))) return 0;
    luat_input_touch_point_t updates[LUAT_TP_TOUCH_MAX];
    luat_input_touch_point_t next[LUAT_TP_TOUCH_MAX];
    memcpy(next, ctx->active, sizeof(next));
    memset(normalized, 0, sizeof(*normalized) * LUAT_TP_TOUCH_MAX);
    unsigned count = 0;
    uint32_t seen = 0;
    uint32_t tracking = ctx->next_tracking;
    for (unsigned i = 0; i < LUAT_TP_TOUCH_MAX; i++) {
        const luat_tp_data_t *raw = &cfg->tp_data[i];
        if (raw->event == TP_EVENT_TYPE_NONE) continue;
        unsigned slot = raw->track_id;
        if (slot >= ctx->slots || (seen & (1U << slot)) || raw->event > TP_EVENT_TYPE_MOVE) return LUAT_INPUT_EINVAL;
        seen |= 1U << slot;
        luat_input_touch_point_t *point = &next[slot];
        if (raw->event == TP_EVENT_TYPE_UP) {
            if (!point->tracking_id) continue;
            point->event = LUAT_INPUT_TOUCH_UP;
        } else {
            int32_t x = raw->x_coordinate, y = raw->y_coordinate;
            if (luat_tp_transform(cfg, &x, &y)) return LUAT_INPUT_EINVAL;
            if (point->tracking_id && point->x == x && point->y == y && point->touch_major == raw->width) continue;
            if (!point->tracking_id) {
                if (tracking == INT32_MAX) return LUAT_INPUT_ENOSPC;
                point->tracking_id = ++tracking;
                point->event = LUAT_INPUT_TOUCH_DOWN;
            } else point->event = LUAT_INPUT_TOUCH_MOVE;
            point->x = x; point->y = y; point->touch_major = raw->width;
        }
        point->slot = slot;
        updates[count++] = *point;
        normalized[slot] = *raw;
        normalized[slot].x_coordinate = point->x;
        normalized[slot].y_coordinate = point->y;
        normalized[slot].event = point->event == LUAT_INPUT_TOUCH_UP ? TP_EVENT_TYPE_UP :
            point->event == LUAT_INPUT_TOUCH_DOWN ? TP_EVENT_TYPE_DOWN : TP_EVENT_TYPE_MOVE;
        if (point->event == LUAT_INPUT_TOUCH_UP) point->tracking_id = 0;
    }
    luat_input_service_lock();
    int ret = luat_input_touch_feed(ctx->touch, luat_mcu_ticks(), updates, count);
    luat_input_service_unlock();
    if (ret) return ret;
    memcpy(ctx->active, next, sizeof(next));
    memcpy(ctx->previous, cfg->tp_data, sizeof(ctx->previous));
    ctx->previous_valid = 1;
    ctx->next_tracking = tracking;
    return count;
}

static const luat_tp_sink_ops_t input_sink = {
    .open = luat_tp_input_init, .close = luat_tp_input_deinit,
    .process = luat_tp_input_feed, .reset = luat_tp_input_reset,
    .suspend = luat_tp_input_suspend
};
int luat_tp_input_setup(luat_tp_config_t *cfg)
{
    if (!cfg || cfg->initialized || cfg->sink_context) return LUAT_INPUT_EBUSY;
    cfg->sink_ops = &input_sink;
    return 0;
}
#endif
