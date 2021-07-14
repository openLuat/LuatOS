
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_btn_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_btn_create(lua_State *L) {
    LV_DEBUG("CALL lv_btn_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_btn_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_btn_set_checkable(lv_obj_t* btn, bool tgl)
int luat_lv_btn_set_checkable(lua_State *L) {
    LV_DEBUG("CALL lv_btn_set_checkable");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    bool tgl = (bool)lua_toboolean(L, 2);
    lv_btn_set_checkable(btn ,tgl);
    return 0;
}

//  void lv_btn_set_state(lv_obj_t* btn, lv_btn_state_t state)
int luat_lv_btn_set_state(lua_State *L) {
    LV_DEBUG("CALL lv_btn_set_state");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_state_t state = (lv_btn_state_t)luaL_checkinteger(L, 2);
    lv_btn_set_state(btn ,state);
    return 0;
}

//  void lv_btn_toggle(lv_obj_t* btn)
int luat_lv_btn_toggle(lua_State *L) {
    LV_DEBUG("CALL lv_btn_toggle");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_toggle(btn);
    return 0;
}

//  void lv_btn_set_layout(lv_obj_t* btn, lv_layout_t layout)
int luat_lv_btn_set_layout(lua_State *L) {
    LV_DEBUG("CALL lv_btn_set_layout");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t layout = (lv_layout_t)luaL_checkinteger(L, 2);
    lv_btn_set_layout(btn ,layout);
    return 0;
}

//  void lv_btn_set_fit4(lv_obj_t* btn, lv_fit_t left, lv_fit_t right, lv_fit_t top, lv_fit_t bottom)
int luat_lv_btn_set_fit4(lua_State *L) {
    LV_DEBUG("CALL lv_btn_set_fit4");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t left = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_fit_t right = (lv_fit_t)luaL_checkinteger(L, 3);
    lv_fit_t top = (lv_fit_t)luaL_checkinteger(L, 4);
    lv_fit_t bottom = (lv_fit_t)luaL_checkinteger(L, 5);
    lv_btn_set_fit4(btn ,left ,right ,top ,bottom);
    return 0;
}

//  void lv_btn_set_fit2(lv_obj_t* btn, lv_fit_t hor, lv_fit_t ver)
int luat_lv_btn_set_fit2(lua_State *L) {
    LV_DEBUG("CALL lv_btn_set_fit2");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t hor = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_fit_t ver = (lv_fit_t)luaL_checkinteger(L, 3);
    lv_btn_set_fit2(btn ,hor ,ver);
    return 0;
}

//  void lv_btn_set_fit(lv_obj_t* btn, lv_fit_t fit)
int luat_lv_btn_set_fit(lua_State *L) {
    LV_DEBUG("CALL lv_btn_set_fit");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t fit = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_btn_set_fit(btn ,fit);
    return 0;
}

//  lv_btn_state_t lv_btn_get_state(lv_obj_t* btn)
int luat_lv_btn_get_state(lua_State *L) {
    LV_DEBUG("CALL lv_btn_get_state");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_state_t ret;
    ret = lv_btn_get_state(btn);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_btn_get_checkable(lv_obj_t* btn)
int luat_lv_btn_get_checkable(lua_State *L) {
    LV_DEBUG("CALL lv_btn_get_checkable");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_btn_get_checkable(btn);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_layout_t lv_btn_get_layout(lv_obj_t* btn)
int luat_lv_btn_get_layout(lua_State *L) {
    LV_DEBUG("CALL lv_btn_get_layout");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t ret;
    ret = lv_btn_get_layout(btn);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_btn_get_fit_left(lv_obj_t* btn)
int luat_lv_btn_get_fit_left(lua_State *L) {
    LV_DEBUG("CALL lv_btn_get_fit_left");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_btn_get_fit_left(btn);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_btn_get_fit_right(lv_obj_t* btn)
int luat_lv_btn_get_fit_right(lua_State *L) {
    LV_DEBUG("CALL lv_btn_get_fit_right");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_btn_get_fit_right(btn);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_btn_get_fit_top(lv_obj_t* btn)
int luat_lv_btn_get_fit_top(lua_State *L) {
    LV_DEBUG("CALL lv_btn_get_fit_top");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_btn_get_fit_top(btn);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_btn_get_fit_bottom(lv_obj_t* btn)
int luat_lv_btn_get_fit_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_btn_get_fit_bottom");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_btn_get_fit_bottom(btn);
    lua_pushinteger(L, ret);
    return 1;
}

