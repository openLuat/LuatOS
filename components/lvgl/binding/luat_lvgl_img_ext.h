#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"

int luat_lv_img_set_src(lua_State *L);

#define LUAT_LV_IMG_EX_RTL {"img_set_src", ROREG_FUNC(luat_lv_img_set_src)},\


