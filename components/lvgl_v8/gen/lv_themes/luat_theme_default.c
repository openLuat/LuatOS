
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_theme_t* lv_theme_default_init(lv_disp_t* disp, lv_color_t color_primary, lv_color_t color_secondary, bool dark, lv_font_t* font)
int luat_lv_theme_default_init(lua_State *L) {
    LV_DEBUG("CALL lv_theme_default_init");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_color_t color_primary = {0};
    color_primary.full = luaL_checkinteger(L, 2);
    lv_color_t color_secondary = {0};
    color_secondary.full = luaL_checkinteger(L, 3);
    bool dark = (bool)lua_toboolean(L, 4);
    lv_font_t* font = (lv_font_t*)lua_touserdata(L, 5);
    lv_theme_t* ret = NULL;
    ret = lv_theme_default_init(disp ,color_primary ,color_secondary ,dark ,font);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_theme_t* lv_theme_default_get()
int luat_lv_theme_default_get(lua_State *L) {
    LV_DEBUG("CALL lv_theme_default_get");
    lv_theme_t* ret = NULL;
    ret = lv_theme_default_get();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  bool lv_theme_default_is_inited()
int luat_lv_theme_default_is_inited(lua_State *L) {
    LV_DEBUG("CALL lv_theme_default_is_inited");
    bool ret;
    ret = lv_theme_default_is_inited();
    lua_pushboolean(L, ret);
    return 1;
}

