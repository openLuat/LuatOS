
#ifndef LUAT_LVGL_CB
#define LUAT_LVGL_CB

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_obj_set_event_cb(lua_State *L);

#define LUAT_LV_CB_RLT {"obj_set_event_cb", luat_lv_obj_set_event_cb, 0},

#endif
