
#ifndef LUAT_LVGL_CB
#define LUAT_LVGL_CB

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_obj_set_event_cb(lua_State *L);
int luat_lv_obj_set_signal_cb(lua_State *L);
int luat_lv_anim_set_exec_cb(lua_State *L);
int luat_lv_anim_set_ready_cb(lua_State *L);

#define LUAT_LV_CB_RLT {"obj_set_event_cb", luat_lv_obj_set_event_cb, 0},\
{"obj_set_signal_cb", luat_lv_obj_set_signal_cb, 0},\
{"anim_set_exec_cb", luat_lv_anim_set_exec_cb, 0},\
{"anim_set_ready_cb", luat_lv_anim_set_ready_cb, 0},\

#endif
