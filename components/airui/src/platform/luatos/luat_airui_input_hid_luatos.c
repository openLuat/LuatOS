/**
 * @file luat_airui_input_hid_luatos.c
 * @summary Small input-core to LVGL bridge for USB mouse and keyboard devices.
 */

#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
#include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS) && defined(LUAT_USE_INPUT)

#include "luat_airui_input_hid_luatos.h"
#include "luat_input_airui.h"
#include <limits.h>
#include <string.h>

#define AIRUI_HID_DEVICES 8U
#define AIRUI_HID_KEY_QUEUE 32U
#define AIRUI_HID_POINTER_QUEUE 32U

typedef struct {
    uint32_t id;
    uint8_t active;
    uint8_t pointer;
    uint8_t left;
    uint8_t shift;
    uint8_t caps;
    uint8_t pressed[128]; /* Translation at press time, including Shift/Caps. */
} airui_hid_device_t;

typedef struct {
    uint32_t device_id;
    uint32_t key;
    lv_indev_state_t state;
    uint16_t code;
} airui_hid_key_event_t;

typedef struct {
    int32_t dx, dy, wheel;
    uint8_t pressed;
} airui_hid_pointer_event_t;

static airui_hid_device_t g_devices[AIRUI_HID_DEVICES];
static airui_hid_key_event_t g_keys[AIRUI_HID_KEY_QUEUE];
static uint8_t g_key_head;
static uint8_t g_key_tail;
static uint8_t g_pointer_position_valid;
static int32_t g_pointer_x;
static int32_t g_pointer_y;
static uint32_t g_last_key;
static uint32_t g_last_key_device;
static uint16_t g_last_key_code;
static uint8_t g_key_cancel;
static airui_hid_pointer_event_t g_pointer_queue[AIRUI_HID_POINTER_QUEUE];
static uint8_t g_pointer_head, g_pointer_tail, g_pointer_pressed, g_pointer_cancel;
static luat_input_airui_lock_t g_lock;
static luat_input_airui_unlock_t g_unlock;
static void *g_lock_userdata;

static uintptr_t bridge_lock(void)
{
    return g_lock ? g_lock(g_lock_userdata) : 0;
}

static void bridge_unlock(uintptr_t token)
{
    if (g_unlock) g_unlock(g_lock_userdata, token);
}

void luat_input_airui_set_lock(luat_input_airui_lock_t lock,
    luat_input_airui_unlock_t unlock, void *userdata)
{
    if (!!lock != !!unlock) return;
    g_lock = lock;
    g_unlock = unlock;
    g_lock_userdata = userdata;
}

static airui_hid_device_t *device_find(uint32_t id, bool create)
{
    airui_hid_device_t *free_slot = NULL;
    for (unsigned i = 0; i < AIRUI_HID_DEVICES; i++) {
        if (g_devices[i].active && g_devices[i].id == id) return &g_devices[i];
        if (!g_devices[i].active && !free_slot) free_slot = &g_devices[i];
    }
    if (!create || !free_slot) return NULL;
    memset(free_slot, 0, sizeof(*free_slot));
    free_slot->id = id;
    free_slot->active = 1;
    return free_slot;
}

static bool is_modifier(uint16_t code)
{
    return code == LUAT_INPUT_KEY_LEFTSHIFT || code == LUAT_INPUT_KEY_RIGHTSHIFT ||
           code == LUAT_INPUT_KEY_LEFTCTRL || code == LUAT_INPUT_KEY_RIGHTCTRL ||
           code == LUAT_INPUT_KEY_LEFTALT || code == LUAT_INPUT_KEY_RIGHTALT;
}

