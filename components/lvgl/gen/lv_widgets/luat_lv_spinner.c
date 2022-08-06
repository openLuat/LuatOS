

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"

#if LV_USE_ANIMATION

//  lv_obj_t* lv_spinner_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_spinner_create(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_spinner_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_spinner_set_arc_length(lv_obj_t* spinner, lv_anim_value_t deg)
int luat_lv_spinner_set_arc_length(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_set_arc_length");
    lv_obj_t* spinner = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_value_t deg = (lv_anim_value_t)luaL_checkinteger(L, 2);
    lv_spinner_set_arc_length(spinner ,deg);
    return 0;
}

//  void lv_spinner_set_spin_time(lv_obj_t* spinner, uint16_t time)
int luat_lv_spinner_set_spin_time(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_set_spin_time");
    lv_obj_t* spinner = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t time = (uint16_t)luaL_checkinteger(L, 2);
    lv_spinner_set_spin_time(spinner ,time);
    return 0;
}

//  void lv_spinner_set_type(lv_obj_t* spinner, lv_spinner_type_t type)
int luat_lv_spinner_set_type(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_set_type");
    lv_obj_t* spinner = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spinner_type_t type = (lv_spinner_type_t)luaL_checkinteger(L, 2);
    lv_spinner_set_type(spinner ,type);
    return 0;
}

//  void lv_spinner_set_dir(lv_obj_t* spinner, lv_spinner_dir_t dir)
int luat_lv_spinner_set_dir(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_set_dir");
    lv_obj_t* spinner = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spinner_dir_t dir = (lv_spinner_dir_t)luaL_checkinteger(L, 2);
    lv_spinner_set_dir(spinner ,dir);
    return 0;
}

//  lv_anim_value_t lv_spinner_get_arc_length(lv_obj_t* spinner)
int luat_lv_spinner_get_arc_length(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_get_arc_length");
    lv_obj_t* spinner = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_value_t ret;
    ret = lv_spinner_get_arc_length(spinner);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_spinner_get_spin_time(lv_obj_t* spinner)
int luat_lv_spinner_get_spin_time(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_get_spin_time");
    lv_obj_t* spinner = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_spinner_get_spin_time(spinner);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_spinner_type_t lv_spinner_get_type(lv_obj_t* spinner)
int luat_lv_spinner_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_get_type");
    lv_obj_t* spinner = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spinner_type_t ret;
    ret = lv_spinner_get_type(spinner);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_spinner_dir_t lv_spinner_get_dir(lv_obj_t* spinner)
int luat_lv_spinner_get_dir(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_get_dir");
    lv_obj_t* spinner = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spinner_dir_t ret;
    ret = lv_spinner_get_dir(spinner);
    lua_pushinteger(L, ret);
    return 1;
}

#endif

