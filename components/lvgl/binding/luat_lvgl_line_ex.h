
#ifndef LUAT_LVGL_LINE_EX
#define LUAT_LVGL_LINE_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_line_set_points(lua_State *L);

#define LUAT_LV_LINE_EX_RLT {"line_set_points", ROREG_FUNC(luat_lv_line_set_points)},\

#endif