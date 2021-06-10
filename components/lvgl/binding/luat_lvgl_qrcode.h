
#ifndef LUAT_LVGL_QRCODE
#define LUAT_LVGL_QRCODE

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_qrcode_create(lua_State *L);
int luat_lv_qrcode_update(lua_State *L);
int luat_lv_qrcode_delete(lua_State *L);

#define LUAT_LV_QRCODE_RLT {"qrcode_create", luat_lv_qrcode_create, 0},\
{"qrcode_update", luat_lv_qrcode_update, 0},\
{"qrcode_delete", luat_lv_qrcode_delete, 0},\

#endif
