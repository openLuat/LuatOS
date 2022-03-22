
#ifndef LUAT_LVGL_MAP
#define LUAT_LVGL_MAP

#include "luat_base.h"
#include "lvgl.h"

#if LV_USE_CHART
int luat_lv_chart_set_range(lua_State *L);
int luat_lv_chart_clear_serie(lua_State *L);
#endif
int luat_lv_obj_align_origo(lua_State *L);
int luat_lv_obj_align_origo_x(lua_State *L);
int luat_lv_obj_align_origo_y(lua_State *L);
int luat_lv_win_add_btn(lua_State *L);

#define LUAT_LV_MAP_RLT {"obj_align_origo", ROREG_FUNC(luat_lv_obj_align_origo)},\
{"obj_align_origo_x", ROREG_FUNC(luat_lv_obj_align_origo_x)},\
{"obj_align_origo_y", ROREG_FUNC(luat_lv_obj_align_origo_y)},\
{"chart_set_range", ROREG_FUNC(luat_lv_chart_set_range)},\
{"chart_clear_serie", ROREG_FUNC(luat_lv_chart_clear_serie)},\
{"win_add_btn", ROREG_FUNC(luat_lv_win_add_btn)},\

#endif