static uint32_t printable_key(uint16_t code, bool shifted)
{
    static const char plain[128] = {
        [LUAT_INPUT_KEY_1]='1', [LUAT_INPUT_KEY_2]='2', [LUAT_INPUT_KEY_3]='3', [LUAT_INPUT_KEY_4]='4',
        [LUAT_INPUT_KEY_5]='5', [LUAT_INPUT_KEY_6]='6', [LUAT_INPUT_KEY_7]='7', [LUAT_INPUT_KEY_8]='8',
        [LUAT_INPUT_KEY_9]='9', [LUAT_INPUT_KEY_0]='0',
        [LUAT_INPUT_KEY_MINUS]='-', [LUAT_INPUT_KEY_EQUAL]='=', [LUAT_INPUT_KEY_Q]='q', [LUAT_INPUT_KEY_W]='w',
        [LUAT_INPUT_KEY_E]='e', [LUAT_INPUT_KEY_R]='r', [LUAT_INPUT_KEY_T]='t', [LUAT_INPUT_KEY_Y]='y',
        [LUAT_INPUT_KEY_U]='u', [LUAT_INPUT_KEY_I]='i',
        [LUAT_INPUT_KEY_O]='o', [LUAT_INPUT_KEY_P]='p', [LUAT_INPUT_KEY_LEFTBRACE]='[', [LUAT_INPUT_KEY_RIGHTBRACE]=']',
        [LUAT_INPUT_KEY_A]='a', [LUAT_INPUT_KEY_S]='s', [LUAT_INPUT_KEY_D]='d', [LUAT_INPUT_KEY_F]='f',
        [LUAT_INPUT_KEY_G]='g', [LUAT_INPUT_KEY_H]='h',
        [LUAT_INPUT_KEY_J]='j', [LUAT_INPUT_KEY_K]='k', [LUAT_INPUT_KEY_L]='l', [LUAT_INPUT_KEY_SEMICOLON]=';',
        [LUAT_INPUT_KEY_APOSTROPHE]='\'', [LUAT_INPUT_KEY_GRAVE]='`', [LUAT_INPUT_KEY_BACKSLASH]='\\', [LUAT_INPUT_KEY_Z]='z',
        [LUAT_INPUT_KEY_X]='x', [LUAT_INPUT_KEY_C]='c',
        [LUAT_INPUT_KEY_V]='v', [LUAT_INPUT_KEY_B]='b', [LUAT_INPUT_KEY_N]='n', [LUAT_INPUT_KEY_M]='m',
        [LUAT_INPUT_KEY_COMMA]=',', [LUAT_INPUT_KEY_DOT]='.', [LUAT_INPUT_KEY_SLASH]='/', [LUAT_INPUT_KEY_KPASTERISK]='*',
        [LUAT_INPUT_KEY_SPACE]=' ',
        [LUAT_INPUT_KEY_KP7]='7', [LUAT_INPUT_KEY_KP8]='8', [LUAT_INPUT_KEY_KP9]='9', [LUAT_INPUT_KEY_KPMINUS]='-',
        [LUAT_INPUT_KEY_KP4]='4', [LUAT_INPUT_KEY_KP5]='5', [LUAT_INPUT_KEY_KP6]='6', [LUAT_INPUT_KEY_KPPLUS]='+',
        [LUAT_INPUT_KEY_KP1]='1', [LUAT_INPUT_KEY_KP2]='2', [LUAT_INPUT_KEY_KP3]='3', [LUAT_INPUT_KEY_KP0]='0',
        [LUAT_INPUT_KEY_KPDOT]='.'
    };
    static const char shifted_chars[128] = {
        [LUAT_INPUT_KEY_1]='!', [LUAT_INPUT_KEY_2]='@', [LUAT_INPUT_KEY_3]='#', [LUAT_INPUT_KEY_4]='$',
        [LUAT_INPUT_KEY_5]='%', [LUAT_INPUT_KEY_6]='^', [LUAT_INPUT_KEY_7]='&', [LUAT_INPUT_KEY_8]='*',
        [LUAT_INPUT_KEY_9]='(', [LUAT_INPUT_KEY_0]=')',
        [LUAT_INPUT_KEY_MINUS]='_', [LUAT_INPUT_KEY_EQUAL]='+', [LUAT_INPUT_KEY_LEFTBRACE]='{', [LUAT_INPUT_KEY_RIGHTBRACE]='}',
        [LUAT_INPUT_KEY_SEMICOLON]=':', [LUAT_INPUT_KEY_APOSTROPHE]='"', [LUAT_INPUT_KEY_GRAVE]='~', [LUAT_INPUT_KEY_BACKSLASH]='|',
        [LUAT_INPUT_KEY_COMMA]='<', [LUAT_INPUT_KEY_DOT]='>', [LUAT_INPUT_KEY_SLASH]='?'
    };
    unsigned char c = (unsigned char)plain[code < 128 ? code : 0];
    if (!c) return 0;
    if (c >= 'a' && c <= 'z') return shifted ? (uint32_t)(c - 'a' + 'A') : c;
    if (shifted && shifted_chars[code]) return (unsigned char)shifted_chars[code];
    return c;
}

