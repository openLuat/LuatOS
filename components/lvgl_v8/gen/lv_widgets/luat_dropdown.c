
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_dropdown_create(lv_obj_t* parent)
int luat_lv_dropdown_create(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_dropdown_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_dropdown_set_text(lv_obj_t* obj, char* txt)
int luat_lv_dropdown_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_dropdown_set_text(obj ,txt);
    return 0;
}

//  void lv_dropdown_set_options(lv_obj_t* obj, char* options)
int luat_lv_dropdown_set_options(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_options");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* options = (char*)luaL_checkstring(L, 2);
    lv_dropdown_set_options(obj ,options);
    return 0;
}

//  void lv_dropdown_set_options_static(lv_obj_t* obj, char* options)
int luat_lv_dropdown_set_options_static(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_options_static");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* options = (char*)luaL_checkstring(L, 2);
    lv_dropdown_set_options_static(obj ,options);
    return 0;
}

//  void lv_dropdown_add_option(lv_obj_t* obj, char* option, uint32_t pos)
int luat_lv_dropdown_add_option(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_add_option");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* option = (char*)luaL_checkstring(L, 2);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 3);
    lv_dropdown_add_option(obj ,option ,pos);
    return 0;
}

//  void lv_dropdown_clear_options(lv_obj_t* obj)
int luat_lv_dropdown_clear_options(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_clear_options");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dropdown_clear_options(obj);
    return 0;
}

//  void lv_dropdown_set_selected(lv_obj_t* obj, uint16_t sel_opt)
int luat_lv_dropdown_set_selected(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_selected");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t sel_opt = (uint16_t)luaL_checkinteger(L, 2);
    lv_dropdown_set_selected(obj ,sel_opt);
    return 0;
}

//  void lv_dropdown_set_dir(lv_obj_t* obj, lv_dir_t dir)
int luat_lv_dropdown_set_dir(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dir_t dir = (lv_dir_t)luaL_checkinteger(L, 2);
    lv_dropdown_set_dir(obj ,dir);
    return 0;
}

//  void lv_dropdown_set_selected_highlight(lv_obj_t* obj, bool en)
int luat_lv_dropdown_set_selected_highlight(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_selected_highlight");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_dropdown_set_selected_highlight(obj ,en);
    return 0;
}

//  lv_obj_t* lv_dropdown_get_list(lv_obj_t* obj)
int luat_lv_dropdown_get_list(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_list");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_dropdown_get_list(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  char* lv_dropdown_get_text(lv_obj_t* obj)
int luat_lv_dropdown_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_dropdown_get_text(obj);
    lua_pushstring(L, ret);
    return 1;
}

//  char* lv_dropdown_get_options(lv_obj_t* obj)
int luat_lv_dropdown_get_options(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_options");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_dropdown_get_options(obj);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_dropdown_get_selected(lv_obj_t* obj)
int luat_lv_dropdown_get_selected(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_selected");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_dropdown_get_selected(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_dropdown_get_option_cnt(lv_obj_t* obj)
int luat_lv_dropdown_get_option_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_option_cnt");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_dropdown_get_option_cnt(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  char* lv_dropdown_get_symbol(lv_obj_t* obj)
int luat_lv_dropdown_get_symbol(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_symbol");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_dropdown_get_symbol(obj);
    lua_pushstring(L, ret);
    return 1;
}

//  bool lv_dropdown_get_selected_highlight(lv_obj_t* obj)
int luat_lv_dropdown_get_selected_highlight(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_selected_highlight");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_dropdown_get_selected_highlight(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_dir_t lv_dropdown_get_dir(lv_obj_t* obj)
int luat_lv_dropdown_get_dir(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dir_t ret;
    ret = lv_dropdown_get_dir(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_dropdown_open(lv_obj_t* dropdown_obj)
int luat_lv_dropdown_open(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_open");
    lv_obj_t* dropdown_obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dropdown_open(dropdown_obj);
    return 0;
}

//  void lv_dropdown_close(lv_obj_t* obj)
int luat_lv_dropdown_close(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_close");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dropdown_close(obj);
    return 0;
}

