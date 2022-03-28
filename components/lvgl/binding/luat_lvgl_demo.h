
#ifndef LUAT_LVGL_DEMO
#define LUAT_LVGL_DEMO

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_demo(lua_State *L);

#define LUAT_LV_DEMO_RLT {"demo", ROREG_FUNC(luat_lv_demo)},\

#endif
