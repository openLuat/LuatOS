
#ifndef LUAT_LVGL_STRUCT
#define LUAT_LVGL_STRUCT

#include "luat_base.h"
#include "lvgl.h"

void luat_lvgl_struct_init(lua_State *L);

int luat_lv_struct_anim_t(lua_State *L);
int luat_lv_struct_area_t(lua_State *L);
int luat_lv_calendar_date_t(lua_State *L);
int luat_lv_draw_rect_dsc_t(lua_State *L);

#define LUAT_LV_STRUCT_RLT {"anim_t", luat_lv_struct_anim_t, 0},\
{"area_t", luat_lv_struct_area_t, 0},\
{"calendar_date_t", luat_lv_calendar_date_t, 0},\
{"draw_rect_dsc_t", luat_lv_draw_rect_dsc_t, 0},\

#endif
