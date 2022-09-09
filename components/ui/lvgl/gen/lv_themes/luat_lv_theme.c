

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_theme_set_act(lv_theme_t* th)
int luat_lv_theme_set_act(lua_State *L) {
    LV_DEBUG("CALL lv_theme_set_act");
    lv_theme_t* th = (lv_theme_t*)lua_touserdata(L, 1);
    lv_theme_set_act(th);
    return 0;
}

//  lv_theme_t* lv_theme_get_act()
int luat_lv_theme_get_act(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_act");
    lv_theme_t* ret = NULL;
    ret = lv_theme_get_act();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_theme_apply(lv_obj_t* obj, lv_theme_style_t name)
int luat_lv_theme_apply(lua_State *L) {
    LV_DEBUG("CALL lv_theme_apply");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_theme_style_t name = luaL_checkinteger(L, 2);
    // miss arg convert
    lv_theme_apply(obj ,name);
    return 0;
}

//  void lv_theme_copy(lv_theme_t* theme, lv_theme_t* copy)
int luat_lv_theme_copy(lua_State *L) {
    LV_DEBUG("CALL lv_theme_copy");
    lv_theme_t* theme = (lv_theme_t*)lua_touserdata(L, 1);
    lv_theme_t* copy = (lv_theme_t*)lua_touserdata(L, 2);
    lv_theme_copy(theme ,copy);
    return 0;
}

//  void lv_theme_set_base(lv_theme_t* new_theme, lv_theme_t* base)
int luat_lv_theme_set_base(lua_State *L) {
    LV_DEBUG("CALL lv_theme_set_base");
    lv_theme_t* new_theme = (lv_theme_t*)lua_touserdata(L, 1);
    lv_theme_t* base = (lv_theme_t*)lua_touserdata(L, 2);
    lv_theme_set_base(new_theme ,base);
    return 0;
}

//  lv_font_t* lv_theme_get_font_small()
int luat_lv_theme_get_font_small(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_font_small");
    lv_font_t* ret = NULL;
    ret = lv_theme_get_font_small();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_font_t* lv_theme_get_font_normal()
int luat_lv_theme_get_font_normal(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_font_normal");
    lv_font_t* ret = NULL;
    ret = lv_theme_get_font_normal();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_font_t* lv_theme_get_font_subtitle()
int luat_lv_theme_get_font_subtitle(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_font_subtitle");
    lv_font_t* ret = NULL;
    ret = lv_theme_get_font_subtitle();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_font_t* lv_theme_get_font_title()
int luat_lv_theme_get_font_title(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_font_title");
    lv_font_t* ret = NULL;
    ret = lv_theme_get_font_title();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_color_t lv_theme_get_color_primary()
int luat_lv_theme_get_color_primary(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_color_primary");
    lv_color_t ret;
    ret = lv_theme_get_color_primary();
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_theme_get_color_secondary()
int luat_lv_theme_get_color_secondary(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_color_secondary");
    lv_color_t ret;
    ret = lv_theme_get_color_secondary();
    lua_pushinteger(L, ret.full);
    return 1;
}

//  uint32_t lv_theme_get_flags()
int luat_lv_theme_get_flags(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_flags");
    uint32_t ret;
    ret = lv_theme_get_flags();
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_theme_t* lv_theme_empty_init(lv_color_t color_primary, lv_color_t color_secondary, uint32_t flags, lv_font_t* font_small, lv_font_t* font_normal, lv_font_t* font_subtitle, lv_font_t* font_title)
int luat_lv_theme_empty_init(lua_State *L) {
    LV_DEBUG("CALL lv_theme_empty_init");
    lv_color_t color_primary = {0};
    color_primary.full = luaL_checkinteger(L, 1);
    lv_color_t color_secondary = {0};
    color_secondary.full = luaL_checkinteger(L, 2);
    uint32_t flags = (uint32_t)luaL_checkinteger(L, 3);
    lv_font_t* font_small = (lv_font_t*)lua_touserdata(L, 4);
    lv_font_t* font_normal = (lv_font_t*)lua_touserdata(L, 5);
    lv_font_t* font_subtitle = (lv_font_t*)lua_touserdata(L, 6);
    lv_font_t* font_title = (lv_font_t*)lua_touserdata(L, 7);
    lv_theme_t* ret = NULL;
    ret = lv_theme_empty_init(color_primary ,color_secondary ,flags ,font_small ,font_normal ,font_subtitle ,font_title);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_theme_t* lv_theme_template_init(lv_color_t color_primary, lv_color_t color_secondary, uint32_t flags, lv_font_t* font_small, lv_font_t* font_normal, lv_font_t* font_subtitle, lv_font_t* font_title)
int luat_lv_theme_template_init(lua_State *L) {
    LV_DEBUG("CALL lv_theme_template_init");
    lv_color_t color_primary = {0};
    color_primary.full = luaL_checkinteger(L, 1);
    lv_color_t color_secondary = {0};
    color_secondary.full = luaL_checkinteger(L, 2);
    uint32_t flags = (uint32_t)luaL_checkinteger(L, 3);
    lv_font_t* font_small = (lv_font_t*)lua_touserdata(L, 4);
    lv_font_t* font_normal = (lv_font_t*)lua_touserdata(L, 5);
    lv_font_t* font_subtitle = (lv_font_t*)lua_touserdata(L, 6);
    lv_font_t* font_title = (lv_font_t*)lua_touserdata(L, 7);
    lv_theme_t* ret = NULL;
    ret = lv_theme_template_init(color_primary ,color_secondary ,flags ,font_small ,font_normal ,font_subtitle ,font_title);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_theme_t* lv_theme_material_init(lv_color_t color_primary, lv_color_t color_secondary, uint32_t flags, lv_font_t* font_small, lv_font_t* font_normal, lv_font_t* font_subtitle, lv_font_t* font_title)
int luat_lv_theme_material_init(lua_State *L) {
    LV_DEBUG("CALL lv_theme_material_init");
    lv_color_t color_primary = {0};
    color_primary.full = luaL_checkinteger(L, 1);
    lv_color_t color_secondary = {0};
    color_secondary.full = luaL_checkinteger(L, 2);
    uint32_t flags = (uint32_t)luaL_checkinteger(L, 3);
    lv_font_t* font_small = (lv_font_t*)lua_touserdata(L, 4);
    lv_font_t* font_normal = (lv_font_t*)lua_touserdata(L, 5);
    lv_font_t* font_subtitle = (lv_font_t*)lua_touserdata(L, 6);
    lv_font_t* font_title = (lv_font_t*)lua_touserdata(L, 7);
    lv_theme_t* ret = NULL;
    ret = lv_theme_material_init(color_primary ,color_secondary ,flags ,font_small ,font_normal ,font_subtitle ,font_title);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_theme_t* lv_theme_mono_init(lv_color_t color_primary, lv_color_t color_secondary, uint32_t flags, lv_font_t* font_small, lv_font_t* font_normal, lv_font_t* font_subtitle, lv_font_t* font_title)
int luat_lv_theme_mono_init(lua_State *L) {
    LV_DEBUG("CALL lv_theme_mono_init");
    lv_color_t color_primary = {0};
    color_primary.full = luaL_checkinteger(L, 1);
    lv_color_t color_secondary = {0};
    color_secondary.full = luaL_checkinteger(L, 2);
    uint32_t flags = (uint32_t)luaL_checkinteger(L, 3);
    lv_font_t* font_small = (lv_font_t*)lua_touserdata(L, 4);
    lv_font_t* font_normal = (lv_font_t*)lua_touserdata(L, 5);
    lv_font_t* font_subtitle = (lv_font_t*)lua_touserdata(L, 6);
    lv_font_t* font_title = (lv_font_t*)lua_touserdata(L, 7);
    lv_theme_t* ret = NULL;
    ret = lv_theme_mono_init(color_primary ,color_secondary ,flags ,font_small ,font_normal ,font_subtitle ,font_title);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

