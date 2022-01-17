
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_slider_create(lv_obj_t* parent)
int luat_lv_slider_create(lua_State *L) {
    LV_DEBUG("CALL lv_slider_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_slider_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_slider_set_value(lv_obj_t* obj, int32_t value, lv_anim_enable_t anim)
int luat_lv_slider_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t value = (int32_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_slider_set_value(obj ,value ,anim);
    return 0;
}

//  void lv_slider_set_left_value(lv_obj_t* obj, int32_t value, lv_anim_enable_t anim)
int luat_lv_slider_set_left_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_left_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t value = (int32_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_slider_set_left_value(obj ,value ,anim);
    return 0;
}

//  void lv_slider_set_range(lv_obj_t* obj, int32_t min, int32_t max)
int luat_lv_slider_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_range");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t min = (int32_t)luaL_checkinteger(L, 2);
    int32_t max = (int32_t)luaL_checkinteger(L, 3);
    lv_slider_set_range(obj ,min ,max);
    return 0;
}

//  void lv_slider_set_mode(lv_obj_t* obj, lv_slider_mode_t mode)
int luat_lv_slider_set_mode(lua_State *L) {
    LV_DEBUG("CALL lv_slider_set_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_slider_mode_t mode = (lv_slider_mode_t)luaL_checkinteger(L, 2);
    lv_slider_set_mode(obj ,mode);
    return 0;
}

//  int32_t lv_slider_get_value(lv_obj_t* obj)
int luat_lv_slider_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_slider_get_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_slider_get_left_value(lv_obj_t* obj)
int luat_lv_slider_get_left_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_left_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_slider_get_left_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_slider_get_min_value(lv_obj_t* obj)
int luat_lv_slider_get_min_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_min_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_slider_get_min_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_slider_get_max_value(lv_obj_t* obj)
int luat_lv_slider_get_max_value(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_max_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_slider_get_max_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_slider_is_dragged(lv_obj_t* obj)
int luat_lv_slider_is_dragged(lua_State *L) {
    LV_DEBUG("CALL lv_slider_is_dragged");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_slider_is_dragged(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_slider_mode_t lv_slider_get_mode(lv_obj_t* slider)
int luat_lv_slider_get_mode(lua_State *L) {
    LV_DEBUG("CALL lv_slider_get_mode");
    lv_obj_t* slider = (lv_obj_t*)lua_touserdata(L, 1);
    lv_slider_mode_t ret;
    ret = lv_slider_get_mode(slider);
    lua_pushinteger(L, ret);
    return 1;
}

