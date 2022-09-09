
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_keyboard_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_keyboard_create(lua_State *L) {
    LV_DEBUG("CALL lv_keyboard_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_keyboard_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_keyboard_set_textarea(lv_obj_t* kb, lv_obj_t* ta)
int luat_lv_keyboard_set_textarea(lua_State *L) {
    LV_DEBUG("CALL lv_keyboard_set_textarea");
    lv_obj_t* kb = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 2);
    lv_keyboard_set_textarea(kb ,ta);
    return 0;
}

//  void lv_keyboard_set_mode(lv_obj_t* kb, lv_keyboard_mode_t mode)
int luat_lv_keyboard_set_mode(lua_State *L) {
    LV_DEBUG("CALL lv_keyboard_set_mode");
    lv_obj_t* kb = (lv_obj_t*)lua_touserdata(L, 1);
    lv_keyboard_mode_t mode = (lv_keyboard_mode_t)luaL_checkinteger(L, 2);
    lv_keyboard_set_mode(kb ,mode);
    return 0;
}

//  void lv_keyboard_set_cursor_manage(lv_obj_t* kb, bool en)
int luat_lv_keyboard_set_cursor_manage(lua_State *L) {
    LV_DEBUG("CALL lv_keyboard_set_cursor_manage");
    lv_obj_t* kb = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_keyboard_set_cursor_manage(kb ,en);
    return 0;
}

//  lv_obj_t* lv_keyboard_get_textarea(lv_obj_t* kb)
int luat_lv_keyboard_get_textarea(lua_State *L) {
    LV_DEBUG("CALL lv_keyboard_get_textarea");
    lv_obj_t* kb = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_keyboard_get_textarea(kb);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_keyboard_mode_t lv_keyboard_get_mode(lv_obj_t* kb)
int luat_lv_keyboard_get_mode(lua_State *L) {
    LV_DEBUG("CALL lv_keyboard_get_mode");
    lv_obj_t* kb = (lv_obj_t*)lua_touserdata(L, 1);
    lv_keyboard_mode_t ret;
    ret = lv_keyboard_get_mode(kb);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_keyboard_get_cursor_manage(lv_obj_t* kb)
int luat_lv_keyboard_get_cursor_manage(lua_State *L) {
    LV_DEBUG("CALL lv_keyboard_get_cursor_manage");
    lv_obj_t* kb = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_keyboard_get_cursor_manage(kb);
    lua_pushboolean(L, ret);
    return 1;
}

