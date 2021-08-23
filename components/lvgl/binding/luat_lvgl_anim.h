
#ifndef LUAT_LVGL_ANIM
#define LUAT_LVGL_ANIM

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_anim_create(lua_State *L);
int luat_lv_anim_free(lua_State *L);
int luat_lv_anim_path_t(lua_State *L);
int luat_lv_anim_path_t_free(lua_State *L);
int luat_lv_anim_set_path_str(lua_State *L);

#define LUAT_LV_ANIM_EX_RLT {"anim_create", luat_lv_anim_create, 0},\
{"anim_free", luat_lv_anim_free, 0},\
{"anim_path_t", luat_lv_anim_path_t, 0},\
{"anim_path_t_free", luat_lv_anim_path_t_free, 0},\
{"anim_set_path_str", luat_lv_anim_set_path_str, 0},\

#endif
