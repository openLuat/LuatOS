
#ifndef LUAT_LVGL_ANIM
#define LUAT_LVGL_ANIM

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_anim_create(lua_State *L);
int luat_lv_anim_free(lua_State *L);
int luat_lv_anim_path_t(lua_State *L);
int luat_lv_anim_path_t_free(lua_State *L);
int luat_lv_anim_set_path_str(lua_State *L);

#define LUAT_LV_ANIM_EX_RLT {"anim_create", ROREG_FUNC(luat_lv_anim_create)},\
{"anim_free", ROREG_FUNC(luat_lv_anim_free)},\
{"anim_path_t", ROREG_FUNC(luat_lv_anim_path_t)},\
{"anim_path_t_free", ROREG_FUNC(luat_lv_anim_path_t_free)},\
{"anim_set_path_str", ROREG_FUNC(luat_lv_anim_set_path_str)},\

#endif
