
#ifndef LUAT_LVGL_STYLE
#define LUAT_LVGL_STYLE

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_style_t(lua_State *L);
int luat_lv_style_create(lua_State *L);
int luat_lv_style_list_create(lua_State *L);
int luat_lv_style_delete(lua_State *L);
int luat_lv_style_list_delete(lua_State *L);
int luat_lv_style_set_transition_path(lua_State *L);

#define LUAT_LV_STYLE2_RLT {"style_t", ROREG_FUNC(luat_lv_style_t)},\
{"style_create", ROREG_FUNC(luat_lv_style_create)},\
{"style_list_create", ROREG_FUNC(luat_lv_style_list_create)},\
{"style_list_t", ROREG_FUNC(luat_lv_style_list_create)},\
{"style_delete", ROREG_FUNC(luat_lv_style_delete)},\
{"style_list_delete", ROREG_FUNC(luat_lv_style_list_delete)},\
{"style_set_transition_path", ROREG_FUNC(luat_lv_style_set_transition_path)},\

#endif
