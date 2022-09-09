
#ifndef LUAT_LVGL_TILEVIEW_EX
#define LUAT_LVGL_TILEVIEW_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_tileview_set_valid_positions(lua_State *L);

#define LUAT_LV_TILEVIEW_EX_RLT {"tileview_set_valid_positions", ROREG_FUNC(luat_lv_tileview_set_valid_positions)},\

#endif