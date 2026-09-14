/** @file luat_input_airui.h
 * Input-core consumer used by the LuatOS AirUI/LVGL platform adapter.
 */
#ifndef LUAT_INPUT_AIRUI_H
#define LUAT_INPUT_AIRUI_H

#include "luat_input.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef uintptr_t (*luat_input_airui_lock_t)(void *userdata);
typedef void (*luat_input_airui_unlock_t)(void *userdata, uintptr_t token);

/** Configure the short critical section shared by producers and LVGL reads.
 * Call once before binding devices. A null pair means externally serialized.
 */
void luat_input_airui_set_lock(luat_input_airui_lock_t lock,
    luat_input_airui_unlock_t unlock, void *userdata);

/** Bind this callback to an input device. It copies only compact pointer/key
 * state; LVGL is called later from its own input read callback.
 */
void luat_input_airui_receive(void *userdata,
    const luat_input_frame_t *frame, const luat_input_event_t *events);

#ifdef __cplusplus
}
#endif
#endif
