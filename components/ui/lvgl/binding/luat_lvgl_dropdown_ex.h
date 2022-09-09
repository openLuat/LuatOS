
#ifndef LUAT_LVGL_DROPDOWN_EX
#define LUAT_LVGL_DROPDOWN_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_dropdown_get_selected_str(lua_State *L);
int luat_lv_dropdown_set_symbol(lua_State *L);

#define LUAT_LV_DROPDOWN_EX_RLT {"dropdown_get_selected_str", ROREG_FUNC(luat_lv_dropdown_get_selected_str)},\
{"dropdown_set_symbol", ROREG_FUNC(luat_lv_dropdown_set_symbol)},\

#endif