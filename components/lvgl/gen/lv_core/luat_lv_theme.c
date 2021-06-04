
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_theme_t* lv_theme_get_from_obj(lv_obj_t* obj)
int luat_lv_theme_get_from_obj(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_from_obj");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_theme_t* ret = NULL;
    ret = lv_theme_get_from_obj(obj);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_theme_apply(lv_obj_t* obj)
int luat_lv_theme_apply(lua_State *L) {
    LV_DEBUG("CALL lv_theme_apply");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_theme_apply(obj);
    return 0;
}

//  void lv_theme_set_parent(lv_theme_t* new_theme, lv_theme_t* parent)
int luat_lv_theme_set_parent(lua_State *L) {
    LV_DEBUG("CALL lv_theme_set_parent");
    lv_theme_t* new_theme = (lv_theme_t*)lua_touserdata(L, 1);
    lv_theme_t* parent = (lv_theme_t*)lua_touserdata(L, 2);
    lv_theme_set_parent(new_theme ,parent);
    return 0;
}

//  lv_font_t* lv_theme_get_font_small(lv_obj_t* obj)
int luat_lv_theme_get_font_small(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_font_small");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_font_t* ret = NULL;
    ret = lv_theme_get_font_small(obj);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_font_t* lv_theme_get_font_normal(lv_obj_t* obj)
int luat_lv_theme_get_font_normal(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_font_normal");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_font_t* ret = NULL;
    ret = lv_theme_get_font_normal(obj);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_font_t* lv_theme_get_font_large(lv_obj_t* obj)
int luat_lv_theme_get_font_large(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_font_large");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_font_t* ret = NULL;
    ret = lv_theme_get_font_large(obj);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_color_t lv_theme_get_color_primary(lv_obj_t* obj)
int luat_lv_theme_get_color_primary(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_color_primary");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t ret;
    ret = lv_theme_get_color_primary(obj);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_theme_get_color_secondary(lv_obj_t* obj)
int luat_lv_theme_get_color_secondary(lua_State *L) {
    LV_DEBUG("CALL lv_theme_get_color_secondary");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t ret;
    ret = lv_theme_get_color_secondary(obj);
    lua_pushinteger(L, ret.full);
    return 1;
}