static uint32_t lv_key(uint16_t code, bool shift, bool caps)
{
    switch (code) {
    case LUAT_INPUT_KEY_ESC: return LV_KEY_ESC;
    case LUAT_INPUT_KEY_BACKSPACE: return LV_KEY_BACKSPACE;
    case LUAT_INPUT_KEY_TAB: return shift ? LV_KEY_PREV : LV_KEY_NEXT;
    case LUAT_INPUT_KEY_ENTER: case LUAT_INPUT_KEY_KPENTER: return LV_KEY_ENTER;
    case LUAT_INPUT_KEY_HOME: return LV_KEY_HOME;
    case LUAT_INPUT_KEY_UP: return LV_KEY_UP;
    case LUAT_INPUT_KEY_PAGEUP: return LV_KEY_PREV;
    case LUAT_INPUT_KEY_LEFT: return LV_KEY_LEFT;
    case LUAT_INPUT_KEY_RIGHT: return LV_KEY_RIGHT;
    case LUAT_INPUT_KEY_END: return LV_KEY_END;
    case LUAT_INPUT_KEY_DOWN: return LV_KEY_DOWN;
    case LUAT_INPUT_KEY_PAGEDOWN: return LV_KEY_NEXT;
    case LUAT_INPUT_KEY_DELETE: return LV_KEY_DEL;
    default:
        if (code >= LUAT_INPUT_KEY_Q && code <= LUAT_INPUT_KEY_M && printable_key(code, false) >= 'a' && printable_key(code, false) <= 'z') {
            return printable_key(code, shift != caps);
        }
        return printable_key(code, shift);
    }
}

static void key_push(uint32_t device_id,
    uint16_t code, uint32_t key, lv_indev_state_t state)
{
    uint8_t next = (uint8_t)((g_key_tail + 1U) % AIRUI_HID_KEY_QUEUE);
    if (next == g_key_head) {
        /* Cancel on the LVGL thread: an overflow must never synthesize a click. */
        g_key_head = g_key_tail = 0;
        g_key_cancel = 1;
        next = (uint8_t)((g_key_tail + 1U) % AIRUI_HID_KEY_QUEUE);
    }
    g_keys[g_key_tail].device_id = device_id;
    g_keys[g_key_tail].key = key;
    g_keys[g_key_tail].code = code;
    g_keys[g_key_tail].state = state;
    g_key_tail = next;
}

static void device_reset(uint32_t id)
{
    airui_hid_device_t *dev = device_find(id, false);
    if (dev && dev->pointer) {
        g_pointer_head = g_pointer_tail = 0;
        g_pointer_cancel = 1;
    }
    if (dev) memset(dev, 0, sizeof(*dev));
    uint8_t read = g_key_head;
    uint8_t write = g_key_head;
    while (read != g_key_tail) {
        airui_hid_key_event_t event = g_keys[read];
        read = (uint8_t)((read + 1U) % AIRUI_HID_KEY_QUEUE);
        if (event.device_id == id) continue;
        g_keys[write] = event;
        write = (uint8_t)((write + 1U) % AIRUI_HID_KEY_QUEUE);
    }
    g_key_tail = write;
    if (g_last_key && g_last_key_device == id) {
        g_key_cancel = 1;
    }
}

