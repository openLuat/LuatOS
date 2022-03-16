
#ifndef LUAT_LVGL_INDEV
#define LUAT_LVGL_INDEV

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_indev_drv_register(lua_State *L);
int luat_lv_indev_point_emulator_update(lua_State *L);
int luat_lv_indev_keyboard_update(lua_State *L);

#define LUAT_LV_INDEV_RLT {"indev_drv_register", luat_lv_indev_drv_register, 0},\
{"indev_point_emulator_update", luat_lv_indev_point_emulator_update, 0},\
{"indev_kb_update", luat_lv_indev_keyboard_update, 0},\

#endif
