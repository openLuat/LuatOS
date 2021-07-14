
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_style_init(lv_style_t* style)
int luat_lv_style_init(lua_State *L) {
    LV_DEBUG("CALL lv_style_init");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_init(style);
    return 0;
}

//  void lv_style_copy(lv_style_t* style_dest, lv_style_t* style_src)
int luat_lv_style_copy(lua_State *L) {
    LV_DEBUG("CALL lv_style_copy");
    lv_style_t* style_dest = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_t* style_src = (lv_style_t*)lua_touserdata(L, 2);
    lv_style_copy(style_dest ,style_src);
    return 0;
}

//  void lv_style_list_init(lv_style_list_t* list)
int luat_lv_style_list_init(lua_State *L) {
    LV_DEBUG("CALL lv_style_list_init");
    lv_style_list_t* list = (lv_style_list_t*)lua_touserdata(L, 1);
    lv_style_list_init(list);
    return 0;
}

//  void lv_style_list_copy(lv_style_list_t* list_dest, lv_style_list_t* list_src)
int luat_lv_style_list_copy(lua_State *L) {
    LV_DEBUG("CALL lv_style_list_copy");
    lv_style_list_t* list_dest = (lv_style_list_t*)lua_touserdata(L, 1);
    lv_style_list_t* list_src = (lv_style_list_t*)lua_touserdata(L, 2);
    lv_style_list_copy(list_dest ,list_src);
    return 0;
}

//  lv_style_t* lv_style_list_get_style(lv_style_list_t* list, uint8_t id)
int luat_lv_style_list_get_style(lua_State *L) {
    LV_DEBUG("CALL lv_style_list_get_style");
    lv_style_list_t* list = (lv_style_list_t*)lua_touserdata(L, 1);
    uint8_t id = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_t* ret = NULL;
    ret = lv_style_list_get_style(list ,id);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_style_reset(lv_style_t* style)
int luat_lv_style_reset(lua_State *L) {
    LV_DEBUG("CALL lv_style_reset");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_reset(style);
    return 0;
}

//  bool lv_style_remove_prop(lv_style_t* style, lv_style_property_t prop)
int luat_lv_style_remove_prop(lua_State *L) {
    LV_DEBUG("CALL lv_style_remove_prop");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_property_t prop = (lv_style_property_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_style_remove_prop(style ,prop);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_style_t* lv_style_list_get_local_style(lv_style_list_t* list)
int luat_lv_style_list_get_local_style(lua_State *L) {
    LV_DEBUG("CALL lv_style_list_get_local_style");
    lv_style_list_t* list = (lv_style_list_t*)lua_touserdata(L, 1);
    lv_style_t* ret = NULL;
    ret = lv_style_list_get_local_style(list);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