static int32_t add_relative(int32_t current, int32_t delta)
{
    int64_t value = (int64_t)current + delta;
    if (value > INT32_MAX) return INT32_MAX;
    if (value < INT32_MIN) return INT32_MIN;
    return (int32_t)value;
}

static void pointer_push(airui_hid_pointer_event_t event)
{
    for (unsigned i = 0; i < AIRUI_HID_DEVICES; i++) event.pressed |= g_devices[i].left;
    if (g_pointer_head != g_pointer_tail) {
        unsigned last = (g_pointer_tail + AIRUI_HID_POINTER_QUEUE - 1U) % AIRUI_HID_POINTER_QUEUE;
        airui_hid_pointer_event_t *previous = &g_pointer_queue[last];
        if (previous->pressed == event.pressed) {
            previous->dx = add_relative(previous->dx, event.dx);
            previous->dy = add_relative(previous->dy, event.dy);
            previous->wheel = add_relative(previous->wheel, event.wheel);
            return;
        }
    }
    uint8_t next = (uint8_t)((g_pointer_tail + 1U) % AIRUI_HID_POINTER_QUEUE);
    if (next == g_pointer_head) {
        g_pointer_head = g_pointer_tail = 0;
        g_pointer_cancel = 1;
        next = 1;
    }
    g_pointer_queue[g_pointer_tail] = event;
    g_pointer_tail = next;
}

void luat_input_airui_receive(void *userdata,
    const luat_input_frame_t *frame, const luat_input_event_t *events)
{
    (void)userdata;
    if (!frame) return;

    uintptr_t token = bridge_lock();
    if (frame->flags & (LUAT_INPUT_FRAME_REMOVE | LUAT_INPUT_FRAME_RESET)) {
        device_reset(frame->device_id);
        bridge_unlock(token);
        return;
    }
    if (!events || !frame->count) {
        bridge_unlock(token);
        return;
    }

    airui_hid_device_t *dev = device_find(frame->device_id, true);
    if (!dev) {
        bridge_unlock(token);
        return;
    }
    airui_hid_pointer_event_t pointer = {0};
    bool pointer_changed = false;

    /* Resolve modifiers before normal presses, independent of HID parser order. */
    for (unsigned i = 0; i < frame->count; i++) {
        const luat_input_event_t *event = &events[i];
        if (event->type != LUAT_INPUT_EV_KEY) continue;
        if (event->code == LUAT_INPUT_KEY_LEFTSHIFT || event->code == LUAT_INPUT_KEY_RIGHTSHIFT) {
            uint8_t bit = event->code == LUAT_INPUT_KEY_LEFTSHIFT ? 1U : 2U;
            if (event->value) dev->shift |= bit; else dev->shift &= (uint8_t)~bit;
        } else if (event->code == LUAT_INPUT_KEY_CAPSLOCK && event->value == LUAT_INPUT_PRESS) {
            dev->caps ^= 1U;
        }
    }

    for (unsigned i = 0; i < frame->count; i++) {
        const luat_input_event_t *event = &events[i];
        if (event->type == LUAT_INPUT_EV_REL) {
            if (event->code == LUAT_INPUT_REL_X) pointer.dx = add_relative(pointer.dx, event->value);
            else if (event->code == LUAT_INPUT_REL_Y) pointer.dy = add_relative(pointer.dy, event->value);
            else if (event->code == LUAT_INPUT_REL_WHEEL) pointer.wheel = add_relative(pointer.wheel, event->value);
            else continue;
            pointer_changed = true;
            dev->pointer = 1;
            continue;
        }
        if (event->type != LUAT_INPUT_EV_KEY) continue;
        if (event->code == LUAT_INPUT_BTN_LEFT) {
            dev->left = event->value != LUAT_INPUT_RELEASE;
            dev->pointer = 1;
            pointer_changed = true;
            continue;
        }
        if (event->code >= 128 || is_modifier(event->code) || event->code == LUAT_INPUT_KEY_CAPSLOCK) continue;
        if (event->value == LUAT_INPUT_REPEAT) continue; /* LVGL owns repeat timing. */
        bool released = event->value == LUAT_INPUT_RELEASE;
        uint32_t key = released ? dev->pressed[event->code] :
            lv_key(event->code, dev->shift != 0, dev->caps != 0);
        dev->pressed[event->code] = released ? 0 : (uint8_t)key;
        if (key) key_push(frame->device_id, event->code, key,
            released ? LV_INDEV_STATE_RELEASED : LV_INDEV_STATE_PRESSED);
    }
    if (pointer_changed) pointer_push(pointer);
    bridge_unlock(token);
}

