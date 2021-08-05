
#ifndef LUAT_LVGL_WIDGETS_EX
#define LUAT_LVGL_WIDGETS_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_msgbox_add_btns(lua_State *L);
int luat_lv_tileview_set_valid_positions(lua_State *L);

#define LUAT_LV_WIDGETS_EX_RLT {"msgbox_add_btns", luat_lv_msgbox_add_btns, 0},\
{"tileview_set_valid_positions", luat_lv_tileview_set_valid_positions, 0},\

#endif