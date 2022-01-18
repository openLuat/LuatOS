
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_bar_create(lv_obj_t* parent)
int luat_lv_bar_create(lua_State *L) {
    LV_DEBUG("CALL lv_bar_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_bar_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_bar_set_value(lv_obj_t* obj, int32_t value, lv_anim_enable_t anim)
int luat_lv_bar_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t value = (int32_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_bar_set_value(obj ,value ,anim);
    return 0;
}

//  void lv_bar_set_start_value(lv_obj_t* obj, int32_t start_value, lv_anim_enable_t anim)
int luat_lv_bar_set_start_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_start_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t start_value = (int32_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_bar_set_start_value(obj ,start_value ,anim);
    return 0;
}

//  void lv_bar_set_range(lv_obj_t* obj, int32_t min, int32_t max)
int luat_lv_bar_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_range");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t min = (int32_t)luaL_checkinteger(L, 2);
    int32_t max = (int32_t)luaL_checkinteger(L, 3);
    lv_bar_set_range(obj ,min ,max);
    return 0;
}

//  void lv_bar_set_mode(lv_obj_t* obj, lv_bar_mode_t mode)
int luat_lv_bar_set_mode(lua_State *L) {
    LV_DEBUG("CALL lv_bar_set_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_bar_mode_t mode = (lv_bar_mode_t)luaL_checkinteger(L, 2);
    lv_bar_set_mode(obj ,mode);
    return 0;
}

//  int32_t lv_bar_get_value(lv_obj_t* obj)
int luat_lv_bar_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_bar_get_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_bar_get_start_value(lv_obj_t* obj)
int luat_lv_bar_get_start_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_start_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_bar_get_start_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_bar_get_min_value(lv_obj_t* obj)
int luat_lv_bar_get_min_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_min_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_bar_get_min_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_bar_get_max_value(lv_obj_t* obj)
int luat_lv_bar_get_max_value(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_max_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_bar_get_max_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_bar_mode_t lv_bar_get_mode(lv_obj_t* obj)
int luat_lv_bar_get_mode(lua_State *L) {
    LV_DEBUG("CALL lv_bar_get_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_bar_mode_t ret;
    ret = lv_bar_get_mode(obj);
    lua_pushinteger(L, ret);
    return 1;
}

