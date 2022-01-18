
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_win_create(lv_obj_t* parent, lv_coord_t header_height)
int luat_lv_win_create(lua_State *L) {
    LV_DEBUG("CALL lv_win_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t header_height = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_win_create(parent ,header_height);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_win_add_title(lv_obj_t* win, char* txt)
int luat_lv_win_add_title(lua_State *L) {
    LV_DEBUG("CALL lv_win_add_title");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_win_add_title(win ,txt);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_win_get_header(lv_obj_t* win)
int luat_lv_win_get_header(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_header");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_win_get_header(win);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_win_get_content(lv_obj_t* win)
int luat_lv_win_get_content(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_content");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_win_get_content(win);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

