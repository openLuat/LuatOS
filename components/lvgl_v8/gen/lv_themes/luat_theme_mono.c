
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_theme_t* lv_theme_mono_init(lv_disp_t* disp, bool dark_bg, lv_font_t* font)
int luat_lv_theme_mono_init(lua_State *L) {
    LV_DEBUG("CALL lv_theme_mono_init");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    bool dark_bg = (bool)lua_toboolean(L, 2);
    lv_font_t* font = (lv_font_t*)lua_touserdata(L, 3);
    lv_theme_t* ret = NULL;
    ret = lv_theme_mono_init(disp ,dark_bg ,font);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

