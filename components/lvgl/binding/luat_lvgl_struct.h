
#ifndef LUAT_LVGL_STRUCT
#define LUAT_LVGL_STRUCT

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_struct_anim_t(lua_State *L);
int luat_lv_struct_area_t(lua_State *L);

#define LUAT_LV_STRUCT_RLT {"anim_t", luat_lv_struct_anim_t, 0},\
{"area_t", luat_lv_struct_area_t, 0},

#endif
