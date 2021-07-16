
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_bar_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_bar_create(lua_State *L) {
    LV_DEBUG("CALL lv_bar_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_bar_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_bar_set_value(lv_obj_t* bar, int16_t value, lv_anim_enable_t anim)
int luat_lv_bar_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_value");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t value = (int16_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_bar_set_value(bar ,value ,anim);
    return 0;
}

//  void lv_bar_set_start_value(lv_obj_t* bar, int16_t start_value, lv_anim_enable_t anim)
int luat_lv_bar_set_start_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_start_value");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t start_value = (int16_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_bar_set_start_value(bar ,start_value ,anim);
    return 0;
}

//  void lv_bar_set_range(lv_obj_t* bar, int16_t min, int16_t max)
int luat_lv_bar_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_range");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t min = (int16_t)luaL_checkinteger(L, 2);
    int16_t max = (int16_t)luaL_checkinteger(L, 3);
    lv_bar_set_range(bar ,min ,max);
    return 0;
}

//  void lv_bar_set_type(lv_obj_t* bar, lv_bar_type_t type)
int luat_lv_bar_set_type(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_type");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    lv_bar_type_t type = (lv_bar_type_t)luaL_checkinteger(L, 2);
    lv_bar_set_type(bar ,type);
    return 0;
}

//  void lv_bar_set_anim_time(lv_obj_t* bar, uint16_t anim_time)
int luat_lv_bar_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_anim_time");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_bar_set_anim_time(bar ,anim_time);
    return 0;
}

//  int16_t lv_bar_get_value(lv_obj_t* bar)
int luat_lv_bar_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_value");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_bar_get_value(bar);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_bar_get_start_value(lv_obj_t* bar)
int luat_lv_bar_get_start_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_start_value");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_bar_get_start_value(bar);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_bar_get_min_value(lv_obj_t* bar)
int luat_lv_bar_get_min_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_min_value");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_bar_get_min_value(bar);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_bar_get_max_value(lv_obj_t* bar)
int luat_lv_bar_get_max_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_max_value");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_bar_get_max_value(bar);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_bar_type_t lv_bar_get_type(lv_obj_t* bar)
int luat_lv_bar_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_type");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    lv_bar_type_t ret;
    ret = lv_bar_get_type(bar);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_bar_get_anim_time(lv_obj_t* bar)
int luat_lv_bar_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_anim_time");
    lv_obj_t* bar = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_bar_get_anim_time(bar);
    lua_pushinteger(L, ret);
    return 1;
}

