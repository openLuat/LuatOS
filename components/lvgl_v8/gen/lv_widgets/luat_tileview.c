
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_tileview_create(lv_obj_t* parent)
int luat_lv_tileview_create(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_tileview_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_tileview_add_tile(lv_obj_t* tv, uint8_t row_id, uint8_t col_id, lv_dir_t dir)
int luat_lv_tileview_add_tile(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_add_tile");
    lv_obj_t* tv = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t row_id = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t col_id = (uint8_t)luaL_checkinteger(L, 3);
    lv_dir_t dir = (lv_dir_t)luaL_checkinteger(L, 4);
    lv_obj_t* ret = NULL;
    ret = lv_tileview_add_tile(tv ,row_id ,col_id ,dir);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_tileview_get_tile_act(lv_obj_t* obj)
int luat_lv_tileview_get_tile_act(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_get_tile_act");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_tileview_get_tile_act(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

