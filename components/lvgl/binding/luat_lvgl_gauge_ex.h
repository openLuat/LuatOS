
#ifndef LUAT_LVGL_GAUGE_EX
#define LUAT_LVGL_GAUGE_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_gauge_set_needle_count(lua_State *L);

#define LUAT_LV_GAUGE_EX_RLT {"gauge_set_needle_count", ROREG_FUNC(luat_lv_gauge_set_needle_count)},\

#endif