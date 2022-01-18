
#ifndef LUAT_LVGL_BTNMATRIX_EX
#define LUAT_LVGL_BTNMATRIX_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_btnmatrix_set_map(lua_State *L);

#define LUAT_LV_BTNMATRIX_EX_RLT {"btnmatrix_set_map", luat_lv_btnmatrix_set_map, 0},\

#endif