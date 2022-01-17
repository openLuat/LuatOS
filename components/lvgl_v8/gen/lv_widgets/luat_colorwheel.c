
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_colorwheel_create(lv_obj_t* parent, bool knob_recolor)
int luat_lv_colorwheel_create(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    bool knob_recolor = (bool)lua_toboolean(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_colorwheel_create(parent ,knob_recolor);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  bool lv_colorwheel_set_hsv(lv_obj_t* obj, lv_color_hsv_t hsv)
int luat_lv_colorwheel_set_hsv(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_set_hsv");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_hsv_t hsv;
    // miss arg convert
    bool ret;
    ret = lv_colorwheel_set_hsv(obj ,hsv);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_colorwheel_set_rgb(lv_obj_t* obj, lv_color_t color)
int luat_lv_colorwheel_set_rgb(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_set_rgb");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_colorwheel_set_rgb(obj ,color);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_colorwheel_set_mode(lv_obj_t* obj, lv_colorwheel_mode_t mode)
int luat_lv_colorwheel_set_mode(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_set_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_colorwheel_mode_t mode;
    // miss arg convert
    lv_colorwheel_set_mode(obj ,mode);
    return 0;
}

//  void lv_colorwheel_set_mode_fixed(lv_obj_t* obj, bool fixed)
int luat_lv_colorwheel_set_mode_fixed(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_set_mode_fixed");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool fixed = (bool)lua_toboolean(L, 2);
    lv_colorwheel_set_mode_fixed(obj ,fixed);
    return 0;
}

//  lv_color_hsv_t lv_colorwheel_get_hsv(lv_obj_t* obj)
int luat_lv_colorwheel_get_hsv(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_get_hsv");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_hsv_t ret;
    ret = lv_colorwheel_get_hsv(obj);
    lua_pushinteger(L, ret.h);
    lua_pushinteger(L, ret.s);
    lua_pushinteger(L, ret.v);
    return 3;
}

//  lv_color_t lv_colorwheel_get_rgb(lv_obj_t* obj)
int luat_lv_colorwheel_get_rgb(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_get_rgb");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t ret;
    ret = lv_colorwheel_get_rgb(obj);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_colorwheel_mode_t lv_colorwheel_get_color_mode(lv_obj_t* obj)
int luat_lv_colorwheel_get_color_mode(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_get_color_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_colorwheel_mode_t ret;
    ret = lv_colorwheel_get_color_mode(obj);
    return 0;
}

//  bool lv_colorwheel_get_color_mode_fixed(lv_obj_t* obj)
int luat_lv_colorwheel_get_color_mode_fixed(lua_State *L) {
    LV_DEBUG("CALL lv_colorwheel_get_color_mode_fixed");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_colorwheel_get_color_mode_fixed(obj);
    lua_pushboolean(L, ret);
    return 1;
}

