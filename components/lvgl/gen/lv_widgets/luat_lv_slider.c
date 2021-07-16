
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_slider_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_slider_create(lua_State *L) {
    LV_DEBUG("CALL lv_slider_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_slider_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_slider_set_value(lv_obj_t* slider, int16_t value, lv_anim_enable_t anim)
int luat_lv_slider_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_value");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t value = (int16_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_slider_set_value(slider ,value ,anim);
    return 0;
}

//  void lv_slider_set_left_value(lv_obj_t* slider, int16_t left_value, lv_anim_enable_t anim)
int luat_lv_slider_set_left_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_left_value");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t left_value = (int16_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_slider_set_left_value(slider ,left_value ,anim);
    return 0;
}

//  void lv_slider_set_range(lv_obj_t* slider, int16_t min, int16_t max)
int luat_lv_slider_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_range");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t min = (int16_t)luaL_checkinteger(L, 2);
    int16_t max = (int16_t)luaL_checkinteger(L, 3);
    lv_slider_set_range(slider ,min ,max);
    return 0;
}

//  void lv_slider_set_anim_time(lv_obj_t* slider, uint16_t anim_time)
int luat_lv_slider_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_anim_time");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_slider_set_anim_time(slider ,anim_time);
    return 0;
}

//  void lv_slider_set_type(lv_obj_t* slider, lv_slider_type_t type)
int luat_lv_slider_set_type(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_type");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    lv_slider_type_t type = (lv_slider_type_t)luaL_checkinteger(L, 2);
    lv_slider_set_type(slider ,type);
    return 0;
}

//  int16_t lv_slider_get_value(lv_obj_t* slider)
int luat_lv_slider_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_value");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_slider_get_value(slider);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_slider_get_left_value(lv_obj_t* slider)
int luat_lv_slider_get_left_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_left_value");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_slider_get_left_value(slider);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_slider_get_min_value(lv_obj_t* slider)
int luat_lv_slider_get_min_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_min_value");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_slider_get_min_value(slider);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_slider_get_max_value(lv_obj_t* slider)
int luat_lv_slider_get_max_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_max_value");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_slider_get_max_value(slider);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_slider_is_dragged(lv_obj_t* slider)
int luat_lv_slider_is_dragged(lua_State *L) {
    LV_DEBUG("CALL lv_slider_is_dragged");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_slider_is_dragged(slider);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_slider_get_anim_time(lv_obj_t* slider)
int luat_lv_slider_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_anim_time");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_slider_get_anim_time(slider);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_slider_type_t lv_slider_get_type(lv_obj_t* slider)
int luat_lv_slider_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_type");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    lv_slider_type_t ret;
    ret = lv_slider_get_type(slider);
    lua_pushinteger(L, ret);
    return 1;
}

