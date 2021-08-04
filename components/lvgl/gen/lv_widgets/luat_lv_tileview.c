
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_tileview_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_tileview_create(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_tileview_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_tileview_add_element(lv_obj_t* tileview, lv_obj_t* element)
int luat_lv_tileview_add_element(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_add_element");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* element = (lv_obj_t*)lua_touserdata(L, 2);
    lv_tileview_add_element(tileview ,element);
    return 0;
}

//  void lv_tileview_set_tile_act(lv_obj_t* tileview, lv_coord_t x, lv_coord_t y, lv_anim_enable_t anim)
int luat_lv_tileview_set_tile_act(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_set_tile_act");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 4);
    lv_tileview_set_tile_act(tileview ,x ,y ,anim);
    return 0;
}

//  void lv_tileview_set_edge_flash(lv_obj_t* tileview, bool en)
int luat_lv_tileview_set_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_set_edge_flash");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_tileview_set_edge_flash(tileview ,en);
    return 0;
}

//  void lv_tileview_set_anim_time(lv_obj_t* tileview, uint16_t anim_time)
int luat_lv_tileview_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_set_anim_time");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_tileview_set_anim_time(tileview ,anim_time);
    return 0;
}

//  void lv_tileview_get_tile_act(lv_obj_t* tileview, lv_coord_t* x, lv_coord_t* y)
int luat_lv_tileview_get_tile_act(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_get_tile_act");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t* x = (lv_coord_t*)lua_touserdata(L, 2);
    lv_coord_t* y = (lv_coord_t*)lua_touserdata(L, 3);
    lv_tileview_get_tile_act(tileview ,x ,y);
    return 0;
}

//  bool lv_tileview_get_edge_flash(lv_obj_t* tileview)
int luat_lv_tileview_get_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_get_edge_flash");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_tileview_get_edge_flash(tileview);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_tileview_get_anim_time(lv_obj_t* tileview)
int luat_lv_tileview_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_get_anim_time");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_tileview_get_anim_time(tileview);
    lua_pushinteger(L, ret);
    return 1;
}

