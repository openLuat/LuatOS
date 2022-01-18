
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_roller_create(lv_obj_t* parent)
int luat_lv_roller_create(lua_State *L) {
    LV_DEBUG("CALL lv_roller_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_roller_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_roller_set_options(lv_obj_t* obj, char* options, lv_roller_mode_t mode)
int luat_lv_roller_set_options(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_options");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* options = (char*)luaL_checkstring(L, 2);
    lv_roller_mode_t mode = (lv_roller_mode_t)luaL_checkinteger(L, 3);
    lv_roller_set_options(obj ,options ,mode);
    return 0;
}

//  void lv_roller_set_selected(lv_obj_t* obj, uint16_t sel_opt, lv_anim_enable_t anim)
int luat_lv_roller_set_selected(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_selected");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t sel_opt = (uint16_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_roller_set_selected(obj ,sel_opt ,anim);
    return 0;
}

//  void lv_roller_set_visible_row_count(lv_obj_t* obj, uint8_t row_cnt)
int luat_lv_roller_set_visible_row_count(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_visible_row_count");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t row_cnt = (uint8_t)luaL_checkinteger(L, 2);
    lv_roller_set_visible_row_count(obj ,row_cnt);
    return 0;
}

//  uint16_t lv_roller_get_selected(lv_obj_t* obj)
int luat_lv_roller_get_selected(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_selected");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_roller_get_selected(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  char* lv_roller_get_options(lv_obj_t* obj)
int luat_lv_roller_get_options(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_options");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_roller_get_options(obj);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_roller_get_option_cnt(lv_obj_t* obj)
int luat_lv_roller_get_option_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_option_cnt");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_roller_get_option_cnt(obj);
    lua_pushinteger(L, ret);
    return 1;
}

