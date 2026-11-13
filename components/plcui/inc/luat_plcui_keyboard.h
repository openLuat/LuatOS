/** @file luat_plcui_keyboard.h Native keyboard composition lifecycle. */
#ifndef LUAT_PLCUI_KEYBOARD_H
#define LUAT_PLCUI_KEYBOARD_H
#include "luat_plcui.h"

bool luat_plcui_keyboard_validate(const plcui_widget_t *widget, plcui_error_t *error);
void luat_plcui_keyboard_reset(plcui_widget_t *widget);
void luat_plcui_keyboard_font_changed(plcui_widget_t *widget);

#endif
