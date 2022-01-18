
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_list_create(lv_obj_t* parent)
int luat_lv_list_create(lua_State *L) {
    LV_DEBUG("CALL lv_list_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_list_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_list_add_text(lv_obj_t* list, char* txt)
int luat_lv_list_add_text(lua_State *L) {
    LV_DEBUG("CALL lv_list_add_text");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_list_add_text(list ,txt);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_list_add_btn(lv_obj_t* list, char* icon, char* txt)
int luat_lv_list_add_btn(lua_State *L) {
    LV_DEBUG("CALL lv_list_add_btn");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    char* icon = (char*)luaL_checkstring(L, 2);
    char* txt = (char*)luaL_checkstring(L, 3);
    lv_obj_t* ret = NULL;
    ret = lv_list_add_btn(list ,icon ,txt);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  char* lv_list_get_btn_text(lv_obj_t* list, lv_obj_t* btn)
int luat_lv_list_get_btn_text(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_btn_text");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 2);
    char* ret = NULL;
    ret = lv_list_get_btn_text(list ,btn);
    lua_pushstring(L, ret);
    return 1;
}

