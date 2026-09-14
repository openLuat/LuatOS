#ifndef LUAT_AIRUI_INPUT_HID_LUATOS_H
#define LUAT_AIRUI_INPUT_HID_LUATOS_H

#include "lvgl9/lvgl.h"

/* Slots 0 and 1 are reserved for the existing touch input. */
#define AIRUI_HID_POINTER_SLOT 2U

/** Return true while at least one input-core pointer is attached. */
bool airui_input_hid_pointer_read(lv_indev_t *indev, int32_t width, int32_t height,
    lv_indev_data_t *data);

/** Pop one translated input-core keyboard event. */
bool airui_input_hid_keypad_read(lv_indev_t *indev, lv_indev_data_t *data);

#endif
