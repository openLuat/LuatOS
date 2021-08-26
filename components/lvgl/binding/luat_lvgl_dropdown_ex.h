
#ifndef LUAT_LVGL_DROPDOWN_EX
#define LUAT_LVGL_DROPDOWN_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_dropdown_get_selected_str(lua_State *L);
int luat_lv_dropdown_set_symbol(lua_State *L);

#define LUAT_LV_DROPDOWN_EX_RLT {"dropdown_get_selected_str", luat_lv_dropdown_get_selected_str, 0},\
{"dropdown_set_symbol", luat_lv_dropdown_set_symbol, 0},\

#endif