#include "luat_input_touch.h"

#ifdef LUAT_USE_INPUT_TOUCH
#include <stddef.h>
#include <string.h>

#define TOUCH_KEY_WORDS (LUAT_INPUT_BTN_TOUCH / 32U + 1U)
#define TOUCH_ABS_MAX 3U
#define TOUCH_MT_MAX 5U

struct luat_input_touch {
    luat_input_device_t device;
    luat_input_link_t link;
    luat_input_device_desc_t desc;
    luat_input_axis_t abs[TOUCH_ABS_MAX];
    luat_input_axis_t mt[TOUCH_MT_MAX];
    luat_input_handle_t handle;
};

static const uint32_t touch_keys[TOUCH_KEY_WORDS] = {
    [LUAT_INPUT_BTN_TOUCH / 32U] = UINT32_C(1) << (LUAT_INPUT_BTN_TOUCH % 32U)
};

size_t luat_input_touch_size(uint16_t slots)
{
    if (!slots || slots > LUAT_INPUT_MT_SLOTS_MAX) return SIZE_MAX;
    size_t words = TOUCH_KEY_WORDS + TOUCH_ABS_MAX + (size_t)slots * TOUCH_MT_MAX;
    return sizeof(luat_input_touch_t) + words * sizeof(uint32_t) +
        ((size_t)slots * 6U + 4U) * sizeof(luat_input_event_t);
}

static uint32_t *state_storage(luat_input_touch_t *touch)
{
    return (uint32_t *)(touch + 1);
}

static luat_input_event_t *event_storage(luat_input_touch_t *touch)
{
    return (luat_input_event_t *)(state_storage(touch) +
        luat_input_state_words(&touch->desc.caps));
}

static int axis_index(const luat_input_axis_t *axes, uint16_t count, uint16_t code)
{
    for (unsigned i = 0; i < count; i++) if (axes[i].code == code) return (int)i;
    return -1;
}

static int state_value(const luat_input_touch_t *touch, uint16_t code, uint16_t slot)
{
    const luat_input_caps_t *caps = &touch->desc.caps;
    int index = axis_index(caps->mt, caps->mt_count, code);
    return (int32_t)state_storage((luat_input_touch_t *)touch)[caps->key_words + caps->abs_count +
        (size_t)slot * caps->mt_count + (unsigned)index];
}

int luat_input_touch_init(luat_input_touch_t *touch, size_t bytes,
    luat_input_core_t *core, const luat_input_touch_config_t *config,
    luat_input_receive_t receive, void *userdata)
{
    if (!touch || !core || !config || config->maximum_x < 0 ||
        config->maximum_y < 0 || config->maximum_pressure < 0 ||
        config->maximum_touch_major < 0) return LUAT_INPUT_EINVAL;
    size_t required = luat_input_touch_size(config->slots);
    if (required == SIZE_MAX) return LUAT_INPUT_EINVAL;
    if (bytes < required) return LUAT_INPUT_ENOSPC;
    memset(touch, 0, required);
    touch->abs[0] = (luat_input_axis_t){LUAT_INPUT_ABS_X, 0, 0, config->maximum_x, 0};
    touch->abs[1] = (luat_input_axis_t){LUAT_INPUT_ABS_Y, 0, 0, config->maximum_y, 0};
    unsigned abs_count = 2;
    if (config->maximum_pressure)
        touch->abs[abs_count++] = (luat_input_axis_t){LUAT_INPUT_ABS_PRESSURE, 0, 0, config->maximum_pressure, 0};
    unsigned mt_count = 0;
    if (config->maximum_touch_major)
        touch->mt[mt_count++] = (luat_input_axis_t){LUAT_INPUT_ABS_MT_TOUCH_MAJOR, 0, 0, config->maximum_touch_major, 0};
    touch->mt[mt_count++] = (luat_input_axis_t){LUAT_INPUT_ABS_MT_POSITION_X, 0, 0, config->maximum_x, 0};
    touch->mt[mt_count++] = (luat_input_axis_t){LUAT_INPUT_ABS_MT_POSITION_Y, 0, 0, config->maximum_y, 0};
    touch->mt[mt_count++] = (luat_input_axis_t){LUAT_INPUT_ABS_MT_TRACKING_ID, 0, -1, INT32_MAX, -1};
    if (config->maximum_pressure)
        touch->mt[mt_count++] = (luat_input_axis_t){LUAT_INPUT_ABS_MT_PRESSURE, 0, 0, config->maximum_pressure, 0};
    touch->desc = (luat_input_device_desc_t){
        .name = config->name,
        .caps = {.keys = touch_keys, .abs = touch->abs, .mt = touch->mt,
            .key_words = TOUCH_KEY_WORDS, .abs_count = abs_count,
            .mt_count = mt_count, .mt_slots = config->slots},
        .properties = LUAT_INPUT_PROP_DIRECT,
        .bus = config->bus, .vendor = config->vendor, .product = config->product,
        .version = config->version
    };
    size_t words = luat_input_state_words(&touch->desc.caps);
    int ret = luat_input_register(core, &touch->device, &touch->desc,
        state_storage(touch), words, &touch->handle);
    if (ret || !receive) return ret;
    ret = luat_input_bind(touch->handle, &touch->link, receive, userdata);
    if (ret) {
        luat_input_unregister(touch->handle, 0);
        memset(&touch->handle, 0, sizeof(touch->handle));
    }
    return ret;
}

