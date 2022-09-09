
#ifndef LUAT_LVGL_CANVAS_EX
#define LUAT_LVGL_CANVAS_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_canvas_set_buffer(lua_State *L);

#define LUAT_LV_CANVAS_EX_RLT {"canvas_set_buffer", ROREG_FUNC(luat_lv_canvas_set_buffer)},\

#endif