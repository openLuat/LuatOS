
#ifndef LUAT_LVGL_ROLLER_EX
#define LUAT_LVGL_ROLLER_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_roller_get_selected_str(lua_State *L);

#define LUAT_LV_ROLLER_EX_RLT {"roller_get_selected_str", ROREG_FUNC(luat_lv_roller_get_selected_str)},\

#endif