
#ifndef LUAT_LVGL_MSGBOX_EX
#define LUAT_LVGL_MSGBOX_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_msgbox_add_btns(lua_State *L);

#define LUAT_LV_MSGBOX_EX_RLT {"msgbox_add_btns", ROREG_FUNC(luat_lv_msgbox_add_btns)},\

#endif