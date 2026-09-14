#include "luat_input_touch.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    unsigned calls;
    luat_input_frame_t frame;
    luat_input_event_t events[32];
} observer_t;

static void observe(void *userdata, const luat_input_frame_t *frame,
    const luat_input_event_t *events)
{
    observer_t *observer = userdata;
    observer->calls++;
    observer->frame = *frame;
    assert(frame->count <= 32);
    if (frame->count) memcpy(observer->events, events, frame->count * sizeof(*events));
}

static int value(luat_input_handle_t handle, uint16_t type, uint16_t code, uint16_t slot)
{
    int32_t result = -999;
    assert(!luat_input_get_value(handle, type, code, slot, &result));
    return result;
}

int main(void)
{
    luat_input_core_t core;
    luat_input_init(&core);
    uint64_t storage[256] = {0};
    observer_t observer = {0};
    const luat_input_touch_config_t config = {
        .name = "test touch", .maximum_x = 799, .maximum_y = 479,
        .maximum_pressure = 255, .maximum_touch_major = 20, .slots = 2,
        .bus = 0x18, .vendor = 1, .product = 2, .version = 3
    };
    assert(luat_input_touch_size(0) == SIZE_MAX);
    assert(luat_input_touch_size(LUAT_INPUT_MT_SLOTS_MAX + 1) == SIZE_MAX);
    assert(luat_input_touch_size(config.slots) <= sizeof(storage));
    luat_input_touch_t *touch = (void *)storage;
    assert(!luat_input_touch_init(touch, sizeof(storage), &core, &config, observe, &observer));
    assert(observer.calls == 1 && observer.frame.flags == LUAT_INPUT_FRAME_ATTACH);
    luat_input_handle_t handle = luat_input_touch_handle(touch);
    const luat_input_device_desc_t *desc = NULL;
    assert(!luat_input_get_desc(handle, &desc));
    assert(desc->properties == LUAT_INPUT_PROP_DIRECT && desc->caps.mt_slots == 2);
    assert(desc->caps.abs_count == 3 && desc->caps.mt_count == 5);

    const luat_input_touch_point_t down[] = {
        {.slot = 0, .event = LUAT_INPUT_TOUCH_DOWN, .tracking_id = 10,
         .x = 100, .y = 200, .pressure = 30, .touch_major = 4},
        {.slot = 1, .event = LUAT_INPUT_TOUCH_DOWN, .tracking_id = 11,
         .x = 300, .y = 400, .pressure = 31, .touch_major = 5}
    };
    assert(!luat_input_touch_feed(touch, 10, down, 2));
    assert(value(handle, LUAT_INPUT_EV_KEY, LUAT_INPUT_BTN_TOUCH, 0) == 1);
    assert(value(handle, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_X, 0) == 100);
    assert(value(handle, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_TRACKING_ID, 0) == 10);
    assert(value(handle, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_POSITION_Y, 1) == 400);

    const luat_input_touch_point_t move = {
        .slot = 1, .event = LUAT_INPUT_TOUCH_MOVE, .tracking_id = 11,
        .x = 320, .y = 410, .pressure = 40, .touch_major = 6
    };
    assert(!luat_input_touch_feed(touch, 11, &move, 1));
    assert(value(handle, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_POSITION_X, 1) == 320);
    assert(value(handle, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_X, 0) == 100);

    const luat_input_touch_point_t up0 = {.slot = 0, .event = LUAT_INPUT_TOUCH_UP};
    assert(!luat_input_touch_feed(touch, 12, &up0, 1));
    assert(value(handle, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_TRACKING_ID, 0) == -1);
    assert(value(handle, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_X, 0) == 320);
    assert(value(handle, LUAT_INPUT_EV_KEY, LUAT_INPUT_BTN_TOUCH, 0) == 1);

    uint32_t sequence = handle.device->sequence;
    luat_input_touch_point_t invalid[2] = {move, move};
    assert(luat_input_touch_feed(touch, 13, invalid, 2) == LUAT_INPUT_EINVAL);
    assert(handle.device->sequence == sequence);
    const luat_input_touch_point_t up1 = {.slot = 1, .event = LUAT_INPUT_TOUCH_UP};
    assert(!luat_input_touch_feed(touch, 14, &up1, 1));
    assert(value(handle, LUAT_INPUT_EV_KEY, LUAT_INPUT_BTN_TOUCH, 0) == 0);
    assert(!luat_input_touch_reset(touch, 15));
    assert(!luat_input_touch_deinit(touch, 16));
    assert(luat_input_touch_feed(touch, 17, NULL, 0) == LUAT_INPUT_ESTALE);
    puts("Touch adapter PASS: two slots, primary fallback, pressure/major, atomic reject and lifecycle");
    return 0;
}
