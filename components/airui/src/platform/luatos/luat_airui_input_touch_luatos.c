#include "luat_conf_bsp.h"
#if defined(LUAT_USE_AIRUI_LUATOS) && defined(LUAT_USE_INPUT_TOUCH)
#include "luat_airui_input_touch_luatos.h"
#include "luat_tp_input.h"
#include <string.h>

#define TP_POINTERS 2U
#define TP_FRAMES 16U

typedef struct {
    int32_t tracking;
    int16_t x, y;
    uint8_t event;
} tp_point_t;
typedef struct {
    tp_point_t points[LUAT_TP_TOUCH_MAX];
    uint32_t timestamp;
} tp_frame_t;

/* Two LVGL readers share immutable samples, with independent cursors. */
static tp_frame_t current, frames[TP_FRAMES];
static luat_input_handle_t bound;
static luat_input_link_t link;
static uint32_t tail, head[TP_POINTERS];
static unsigned readers, slots, selected_slot;
static uint8_t cancel[TP_POINTERS];
static uint8_t blocked[TP_POINTERS], notify_blocked;
static tp_point_t displayed[TP_POINTERS] = {{.tracking = -1}, {.tracking = -1}};

static void clear_points(tp_frame_t *frame)
{
    memset(frame, 0, sizeof(*frame));
    for (unsigned i = 0; i < LUAT_TP_TOUCH_MAX; i++) frame->points[i].tracking = -1;
}

static void cancel_pending(int lost)
{
    notify_blocked = !!lost;
    for (unsigned i = 0; i < TP_POINTERS; i++) {
        head[i] = tail;
        cancel[i] = 1;
        blocked[i] = !!lost;
    }
}

static void receive(void *userdata, const luat_input_frame_t *frame, const luat_input_event_t *events)
{
    (void)userdata;
    if (frame->flags & (LUAT_INPUT_FRAME_RESET | LUAT_INPUT_FRAME_REMOVE)) {
        clear_points(&current);
        selected_slot = 0;
        cancel_pending(0);
        return;
    }
    tp_frame_t previous = current;
    if (frame->flags & LUAT_INPUT_FRAME_ATTACH) {
        clear_points(&previous);
        clear_points(&current);
        for (unsigned i = 0; i < slots; i++) {
            int32_t value = -1;
            luat_input_get_value(bound, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_TRACKING_ID, i, &value);
            current.points[i].tracking = value;
            luat_input_get_value(bound, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_POSITION_X, i, &value);
            current.points[i].x = value;
            luat_input_get_value(bound, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_POSITION_Y, i, &value);
            current.points[i].y = value;
        }
    } else {
        for (unsigned i = 0; i < frame->count; i++) {
            const luat_input_event_t *event = events + i;
            if (event->type != LUAT_INPUT_EV_ABS) continue;
            if (event->code == LUAT_INPUT_ABS_MT_SLOT) { selected_slot = (unsigned)event->value; continue; }
            if (selected_slot >= slots) continue;
            tp_point_t *point = &current.points[selected_slot];
            if (event->code == LUAT_INPUT_ABS_MT_TRACKING_ID) point->tracking = event->value;
            else if (event->code == LUAT_INPUT_ABS_MT_POSITION_X) point->x = event->value;
            else if (event->code == LUAT_INPUT_ABS_MT_POSITION_Y) point->y = event->value;
        }
    }
    for (unsigned i = 0; i < slots; i++) {
        tp_point_t *p = &current.points[i];
        p->event = p->tracking >= 0 ? (previous.points[i].tracking == p->tracking ?
            AIRUI_TOUCH_STATE_HOLD : AIRUI_TOUCH_STATE_DOWN) :
            (previous.points[i].tracking >= 0 ? AIRUI_TOUCH_STATE_UP : AIRUI_TOUCH_STATE_NONE);
    }
    current.timestamp = frame->timestamp_ms;
    for (unsigned i = 0; i < readers; i++) {
        if ((uint32_t)(tail - head[i]) >= TP_FRAMES) { cancel_pending(1); break; }
    }
    frames[tail++ % TP_FRAMES] = current;
}