int luat_input_touch_feed(luat_input_touch_t *touch, uint32_t timestamp_ms,
    const luat_input_touch_point_t *points, uint16_t count)
{
    if (!touch || !touch->handle.device || !touch->handle.id ||
        !touch->handle.device->core || touch->handle.device->id != touch->handle.id)
        return LUAT_INPUT_ESTALE;
    if ((count && !points) || count > touch->desc.caps.mt_slots) return LUAT_INPUT_EINVAL;
    uint16_t slots = touch->desc.caps.mt_slots;
    int previous_primary = -1;
    for (unsigned slot = 0; slot < slots; slot++) {
        if (previous_primary < 0 &&
            state_value(touch, LUAT_INPUT_ABS_MT_TRACKING_ID, slot) >= 0)
            previous_primary = (int)slot;
    }
    uint32_t seen = 0;
    for (unsigned i = 0; i < count; i++) {
        const luat_input_touch_point_t *point = points + i;
        if (point->slot >= slots || (seen & (UINT32_C(1) << point->slot)) ||
            point->event < LUAT_INPUT_TOUCH_DOWN || point->event > LUAT_INPUT_TOUCH_UP)
            return LUAT_INPUT_EINVAL;
        seen |= UINT32_C(1) << point->slot;
        if (point->event == LUAT_INPUT_TOUCH_UP) continue;
        if (point->tracking_id < 0 || point->x < 0 || point->x > touch->abs[0].maximum ||
            point->y < 0 || point->y > touch->abs[1].maximum ||
            point->pressure < 0 || (touch->desc.caps.abs_count == 3 && point->pressure > touch->abs[2].maximum) ||
            point->touch_major < 0 || (touch->desc.caps.mt[0].code == LUAT_INPUT_ABS_MT_TOUCH_MAJOR &&
                                      point->touch_major > touch->mt[0].maximum)) return LUAT_INPUT_EINVAL;
    }
    luat_input_event_t *events = event_storage(touch);
    unsigned n = 0;
    for (unsigned i = 0; i < count; i++) {
        const luat_input_touch_point_t *point = points + i;
        int32_t old_tracking = state_value(touch, LUAT_INPUT_ABS_MT_TRACKING_ID, point->slot);
        if (point->event == LUAT_INPUT_TOUCH_UP && old_tracking < 0) continue;
        events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_SLOT, point->slot};
        if (point->event == LUAT_INPUT_TOUCH_UP) {
            events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_TRACKING_ID, -1};
            continue;
        }
        if (old_tracking != point->tracking_id)
            events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_TRACKING_ID, point->tracking_id};
        if (touch->desc.caps.mt[0].code == LUAT_INPUT_ABS_MT_TOUCH_MAJOR)
            events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_TOUCH_MAJOR, point->touch_major};
        events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_POSITION_X, point->x};
        events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_POSITION_Y, point->y};
        if (touch->desc.caps.abs_count == 3)
            events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_PRESSURE, point->pressure};
    }
    int primary = -1;
    for (unsigned slot = 0; slot < slots; slot++) {
        int active = state_value(touch, LUAT_INPUT_ABS_MT_TRACKING_ID, slot) >= 0;
        for (unsigned i = 0; i < count; i++) {
            if (points[i].slot == slot) {
                active = points[i].event != LUAT_INPUT_TOUCH_UP;
                break;
            }
        }
        if (active) { primary = (int)slot; break; }
    }
    if ((previous_primary < 0) != (primary < 0))
        events[n++] = (luat_input_event_t){LUAT_INPUT_EV_KEY, LUAT_INPUT_BTN_TOUCH,
                                           primary >= 0 ? LUAT_INPUT_PRESS : LUAT_INPUT_RELEASE};
    if (primary >= 0 && (primary != previous_primary || count)) {
        int32_t primary_x = state_value(touch, LUAT_INPUT_ABS_MT_POSITION_X, (uint16_t)primary);
        int32_t primary_y = state_value(touch, LUAT_INPUT_ABS_MT_POSITION_Y, (uint16_t)primary);
        int32_t primary_pressure = touch->desc.caps.abs_count == 3 ?
            state_value(touch, LUAT_INPUT_ABS_MT_PRESSURE, (uint16_t)primary) : 0;
        for (unsigned i = 0; i < count; i++) {
            if (points[i].slot == primary && points[i].event != LUAT_INPUT_TOUCH_UP) {
                primary_x = points[i].x;
                primary_y = points[i].y;
                primary_pressure = points[i].pressure;
                break;
            }
        }
        events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_X, primary_x};
        events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_Y, primary_y};
        if (touch->desc.caps.abs_count == 3)
            events[n++] = (luat_input_event_t){LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_PRESSURE, primary_pressure};
    }
    if (!n) return LUAT_INPUT_OK;
    return luat_input_submit(touch->handle, timestamp_ms, events, (uint16_t)n);
}

int luat_input_touch_reset(luat_input_touch_t *touch, uint32_t timestamp_ms)
{
    if (!touch) return LUAT_INPUT_EINVAL;
    return luat_input_reset(touch->handle, timestamp_ms);
}

int luat_input_touch_deinit(luat_input_touch_t *touch, uint32_t timestamp_ms)
{
    if (!touch) return LUAT_INPUT_EINVAL;
    int ret = luat_input_unregister(touch->handle, timestamp_ms);
    if (!ret) memset(&touch->handle, 0, sizeof(touch->handle));
    return ret;
}

luat_input_handle_t luat_input_touch_handle(luat_input_touch_t *touch)
{
    return touch ? touch->handle : (luat_input_handle_t){0};
}
#endif