/* Run on the GUI thread. LVGL 9's pointer enc_diff path can synthesize a
 * RELEASED/CLICKED on the previously clicked, non-scrollable object. Scroll
 * the hovered object's nearest scrollable ancestor through public APIs instead.
 */
static void pointer_scroll(lv_indev_t *indev, lv_point_t point, int32_t wheel,
    int32_t width, int32_t height)
{
    if (!indev || !wheel) return;
    lv_display_t *display = lv_indev_get_display(indev);
    if (!display) return;
    lv_display_rotation_t rotation = lv_display_get_rotation(display);
    if (rotation == LV_DISPLAY_ROTATION_180 || rotation == LV_DISPLAY_ROTATION_270) {
        point.x = width - point.x - 1;
        point.y = height - point.y - 1;
    }
    if (rotation == LV_DISPLAY_ROTATION_90 || rotation == LV_DISPLAY_ROTATION_270) {
        int32_t x = point.x;
        point.x = point.y;
        point.y = height - x - 1;
    }
    lv_obj_t *layers[] = {lv_display_get_layer_sys(display),
        lv_display_get_layer_top(display), lv_display_get_screen_active(display),
        lv_display_get_layer_bottom(display)};
    lv_obj_t *obj = NULL;
    for (unsigned i = 0; i < sizeof(layers) / sizeof(layers[0]) && !obj; i++) {
        obj = lv_indev_search_obj(layers[i], &point);
    }
    for (; obj; obj = lv_obj_get_parent(obj)) {
        if (!lv_obj_has_flag(obj, LV_OBJ_FLAG_SCROLLABLE) ||
            !(lv_obj_get_scroll_dir(obj) & LV_DIR_VER)) continue;
        int32_t available = wheel > 0 ? lv_obj_get_scroll_top(obj) : lv_obj_get_scroll_bottom(obj);
        if (available <= 0) continue;
        int64_t pixels = (int64_t)wheel * 32;
        if (pixels > available) pixels = available;
        if (pixels < -(int64_t)available) pixels = -(int64_t)available;
        lv_obj_scroll_by_bounded(obj, 0, (int32_t)pixels, LV_ANIM_OFF);
        break;
    }
}

