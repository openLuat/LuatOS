
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_cont_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_cont_create(lua_State *L) {
    LV_DEBUG("CALL lv_cont_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_cont_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_cont_set_layout(lv_obj_t* cont, lv_layout_t layout)
int luat_lv_cont_set_layout(lua_State *L) {
    LV_DEBUG("CALL lv_cont_set_layout");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t layout = (lv_layout_t)luaL_checkinteger(L, 2);
    lv_cont_set_layout(cont ,layout);
    return 0;
}

//  void lv_cont_set_fit4(lv_obj_t* cont, lv_fit_t left, lv_fit_t right, lv_fit_t top, lv_fit_t bottom)
int luat_lv_cont_set_fit4(lua_State *L) {
    LV_DEBUG("CALL lv_cont_set_fit4");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t left = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_fit_t right = (lv_fit_t)luaL_checkinteger(L, 3);
    lv_fit_t top = (lv_fit_t)luaL_checkinteger(L, 4);
    lv_fit_t bottom = (lv_fit_t)luaL_checkinteger(L, 5);
    lv_cont_set_fit4(cont ,left ,right ,top ,bottom);
    return 0;
}

//  void lv_cont_set_fit2(lv_obj_t* cont, lv_fit_t hor, lv_fit_t ver)
int luat_lv_cont_set_fit2(lua_State *L) {
    LV_DEBUG("CALL lv_cont_set_fit2");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t hor = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_fit_t ver = (lv_fit_t)luaL_checkinteger(L, 3);
    lv_cont_set_fit2(cont ,hor ,ver);
    return 0;
}

//  void lv_cont_set_fit(lv_obj_t* cont, lv_fit_t fit)
int luat_lv_cont_set_fit(lua_State *L) {
    LV_DEBUG("CALL lv_cont_set_fit");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t fit = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_cont_set_fit(cont ,fit);
    return 0;
}

//  lv_layout_t lv_cont_get_layout(lv_obj_t* cont)
int luat_lv_cont_get_layout(lua_State *L) {
    LV_DEBUG("CALL lv_cont_get_layout");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t ret;
    ret = lv_cont_get_layout(cont);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_cont_get_fit_left(lv_obj_t* cont)
int luat_lv_cont_get_fit_left(lua_State *L) {
    LV_DEBUG("CALL lv_cont_get_fit_left");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_cont_get_fit_left(cont);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_cont_get_fit_right(lv_obj_t* cont)
int luat_lv_cont_get_fit_right(lua_State *L) {
    LV_DEBUG("CALL lv_cont_get_fit_right");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_cont_get_fit_right(cont);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_cont_get_fit_top(lv_obj_t* cont)
int luat_lv_cont_get_fit_top(lua_State *L) {
    LV_DEBUG("CALL lv_cont_get_fit_top");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_cont_get_fit_top(cont);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_cont_get_fit_bottom(lv_obj_t* cont)
int luat_lv_cont_get_fit_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_cont_get_fit_bottom");
    lv_obj_t* cont = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_cont_get_fit_bottom(cont);
    lua_pushinteger(L, ret);
    return 1;
}

