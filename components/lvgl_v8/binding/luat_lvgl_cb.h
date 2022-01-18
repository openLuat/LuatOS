
#ifndef LUAT_LVGL_CB
#define LUAT_LVGL_CB

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_obj_add_event_cb(lua_State *L);
int luat_lv_obj_remove_event_cb(lua_State *L);
int luat_lv_obj_remove_event_cb_with_user_data(lua_State *L);
int luat_lv_keyboard_def_event_cb(lua_State *L);
int luat_lv_anim_set_exec_cb(lua_State *L);
int luat_lv_anim_set_ready_cb(lua_State *L);

#define LUAT_LV_CB_RLT {"obj_add_event_cb", luat_lv_obj_add_event_cb, 0},\
{"obj_remove_event_cb", luat_lv_obj_remove_event_cb, 0},\
{"obj_remove_event_cb_with_user_data", luat_lv_obj_remove_event_cb_with_user_data, 0},\
{"keyboard_def_event_cb", luat_lv_keyboard_def_event_cb, 0},\
{"anim_set_exec_cb", luat_lv_anim_set_exec_cb, 0},\
{"anim_set_ready_cb", luat_lv_anim_set_ready_cb, 0},\

#endif
