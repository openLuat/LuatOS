/** @file luat_plcui_input_luatos.c One-pointer consumer of normalized TP frames. */
#include "luat_conf_bsp.h"
#if defined(LUAT_USE_PLCUI_LUATOS)

#include "luat_plcui_luatos.h"
#include "luat_plcui_conf.h"
#include "luat_tp_input.h"
#include <string.h>

#define LUAT_LOG_TAG "plcui.touch"
#include "luat_log.h"

#define PLCUI_TOUCH_FRAMES 32U

typedef struct {
    int32_t tracking;
    int32_t x;
    int32_t y;
} touch_point_t;

/* Only the UI thread accesses indev/config. The remaining state is serialized
 * with the input service lock; receive never calls LVGL, Lua, or TP lifecycle. */
static struct {
    lv_indev_t *indev;
    luat_tp_config_t *config;
    luat_input_handle_t bound;
    luat_input_link_t link;
    touch_point_t points[LUAT_TP_TOUCH_MAX];
    touch_point_t frames[PLCUI_TOUCH_FRAMES];
    touch_point_t shown;
    uint32_t head;
    uint32_t tail;
    unsigned slots;
    unsigned selected_slot;
    int primary;
    int32_t primary_tracking;
    uint8_t cancel;
    uint8_t blocked;
} touch;

static void clear_points(void)
{
    memset(touch.points, 0, sizeof(touch.points));
    for (unsigned i = 0; i < LUAT_TP_TOUCH_MAX; ++i) touch.points[i].tracking = -1;
    touch.primary = -1;
    touch.primary_tracking = -1;
    touch.selected_slot = 0;
}

static void cancel_samples(void)
{
    touch.head = touch.tail;
    touch.cancel = 1;
    touch.blocked = 1;
    touch.primary = -1;
    touch.primary_tracking = -1;
}

static void receive(void *userdata, const luat_input_frame_t *frame, const luat_input_event_t *events)
{
    (void)userdata;
    if (frame->flags & (LUAT_INPUT_FRAME_RESET | LUAT_INPUT_FRAME_REMOVE)) {
        clear_points();
        cancel_samples();
        return;
    }
    if (frame->flags & LUAT_INPUT_FRAME_ATTACH) {
        clear_points();
        for (unsigned slot = 0; slot < touch.slots; ++slot) {
            luat_input_get_value(touch.bound, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_TRACKING_ID,
                                 slot, &touch.points[slot].tracking);
            luat_input_get_value(touch.bound, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_POSITION_X,
                                 slot, &touch.points[slot].x);
            luat_input_get_value(touch.bound, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_POSITION_Y,
                                 slot, &touch.points[slot].y);
        }
        /* A finger held while binding is not a new press. */
        cancel_samples();
    } else {
        for (unsigned i = 0; i < frame->count; ++i) {
            const luat_input_event_t *event = &events[i];
            if (event->type != LUAT_INPUT_EV_ABS) continue;
            if (event->code == LUAT_INPUT_ABS_MT_SLOT) {
                touch.selected_slot = (unsigned)event->value;
                continue;
            }
            if (touch.selected_slot >= touch.slots) continue;
            touch_point_t *point = &touch.points[touch.selected_slot];
            if (event->code == LUAT_INPUT_ABS_MT_TRACKING_ID) point->tracking = event->value;
            else if (event->code == LUAT_INPUT_ABS_MT_POSITION_X) point->x = event->value;
            else if (event->code == LUAT_INPUT_ABS_MT_POSITION_Y) point->y = event->value;
        }
    }

    int first = -1;
    for (unsigned i = 0; i < touch.slots; ++i) {
        if (touch.points[i].tracking >= 0) { first = (int)i; break; }
    }
    if ((uint32_t)(touch.tail - touch.head) >= PLCUI_TOUCH_FRAMES) cancel_samples();

    touch_point_t sample = { .tracking = -1, .x = touch.shown.x, .y = touch.shown.y };
    if (touch.blocked) {
        if (first < 0) touch.blocked = 0;
    } else if (touch.primary >= 0) {
        touch_point_t point = touch.points[touch.primary];
        if (point.tracking == touch.primary_tracking) {
            sample = point;
        } else if (point.tracking >= 0) {
            /* The selected slot was recycled without an observed release. */
            cancel_samples();
        } else {
            sample.x = point.x;
            sample.y = point.y;
            touch.primary = -1;
            touch.primary_tracking = -1;
            touch.blocked = first >= 0;
        }
    } else if (first >= 0) {
        touch.primary = first;
        touch.primary_tracking = touch.points[first].tracking;
        sample = touch.points[first];
    }
    touch.frames[touch.tail++ % PLCUI_TOUCH_FRAMES] = sample;
}

