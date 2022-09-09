
#ifndef LUAT_LVGL_INDEV
#define LUAT_LVGL_INDEV

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_indev_drv_register(lua_State *L);
int luat_lv_indev_point_emulator_update(lua_State *L);
int luat_lv_indev_keyboard_update(lua_State *L);

#define LUAT_LV_INDEV_RLT {"indev_drv_register", ROREG_FUNC(luat_lv_indev_drv_register)},\
{"indev_point_emulator_update", ROREG_FUNC(luat_lv_indev_point_emulator_update)},\
{"indev_kb_update", ROREG_FUNC(luat_lv_indev_keyboard_update)},\

#endif
