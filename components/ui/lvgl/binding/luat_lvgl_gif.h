
#ifndef LUAT_LVGL_GIF
#define LUAT_LVGL_GIF

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_gif_create(lua_State *L);
int luat_lv_gif_restart(lua_State *L);
int luat_lv_gif_delete(lua_State *L);

#define LUAT_LV_GIF_RLT {"gif_create", ROREG_FUNC(luat_lv_gif_create)},\
{"gif_restart", ROREG_FUNC(luat_lv_gif_restart)},\

#endif