/* All caller paths run on the UI thread. The service lock protects bindings. */
static int bind_config(luat_tp_config_t *config)
{
    uint32_t id = config ? luat_tp_input_id(config) : 0;
    if (config && !id) return LUAT_INPUT_ESTALE;
    if (id && id == touch.bound.id && touch.link.device) return 0;
    luat_input_handle_t next = {0};
    const luat_input_device_desc_t *desc = NULL;
    if (id) {
        int result = luat_input_lookup(luat_input_service_core(), id, &next);
        if (result != 0) return result;
        result = luat_input_get_desc(next, &desc);
        if (result != 0) return result;
        if (!desc->caps.mt_slots || desc->caps.mt_slots > LUAT_TP_TOUCH_MAX) return LUAT_INPUT_ENOTSUP;
    }
    if (touch.link.device) luat_input_unbind(&touch.link);
    memset(&touch.bound, 0, sizeof(touch.bound));
    clear_points();
    cancel_samples();
    touch.slots = 0;
    if (!id) return 0;
    touch.bound = next;
    touch.slots = desc->caps.mt_slots;
    int result = luat_input_bind(next, &touch.link, receive, NULL);
    if (result != 0) {
        memset(&touch.bound, 0, sizeof(touch.bound));
        touch.slots = 0;
    }
    return result;
}

int plcui_platform_bind_touch(luat_tp_config_t *config)
{
    if (!touch.indev) return -1;
    if (config && (config->w != lv_display_get_horizontal_resolution(plcui_luatos_display()) ||
                   config->h != lv_display_get_vertical_resolution(plcui_luatos_display()))) return -1;
    if (!luat_input_service_is_ready()) return config ? LUAT_INPUT_SERVICE_ENOTREADY : 0;
    luat_input_service_lock();
    int result = bind_config(config);
    if (result == 0) touch.config = config;
    luat_input_service_unlock();
    if (result == 0) LLOGI("touch %s id=%u", config ? "bound" : "unbound", config ? luat_tp_input_id(config) : 0U);
    return result;
}

static void pointer_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    int cancelled = 0;
    if (luat_input_service_is_ready()) {
        luat_input_service_lock();
        cancelled = touch.cancel;
        touch.cancel = 0;
        if (!cancelled && touch.head != touch.tail) {
            touch.shown = touch.frames[touch.head++ % PLCUI_TOUCH_FRAMES];
        }
        if (cancelled) touch.shown.tracking = -1;
        data->continue_reading = touch.head != touch.tail;
        data->point.x = touch.shown.x;
        data->point.y = touch.shown.y;
        data->state = touch.shown.tracking >= 0 ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
        luat_input_service_unlock();
    } else {
        data->state = LV_INDEV_STATE_RELEASED;
        data->continue_reading = false;
    }
    if (data->state == LV_INDEV_STATE_PRESSED &&
        (data->point.x < 0 || data->point.y < 0 ||
         data->point.x >= lv_display_get_horizontal_resolution(plcui_luatos_display()) ||
         data->point.y >= lv_display_get_vertical_resolution(plcui_luatos_display()))) {
        luat_input_service_lock();
        cancel_samples();
        luat_input_service_unlock();
        cancelled = 1;
        data->state = LV_INDEV_STATE_RELEASED;
    }
    if (cancelled) {
        lv_indev_reset(indev, NULL);
        lv_indev_wait_release(indev);
    }
}

int plcui_luatos_input_init(lv_display_t *display)
{
    if (touch.indev || !display) return -1;
    memset(&touch, 0, sizeof(touch));
    clear_points();
    touch.shown.tracking = -1;
    touch.indev = lv_indev_create();
    if (!touch.indev) return -1;
    lv_indev_set_type(touch.indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_display(touch.indev, display);
    lv_indev_set_read_cb(touch.indev, pointer_read);
    lv_timer_set_period(lv_indev_get_read_timer(touch.indev), PLCUI_REFRESH_PERIOD_MS);
    return 0;
}

void plcui_luatos_input_poll(void)
{
    if (!touch.indev || !touch.config || !luat_input_service_is_ready()) return;
    luat_input_service_lock();
    uint32_t id = luat_tp_input_id(touch.config);
    if (!id || id != touch.bound.id || !touch.link.device) {
        int result = bind_config(id ? touch.config : NULL);
        if (result != 0) cancel_samples();
    }
    luat_input_service_unlock();
}

void plcui_luatos_input_deinit(void)
{
    if (luat_input_service_is_ready()) {
        luat_input_service_lock();
        bind_config(NULL);
        touch.config = NULL;
        luat_input_service_unlock();
    }
    if (touch.indev) lv_indev_delete(touch.indev);
    memset(&touch, 0, sizeof(touch));
}

#endif
