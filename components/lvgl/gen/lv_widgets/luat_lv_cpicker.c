

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_cpicker_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_cpicker_create(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_cpicker_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_cpicker_set_type(lv_obj_t* cpicker, lv_cpicker_type_t type)
int luat_lv_cpicker_set_type(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_set_type");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    lv_cpicker_type_t type = (lv_cpicker_type_t)luaL_checkinteger(L, 2);
    lv_cpicker_set_type(cpicker ,type);
    return 0;
}

//  bool lv_cpicker_set_hue(lv_obj_t* cpicker, uint16_t hue)
int luat_lv_cpicker_set_hue(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_set_hue");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t hue = (uint16_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_cpicker_set_hue(cpicker ,hue);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_cpicker_set_saturation(lv_obj_t* cpicker, uint8_t saturation)
int luat_lv_cpicker_set_saturation(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_set_saturation");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t saturation = (uint8_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_cpicker_set_saturation(cpicker ,saturation);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_cpicker_set_value(lv_obj_t* cpicker, uint8_t val)
int luat_lv_cpicker_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_set_value");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t val = (uint8_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_cpicker_set_value(cpicker ,val);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_cpicker_set_hsv(lv_obj_t* cpicker, lv_color_hsv_t hsv)
int luat_lv_cpicker_set_hsv(lua_State *L) {
    // LV_DEBUG("CALL lv_cpicker_set_hsv");
    // lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    // lv_color_hsv_t hsv = luaL_checkinteger(L, 2);
    // // miss arg convert
    // bool ret;
    // ret = lv_cpicker_set_hsv(cpicker ,hsv);
    // lua_pushboolean(L, ret);
    // return 1;
    return 0;
}

//  bool lv_cpicker_set_color(lv_obj_t* cpicker, lv_color_t color)
int luat_lv_cpicker_set_color(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_set_color");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_cpicker_set_color(cpicker ,color);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_cpicker_set_color_mode(lv_obj_t* cpicker, lv_cpicker_color_mode_t mode)
int luat_lv_cpicker_set_color_mode(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_set_color_mode");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    lv_cpicker_color_mode_t mode = (lv_cpicker_color_mode_t)luaL_checkinteger(L, 2);
    lv_cpicker_set_color_mode(cpicker ,mode);
    return 0;
}

//  void lv_cpicker_set_color_mode_fixed(lv_obj_t* cpicker, bool fixed)
int luat_lv_cpicker_set_color_mode_fixed(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_set_color_mode_fixed");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    bool fixed = (bool)lua_toboolean(L, 2);
    lv_cpicker_set_color_mode_fixed(cpicker ,fixed);
    return 0;
}

//  void lv_cpicker_set_knob_colored(lv_obj_t* cpicker, bool en)
int luat_lv_cpicker_set_knob_colored(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_set_knob_colored");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_cpicker_set_knob_colored(cpicker ,en);
    return 0;
}

//  lv_cpicker_color_mode_t lv_cpicker_get_color_mode(lv_obj_t* cpicker)
int luat_lv_cpicker_get_color_mode(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_get_color_mode");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    lv_cpicker_color_mode_t ret;
    ret = lv_cpicker_get_color_mode(cpicker);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_cpicker_get_color_mode_fixed(lv_obj_t* cpicker)
int luat_lv_cpicker_get_color_mode_fixed(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_get_color_mode_fixed");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_cpicker_get_color_mode_fixed(cpicker);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_cpicker_get_hue(lv_obj_t* cpicker)
int luat_lv_cpicker_get_hue(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_get_hue");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_cpicker_get_hue(cpicker);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint8_t lv_cpicker_get_saturation(lv_obj_t* cpicker)
int luat_lv_cpicker_get_saturation(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_get_saturation");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t ret;
    ret = lv_cpicker_get_saturation(cpicker);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint8_t lv_cpicker_get_value(lv_obj_t* cpicker)
int luat_lv_cpicker_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_get_value");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t ret;
    ret = lv_cpicker_get_value(cpicker);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_hsv_t lv_cpicker_get_hsv(lv_obj_t* cpicker)
int luat_lv_cpicker_get_hsv(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_get_hsv");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_hsv_t ret;
    ret = lv_cpicker_get_hsv(cpicker);
    lua_pushinteger(L, ret.h);
    lua_pushinteger(L, ret.s);
    lua_pushinteger(L, ret.v);
    return 3;
}

//  lv_color_t lv_cpicker_get_color(lv_obj_t* cpicker)
int luat_lv_cpicker_get_color(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_get_color");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t ret;
    ret = lv_cpicker_get_color(cpicker);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  bool lv_cpicker_get_knob_colored(lv_obj_t* cpicker)
int luat_lv_cpicker_get_knob_colored(lua_State *L) {
    LV_DEBUG("CALL lv_cpicker_get_knob_colored");
    lv_obj_t* cpicker = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_cpicker_get_knob_colored(cpicker);
    lua_pushboolean(L, ret);
    return 1;
}