/* Service lock held. Bind by instance id, never by a borrowed TP buffer. */
static void bind_device(uint32_t id)
{
    if (id == bound.id && (!id || link.device)) return;
    int had_device = bound.id != 0;
    if (link.device) luat_input_unbind(&link);
    memset(&bound, 0, sizeof(bound));
    tail = 0; selected_slot = 0; slots = 0;
    notify_blocked = 0;
    clear_points(&current);
    for (unsigned i = 0; i < TP_POINTERS; i++) {
        head[i] = 0; cancel[i] = had_device; blocked[i] = 0;
        displayed[i].tracking = -1;
    }
    if (!id || luat_input_lookup(luat_input_service_core(), id, &bound)) {
        memset(&bound, 0, sizeof(bound));
        return;
    }
    const luat_input_device_desc_t *desc;
    if (luat_input_get_desc(bound, &desc) || desc->caps.mt_slots > LUAT_TP_TOUCH_MAX) {
        memset(&bound, 0, sizeof(bound));
        return;
    }
    slots = desc->caps.mt_slots;
    if (luat_input_bind(bound, &link, receive, NULL)) memset(&bound, 0, sizeof(bound));
}

bool airui_input_touch_read(airui_ctx_t *ctx, lv_indev_t *indev,
    lv_indev_data_t *data, luat_tp_config_t *config, unsigned slot)
{
    if (slot >= TP_POINTERS) return false;
    if (!luat_tp_input_id(config) && !bound.id) {
        data->state = LV_INDEV_STATE_RELEASED;
        return false;
    }
    tp_frame_t sample = {0};
    bool have_sample = false, cancelled, notify_sample = false;
    unsigned count;
    luat_input_service_lock();
    readers = ctx->indev_ptr_count < TP_POINTERS ? ctx->indev_ptr_count : TP_POINTERS;
    bind_device(luat_tp_input_id(config));
    count = slots;
    cancelled = cancel[slot]; cancel[slot] = 0;
    if (!cancelled && head[slot] != tail) {
        sample = frames[head[slot]++ % TP_FRAMES];
        displayed[slot] = sample.points[slot];
        if (blocked[slot]) {
            if (displayed[slot].tracking < 0) blocked[slot] = 0;
            displayed[slot].tracking = -1;
        }
        have_sample = true;
        if (slot == 0) {
            notify_sample = !notify_blocked;
            if (notify_blocked) {
                bool active = false;
                for (unsigned i = 0; i < slots; i++) active |= sample.points[i].tracking >= 0;
                if (!active) notify_blocked = 0;
            }
        }
    }
    if (cancelled) displayed[slot].tracking = -1;
    tp_point_t point = displayed[slot];
    data->continue_reading = head[slot] != tail;
    luat_input_service_unlock();
    data->point.x = point.x; data->point.y = point.y;
    data->state = point.tracking >= 0 ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    if (cancelled) {
        lv_indev_reset(indev, NULL);
        lv_indev_wait_release(indev);
        if (slot == 0) {
            ctx->touch_pressed = false;
            ctx->touch_active_count = 0;
            ctx->touch_last_state = AIRUI_TOUCH_STATE_NONE;
            memset(ctx->touch_active, 0, sizeof(ctx->touch_active));
        }
    }
    if (slot == 0 && have_sample && notify_sample && ctx->touch_callback_ref > 0) {
        airui_touch_point_t points[AIRUI_TOUCH_MAX_POINTS];
        uint8_t n = 0;
        for (unsigned i = 0; i < count && n < AIRUI_TOUCH_MAX_POINTS; i++) {
            const tp_point_t *p = &sample.points[i];
            if (p->event == AIRUI_TOUCH_STATE_NONE) continue;
            points[n++] = (airui_touch_point_t){p->event, p->x, p->y, (uint8_t)i, sample.timestamp};
        }
        if (n) airui_touch_notify(ctx, points, n);
    }
    return data->state == LV_INDEV_STATE_PRESSED;
}
#endif
