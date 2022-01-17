
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_tabview_create(lv_obj_t* parent, lv_dir_t tab_pos, lv_coord_t tab_size)
int luat_lv_tabview_create(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dir_t tab_pos = (lv_dir_t)luaL_checkinteger(L, 2);
    lv_coord_t tab_size = (lv_coord_t)luaL_checknumber(L, 3);
    lv_obj_t* ret = NULL;
    ret = lv_tabview_create(parent ,tab_pos ,tab_size);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_tabview_add_tab(lv_obj_t* tv, char* name)
int luat_lv_tabview_add_tab(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_add_tab");
    lv_obj_t* tv = (lv_obj_t*)lua_touserdata(L, 1);
    char* name = (char*)luaL_checkstring(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_tabview_add_tab(tv ,name);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_tabview_get_content(lv_obj_t* tv)
int luat_lv_tabview_get_content(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_get_content");
    lv_obj_t* tv = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_tabview_get_content(tv);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_tabview_get_tab_btns(lv_obj_t* tv)
int luat_lv_tabview_get_tab_btns(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_get_tab_btns");
    lv_obj_t* tv = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_tabview_get_tab_btns(tv);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_tabview_set_act(lv_obj_t* obj, uint32_t id, lv_anim_enable_t anim_en)
int luat_lv_tabview_set_act(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_set_act");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t id = (uint32_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_tabview_set_act(obj ,id ,anim_en);
    return 0;
}

//  uint16_t lv_tabview_get_tab_act(lv_obj_t* tv)
int luat_lv_tabview_get_tab_act(lua_State *L) {
    LV_DEBUG("CALL lv_tabview_get_tab_act");
    lv_obj_t* tv = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_tabview_get_tab_act(tv);
    lua_pushinteger(L, ret);
    return 1;
}

