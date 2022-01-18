
#ifndef LUAT_LVGL_MAP
#define LUAT_LVGL_MAP

#include "luat_base.h"
#include "lvgl.h"

#if LV_USE_CHART
int luat_lv_chart_clear_serie(lua_State *L);
#endif
int luat_lv_obj_align_origo(lua_State *L);
int luat_lv_obj_align_origo_x(lua_State *L);
int luat_lv_obj_align_origo_y(lua_State *L);
int luat_lv_win_add_btn(lua_State *L);

#define LUAT_LV_MAP_RLT {"obj_align_origo", luat_lv_obj_align_origo, 0},\
{"obj_align_origo_x", luat_lv_obj_align_origo_x, 0},\
{"obj_align_origo_y", luat_lv_obj_align_origo_y, 0},\
{"chart_clear_serie", luat_lv_chart_clear_serie, 0},\
{"win_add_btn", luat_lv_win_add_btn, 0},\

#endif