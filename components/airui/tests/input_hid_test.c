/* Runs against real LVGL 9 objects and input processing, without a display. */
#include "luat_airui_input_hid_luatos.h"
#include "luat_input_airui.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Exit normally on failure, avoiding a Windows crash-report dialog. */
#undef assert
#define assert(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); \
} } while (0)

static lv_indev_t *mouse, *keyboard;
static lv_obj_t *button, *textarea;
static lv_group_t *group;
static unsigned clicks;
static unsigned long_presses;

static void pointer_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    airui_input_hid_pointer_read(indev, 800, 480, data);
}

static void keypad_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    airui_input_hid_keypad_read(indev, data);
}

static void clicked(lv_event_t *event)
{
    (void)event;
    clicks++;
}

static void long_pressed(lv_event_t *event)
{
    (void)event;
    long_presses++;
}

static void send_events(uint32_t id, const luat_input_event_t *events, uint16_t count)
{
    lv_tick_inc(1);
    /* Device uptime and LVGL ticks need not share an epoch. */
    luat_input_frame_t frame = {id, 0, lv_tick_get() + 600000U, count, 0};
    luat_input_airui_receive(NULL, &frame, events);
}

static void key(uint16_t code, int value)
{
    luat_input_event_t event = {LUAT_INPUT_EV_KEY, code, value};
    send_events(2, &event, 1);
}

static void remove_device(uint32_t id)
{
    luat_input_frame_t frame = {id, 0, lv_tick_get(), 0,
        LUAT_INPUT_FRAME_REMOVE | LUAT_INPUT_FRAME_RESET};
    luat_input_airui_receive(NULL, &frame, NULL);
}

