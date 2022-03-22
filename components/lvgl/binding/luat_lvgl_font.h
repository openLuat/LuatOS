#include "luat_base.h"
#include "luat_msgbus.h"
#include "lvgl.h"

int luat_lv_font_get(lua_State *L);
int luat_lv_font_load(lua_State *L);
int luat_lv_font_free(lua_State *L);

#define LUAT_LV_FONT_EX_RLT {"font_get", ROREG_FUNC(luat_lv_font_get)},\
{"font_load", ROREG_FUNC(luat_lv_font_load)},\
{"font_free", ROREG_FUNC(luat_lv_font_free)},\

