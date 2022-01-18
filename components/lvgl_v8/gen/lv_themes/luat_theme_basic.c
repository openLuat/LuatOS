
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_theme_t* lv_theme_basic_init(lv_disp_t* disp)
int luat_lv_theme_basic_init(lua_State *L) {
    LV_DEBUG("CALL lv_theme_basic_init");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_theme_t* ret = NULL;
    ret = lv_theme_basic_init(disp);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

