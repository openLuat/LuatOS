#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"

int luat_lv_imgbtn_set_src(lua_State *L);

#define LUAT_LV_IMGBTN_EX_RTL {"imgbtn_set_src", ROREG_FUNC(luat_lv_imgbtn_set_src)},\


