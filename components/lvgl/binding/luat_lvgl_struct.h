#ifndef LUAT_LVGL_STRUCT
#define LUAT_LVGL_STRUCT

#include "luat_base.h"
#include "lvgl.h"

void luat_lvgl_struct_init(lua_State *L);

int luat_lv_struct_anim_t(lua_State *L);
int luat_lv_struct_area_t(lua_State *L);
int luat_lv_calendar_date_t(lua_State *L);
int luat_lv_draw_rect_dsc_t(lua_State *L);
int luat_lv_draw_label_dsc_t(lua_State *L);
int luat_lv_draw_img_dsc_t(lua_State *L);
int luat_lv_img_dsc_t(lua_State *L);
int luat_lv_draw_line_dsc_t(lua_State *L);

#define LUAT_LV_STRUCT_RLT {"anim_t", ROREG_FUNC(luat_lv_struct_anim_t)},\
{"area_t", ROREG_FUNC(luat_lv_struct_area_t)},\
{"calendar_date_t", ROREG_FUNC(luat_lv_calendar_date_t)},\
{"draw_rect_dsc_t", ROREG_FUNC(luat_lv_draw_rect_dsc_t)},\
{"draw_label_dsc_t", ROREG_FUNC(luat_lv_draw_label_dsc_t)},\
{"draw_img_dsc_t", ROREG_FUNC(luat_lv_draw_img_dsc_t)},\
{"img_dsc_t", ROREG_FUNC(luat_lv_img_dsc_t)},\
{"draw_line_dsc_t", ROREG_FUNC(luat_lv_draw_line_dsc_t)},\

#endif
