
#ifndef LUAT_LVGL_CB
#define LUAT_LVGL_CB

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_obj_set_event_cb(lua_State *L);
int luat_lv_obj_set_signal_cb(lua_State *L);
int luat_lv_event_send(lua_State *L);
int luat_lv_keyboard_def_event_cb(lua_State *L);
int luat_lv_anim_set_exec_cb(lua_State *L);
int luat_lv_anim_set_ready_cb(lua_State *L);
int luat_lv_anim_path_set_cb(lua_State *L);

#define LUAT_LV_CB_RLT {"obj_set_event_cb", ROREG_FUNC(luat_lv_obj_set_event_cb)},\
{"obj_set_signal_cb", ROREG_FUNC(luat_lv_obj_set_signal_cb)},\
{"event_send", ROREG_FUNC(luat_lv_event_send)},\
{"keyboard_def_event_cb", ROREG_FUNC(luat_lv_keyboard_def_event_cb)},\
{"anim_set_exec_cb", ROREG_FUNC(luat_lv_anim_set_exec_cb)},\
{"anim_set_ready_cb", ROREG_FUNC(luat_lv_anim_set_ready_cb)},\
{"anim_path_set_cb", ROREG_FUNC(luat_lv_anim_path_set_cb)},\

#endif
