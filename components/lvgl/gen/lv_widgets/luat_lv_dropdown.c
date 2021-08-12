
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_dropdown_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_dropdown_create(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_dropdown_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_dropdown_set_text(lv_obj_t* ddlist, char* txt)
int luat_lv_dropdown_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_text");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_dropdown_set_text(ddlist ,txt);
    return 0;
}

//  void lv_dropdown_clear_options(lv_obj_t* ddlist)
int luat_lv_dropdown_clear_options(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_clear_options");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dropdown_clear_options(ddlist);
    return 0;
}

//  void lv_dropdown_set_options(lv_obj_t* ddlist, char* options)
int luat_lv_dropdown_set_options(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_options");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    char* options = (char*)luaL_checkstring(L, 2);
    lv_dropdown_set_options(ddlist ,options);
    return 0;
}

//  void lv_dropdown_set_options_static(lv_obj_t* ddlist, char* options)
int luat_lv_dropdown_set_options_static(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_options_static");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    char* options = (char*)luaL_checkstring(L, 2);
    lv_dropdown_set_options_static(ddlist ,options);
    return 0;
}

//  void lv_dropdown_add_option(lv_obj_t* ddlist, char* option, uint32_t pos)
int luat_lv_dropdown_add_option(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_add_option");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    char* option = (char*)luaL_checkstring(L, 2);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 3);
    lv_dropdown_add_option(ddlist ,option ,pos);
    return 0;
}

//  void lv_dropdown_set_selected(lv_obj_t* ddlist, uint16_t sel_opt)
int luat_lv_dropdown_set_selected(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_selected");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t sel_opt = (uint16_t)luaL_checkinteger(L, 2);
    lv_dropdown_set_selected(ddlist ,sel_opt);
    return 0;
}

//  void lv_dropdown_set_dir(lv_obj_t* ddlist, lv_dropdown_dir_t dir)
int luat_lv_dropdown_set_dir(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_dir");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dropdown_dir_t dir = (lv_dropdown_dir_t)luaL_checkinteger(L, 2);
    lv_dropdown_set_dir(ddlist ,dir);
    return 0;
}

//  void lv_dropdown_set_max_height(lv_obj_t* ddlist, lv_coord_t h)
int luat_lv_dropdown_set_max_height(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_max_height");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 2);
    lv_dropdown_set_max_height(ddlist ,h);
    return 0;
}

//  void lv_dropdown_set_show_selected(lv_obj_t* ddlist, bool show)
int luat_lv_dropdown_set_show_selected(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_show_selected");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    bool show = (bool)lua_toboolean(L, 2);
    lv_dropdown_set_show_selected(ddlist ,show);
    return 0;
}

//  char* lv_dropdown_get_text(lv_obj_t* ddlist)
int luat_lv_dropdown_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_text");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_dropdown_get_text(ddlist);
    lua_pushstring(L, ret);
    return 1;
}

//  char* lv_dropdown_get_options(lv_obj_t* ddlist)
int luat_lv_dropdown_get_options(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_options");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_dropdown_get_options(ddlist);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_dropdown_get_selected(lv_obj_t* ddlist)
int luat_lv_dropdown_get_selected(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_selected");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_dropdown_get_selected(ddlist);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_dropdown_get_option_cnt(lv_obj_t* ddlist)
int luat_lv_dropdown_get_option_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_option_cnt");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_dropdown_get_option_cnt(ddlist);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_dropdown_get_max_height(lv_obj_t* ddlist)
int luat_lv_dropdown_get_max_height(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_max_height");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_dropdown_get_max_height(ddlist);
    lua_pushinteger(L, ret);
    return 1;
}

//  char* lv_dropdown_get_symbol(lv_obj_t* ddlist)
int luat_lv_dropdown_get_symbol(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_symbol");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_dropdown_get_symbol(ddlist);
    lua_pushstring(L, ret);
    return 1;
}

//  lv_dropdown_dir_t lv_dropdown_get_dir(lv_obj_t* ddlist)
int luat_lv_dropdown_get_dir(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_dir");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dropdown_dir_t ret;
    ret = lv_dropdown_get_dir(ddlist);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_dropdown_get_show_selected(lv_obj_t* ddlist)
int luat_lv_dropdown_get_show_selected(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_show_selected");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_dropdown_get_show_selected(ddlist);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_dropdown_open(lv_obj_t* ddlist)
int luat_lv_dropdown_open(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_open");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dropdown_open(ddlist);
    return 0;
}

//  void lv_dropdown_close(lv_obj_t* ddlist)
int luat_lv_dropdown_close(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_close");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dropdown_close(ddlist);
    return 0;
}

