
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_imgbtn_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_imgbtn_create(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_imgbtn_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_imgbtn_set_state(lv_obj_t* imgbtn, lv_btn_state_t state)
int luat_lv_imgbtn_set_state(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_set_state");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_state_t state = (lv_btn_state_t)luaL_checkinteger(L, 2);
    lv_imgbtn_set_state(imgbtn ,state);
    return 0;
}

//  void lv_imgbtn_toggle(lv_obj_t* imgbtn)
int luat_lv_imgbtn_toggle(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_toggle");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_imgbtn_toggle(imgbtn);
    return 0;
}

//  void lv_imgbtn_set_checkable(lv_obj_t* imgbtn, bool tgl)
int luat_lv_imgbtn_set_checkable(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_set_checkable");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    bool tgl = (bool)lua_toboolean(L, 2);
    lv_imgbtn_set_checkable(imgbtn ,tgl);
    return 0;
}

//  void* lv_imgbtn_get_src(lv_obj_t* imgbtn, lv_btn_state_t state)
int luat_lv_imgbtn_get_src(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_get_src");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_state_t state = (lv_btn_state_t)luaL_checkinteger(L, 2);
    void* ret = NULL;
    ret = lv_imgbtn_get_src(imgbtn ,state);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_btn_state_t lv_imgbtn_get_state(lv_obj_t* imgbtn)
int luat_lv_imgbtn_get_state(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_get_state");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_state_t ret;
    ret = lv_imgbtn_get_state(imgbtn);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_imgbtn_get_checkable(lv_obj_t* imgbtn)
int luat_lv_imgbtn_get_checkable(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_get_checkable");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_imgbtn_get_checkable(imgbtn);
    lua_pushboolean(L, ret);
    return 1;
}

