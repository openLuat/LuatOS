
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_tabview_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_tabview_create(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_tabview_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_tabview_add_tab(lv_obj_t* tabview, char* name)
int luat_lv_tabview_add_tab(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_add_tab");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    char* name = (char*)luaL_checkstring(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_tabview_add_tab(tabview ,name);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_tabview_clean_tab(lv_obj_t* tab)
int luat_lv_tabview_clean_tab(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_clean_tab");
    lv_obj_t* tab = (lv_obj_t*)lua_touserdata(L, 1);
    lv_tabview_clean_tab(tab);
    return 0;
}

//  void lv_tabview_set_tab_act(lv_obj_t* tabview, uint16_t id, lv_anim_enable_t anim)
int luat_lv_tabview_set_tab_act(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_set_tab_act");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_tabview_set_tab_act(tabview ,id ,anim);
    return 0;
}

//  void lv_tabview_set_tab_name(lv_obj_t* tabview, uint16_t id, char* name)
int luat_lv_tabview_set_tab_name(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_set_tab_name");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 2);
    char* name = (char*)luaL_checkstring(L, 3);
    lv_tabview_set_tab_name(tabview ,id ,name);
    return 0;
}

//  void lv_tabview_set_anim_time(lv_obj_t* tabview, uint16_t anim_time)
int luat_lv_tabview_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_set_anim_time");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_tabview_set_anim_time(tabview ,anim_time);
    return 0;
}

//  void lv_tabview_set_btns_pos(lv_obj_t* tabview, lv_tabview_btns_pos_t btns_pos)
int luat_lv_tabview_set_btns_pos(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_set_btns_pos");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    lv_tabview_btns_pos_t btns_pos = (lv_tabview_btns_pos_t)luaL_checkinteger(L, 2);
    lv_tabview_set_btns_pos(tabview ,btns_pos);
    return 0;
}

//  uint16_t lv_tabview_get_tab_act(lv_obj_t* tabview)
int luat_lv_tabview_get_tab_act(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_get_tab_act");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_tabview_get_tab_act(tabview);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_tabview_get_tab_count(lv_obj_t* tabview)
int luat_lv_tabview_get_tab_count(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_get_tab_count");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_tabview_get_tab_count(tabview);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_obj_t* lv_tabview_get_tab(lv_obj_t* tabview, uint16_t id)
int luat_lv_tabview_get_tab(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_get_tab");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_tabview_get_tab(tabview ,id);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint16_t lv_tabview_get_anim_time(lv_obj_t* tabview)
int luat_lv_tabview_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_get_anim_time");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_tabview_get_anim_time(tabview);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_tabview_btns_pos_t lv_tabview_get_btns_pos(lv_obj_t* tabview)
int luat_lv_tabview_get_btns_pos(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_get_btns_pos");
    lv_obj_t* tabview = (lv_obj_t*)lua_touserdata(L, 1);
    lv_tabview_btns_pos_t ret;
    ret = lv_tabview_get_btns_pos(tabview);
    lua_pushinteger(L, ret);
    return 1;
}