bool airui_input_hid_pointer_read(lv_indev_t *indev, int32_t width, int32_t height,
    lv_indev_data_t *data)
{
    if (!data || width <= 0 || height <= 0) return false;
    bool attached = false;
    uintptr_t token = bridge_lock();
    bool cancel = g_pointer_cancel != 0;
    g_pointer_cancel = 0;
    if (cancel) g_pointer_pressed = 0;
    airui_hid_pointer_event_t event = {0};
    for (unsigned i = 0; i < AIRUI_HID_DEVICES; i++) {
        airui_hid_device_t *dev = &g_devices[i];
        if (!dev->active || !dev->pointer) continue;
        attached = true;
    }
    if (!cancel && g_pointer_head != g_pointer_tail) {
        event = g_pointer_queue[g_pointer_head];
        g_pointer_head = (uint8_t)((g_pointer_head + 1U) % AIRUI_HID_POINTER_QUEUE);
        g_pointer_pressed = event.pressed;
    }
    if (attached || cancel) {
        if (!g_pointer_position_valid) {
            g_pointer_x = width / 2;
            g_pointer_y = height / 2;
            g_pointer_position_valid = 1;
        }
        int64_t x = (int64_t)g_pointer_x + event.dx;
        int64_t y = (int64_t)g_pointer_y + event.dy;
        if (x < 0) x = 0; else if (x >= width) x = width - 1;
        if (y < 0) y = 0; else if (y >= height) y = height - 1;
        g_pointer_x = (int32_t)x;
        g_pointer_y = (int32_t)y;
        data->point.x = (lv_coord_t)g_pointer_x;
        data->point.y = (lv_coord_t)g_pointer_y;
        data->state = g_pointer_pressed ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
        data->enc_diff = 0;
        /* Keep LVGL's clock: input timestamps can use a different epoch. */
        data->continue_reading = g_pointer_head != g_pointer_tail;
    }
    bridge_unlock(token);
    lv_obj_t *cursor = indev ? lv_indev_get_cursor(indev) : NULL;
    if (cursor) lv_obj_set_flag(cursor, LV_OBJ_FLAG_HIDDEN, !attached);
    if (cancel && indev) {
        lv_indev_reset(indev, NULL);
        lv_indev_wait_release(indev);
    }
    if (!cancel && data->state == LV_INDEV_STATE_RELEASED) {
        pointer_scroll(indev, data->point, event.wheel, width, height);
    }
    return attached || cancel;
}

bool airui_input_hid_keypad_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    if (!data) return false;
    bool ready = false;
    uintptr_t token = bridge_lock();
    bool cancel = g_key_cancel != 0;
    g_key_cancel = 0;
    if (cancel) {
        g_last_key = g_last_key_device = 0;
        data->state = LV_INDEV_STATE_RELEASED;
        ready = true;
    }
    while (!ready && g_key_head != g_key_tail) {
        airui_hid_key_event_t event = g_keys[g_key_head];
        /* LVGL keypad is a single active key. Release it before another press. */
        if (event.state == LV_INDEV_STATE_PRESSED && g_last_key) {
            data->key = g_last_key;
            data->state = LV_INDEV_STATE_RELEASED;
            g_last_key = g_last_key_device = 0;
            ready = true;
            break;
        }
        g_key_head = (uint8_t)((g_key_head + 1U) % AIRUI_HID_KEY_QUEUE);
        if (event.state == LV_INDEV_STATE_RELEASED &&
            (!g_last_key || event.device_id != g_last_key_device || event.code != g_last_key_code)) continue;
        data->key = event.key;
        data->state = event.state;
        data->continue_reading = g_key_head != g_key_tail;
        if (event.state == LV_INDEV_STATE_PRESSED) {
            g_last_key = event.key;
            g_last_key_device = event.device_id;
            g_last_key_code = event.code;
        } else if (g_last_key == event.key) {
            g_last_key = 0;
            g_last_key_device = 0;
        }
        ready = true;
    }
    if (!ready && g_last_key) {
        data->key = g_last_key;
        data->state = LV_INDEV_STATE_PRESSED;
        ready = true;
    }
    data->continue_reading = g_key_head != g_key_tail;
    bridge_unlock(token);
    if (cancel && indev) {
        lv_indev_reset(indev, NULL);
        /* lv_indev_reset alone does not clear keypad.last_state in LVGL 9. */
        lv_indev_wait_release(indev);
        lv_group_t *group = lv_indev_get_group(indev);
        lv_obj_t *focused = group ? lv_group_get_focused(group) : NULL;
        if (focused) lv_obj_remove_state(focused, LV_STATE_PRESSED);
    }
    return ready;
}

#endif