int main(void)
{
    lv_init();
    lv_display_t *display = lv_display_create(800, 480);
    assert(display);
    lv_timer_pause(lv_display_get_refr_timer(display));
    button = lv_button_create(lv_screen_active());
    lv_obj_set_pos(button, 300, 180);
    lv_obj_set_size(button, 200, 120);
    lv_obj_add_event_cb(button, clicked, LV_EVENT_CLICKED, NULL);
    lv_obj_add_event_cb(button, long_pressed, LV_EVENT_LONG_PRESSED, NULL);
    textarea = lv_textarea_create(lv_screen_active());
    lv_obj_set_pos(textarea, 20, 20);
    lv_obj_set_size(textarea, 250, 100);
    lv_textarea_set_text(textarea, "");
    group = lv_group_create();
    lv_group_add_obj(group, textarea);
    lv_group_add_obj(group, button);
    mouse = lv_indev_create();
    keyboard = lv_indev_create();
    assert(mouse && keyboard && group);
    lv_indev_set_type(mouse, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(mouse, pointer_read);
    lv_indev_set_type(keyboard, LV_INDEV_TYPE_KEYPAD);
    lv_indev_set_read_cb(keyboard, keypad_read);
    lv_indev_set_group(keyboard, group);
    lv_obj_update_layout(lv_screen_active());

    /* Both edges arrive before a single LVGL read: must still click exactly once. */
    luat_input_event_t left = {LUAT_INPUT_EV_KEY, LUAT_INPUT_BTN_LEFT, 1};
    send_events(1, &left, 1);
    left.value = 0;
    send_events(1, &left, 1);
    lv_indev_read(mouse);
    assert(clicks == 1);

    /* A wheel over a non-scrollable button must never replay its click. */
    luat_input_event_t wheel = {LUAT_INPUT_EV_REL, LUAT_INPUT_REL_WHEEL, -1};
    for (unsigned i = 0; i < 4; i++) {
        send_events(1, &wheel, 1);
        lv_indev_read(mouse);
    }
    assert(clicks == 1);

    /* Scrolling targets the object under the cursor and does not require a click. */
    lv_obj_t *panel = lv_obj_create(lv_screen_active());
    lv_obj_set_pos(panel, 500, 20);
    lv_obj_set_size(panel, 200, 100);
    lv_obj_t *content = lv_obj_create(panel);
    lv_obj_set_size(content, 100, 400);
    lv_obj_update_layout(panel);
    luat_input_event_t move[] = {{LUAT_INPUT_EV_REL, LUAT_INPUT_REL_X, 150},
        {LUAT_INPUT_EV_REL, LUAT_INPUT_REL_Y, -180}};
    send_events(1, move, 2);
    send_events(1, &wheel, 1);
    lv_indev_read(mouse);
    assert(lv_obj_get_scroll_y(panel) > 0 && clicks == 1);
    wheel.value = 1;
    send_events(1, &wheel, 1);
    lv_indev_read(mouse);
    assert(lv_obj_get_scroll_y(panel) == 0);
    move[0].value = -150; move[1].value = 180;
    send_events(1, move, 2);
    lv_indev_read(mouse);

    /* A held mouse must remain pressed across empty polls; removal cancels. */
    left.value = 1;
    send_events(1, &left, 1);
    lv_indev_read(mouse);
    lv_tick_inc(20);
    lv_indev_read(mouse);
    assert(lv_indev_get_state(mouse) == LV_INDEV_STATE_PRESSED);
    assert(long_presses == 0);
    remove_device(1);
    lv_indev_read(mouse);
    assert(lv_indev_get_state(mouse) == LV_INDEV_STATE_RELEASED && clicks == 1);

    lv_group_focus_obj(textarea);
    luat_input_event_t shift_a[] = {{LUAT_INPUT_EV_KEY, 30, 1}, {LUAT_INPUT_EV_KEY, 42, 1}};
    send_events(2, shift_a, 2);
    lv_indev_read(keyboard);
    assert(!strcmp(lv_textarea_get_text(textarea), "A"));
    lv_indev_read(keyboard);
    assert(lv_indev_get_state(keyboard) == LV_INDEV_STATE_PRESSED);
    /* Shift can be released in an earlier report than the letter. */
    key(42, 0);
    key(30, 0);
    lv_indev_read(keyboard);
    assert(lv_indev_get_state(keyboard) == LV_INDEV_STATE_RELEASED);

    /* Overlapping ordinary keys must both reach the textarea. */
    key(48, 1);
    key(46, 1);
    lv_indev_read(keyboard);
    assert(!strcmp(lv_textarea_get_text(textarea), "Abc"));
    key(48, 0);
    lv_indev_read(keyboard);
    assert(lv_indev_get_state(keyboard) == LV_INDEV_STATE_PRESSED);
    key(46, 0);
    lv_indev_read(keyboard);

    key(14, 1); key(14, 0);
    lv_indev_read(keyboard);
    assert(!strcmp(lv_textarea_get_text(textarea), "Ab"));

    key(15, 1); key(15, 0);
    lv_indev_read(keyboard);
    assert(lv_group_get_focused(group) == button);
    key(28, 1); key(28, 0);
    lv_indev_read(keyboard);
    assert(clicks == 2);
    key(28, 1);
    lv_indev_read(keyboard);
    lv_tick_inc(20);
    lv_indev_read(keyboard);
    assert(long_presses == 0);
    lv_tick_inc(500);
    lv_indev_read(keyboard);
    assert(long_presses == 1);
    remove_device(2);
    lv_indev_read(keyboard);
    assert(clicks == 2); /* Unplug must not become an Enter click. */

    /* Overflow during a held Enter cancels it without clicking the button. */
    key(28, 1);
    lv_indev_read(keyboard);
    for (unsigned i = 0; i < 40; i++) key(30, i & 1U);
    lv_indev_read(keyboard);
    assert(clicks == 2);
    remove_device(2);
    lv_indev_read(keyboard);

    lv_indev_delete(mouse);
    lv_indev_delete(keyboard);
    lv_group_delete(group);
    lv_display_delete(display);
    puts("LVGL HID tests PASS: click, wheel, scroll, hold, clock, text, Shift, Backspace, overlap, Tab, Enter, unplug, overflow");
    return 0;
}
