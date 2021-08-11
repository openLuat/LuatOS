
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_roller_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_roller_create(lua_State *L) {
    LV_DEBUG("CALL lv_roller_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_roller_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_roller_set_options(lv_obj_t* roller, char* options, lv_roller_mode_t mode)
int luat_lv_roller_set_options(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_options");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    char* options = (char*)luaL_checkstring(L, 2);
    lv_roller_mode_t mode = (lv_roller_mode_t)luaL_checkinteger(L, 3);
    lv_roller_set_options(roller ,options ,mode);
    return 0;
}

//  void lv_roller_set_align(lv_obj_t* roller, lv_label_align_t align)
int luat_lv_roller_set_align(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_align");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_align_t align = (lv_label_align_t)luaL_checkinteger(L, 2);
    lv_roller_set_align(roller ,align);
    return 0;
}

//  void lv_roller_set_selected(lv_obj_t* roller, uint16_t sel_opt, lv_anim_enable_t anim)
int luat_lv_roller_set_selected(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_selected");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t sel_opt = (uint16_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_roller_set_selected(roller ,sel_opt ,anim);
    return 0;
}

//  void lv_roller_set_visible_row_count(lv_obj_t* roller, uint8_t row_cnt)
int luat_lv_roller_set_visible_row_count(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_visible_row_count");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t row_cnt = (uint8_t)luaL_checkinteger(L, 2);
    lv_roller_set_visible_row_count(roller ,row_cnt);
    return 0;
}

//  void lv_roller_set_auto_fit(lv_obj_t* roller, bool auto_fit)
int luat_lv_roller_set_auto_fit(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_auto_fit");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    bool auto_fit = (bool)lua_toboolean(L, 2);
    lv_roller_set_auto_fit(roller ,auto_fit);
    return 0;
}

//  void lv_roller_set_anim_time(lv_obj_t* roller, uint16_t anim_time)
int luat_lv_roller_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_roller_set_anim_time");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_roller_set_anim_time(roller ,anim_time);
    return 0;
}

//  uint16_t lv_roller_get_selected(lv_obj_t* roller)
int luat_lv_roller_get_selected(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_selected");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_roller_get_selected(roller);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_roller_get_option_cnt(lv_obj_t* roller)
int luat_lv_roller_get_option_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_option_cnt");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_roller_get_option_cnt(roller);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_label_align_t lv_roller_get_align(lv_obj_t* roller)
int luat_lv_roller_get_align(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_align");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_align_t ret;
    ret = lv_roller_get_align(roller);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_roller_get_auto_fit(lv_obj_t* roller)
int luat_lv_roller_get_auto_fit(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_auto_fit");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_roller_get_auto_fit(roller);
    lua_pushboolean(L, ret);
    return 1;
}

//  char* lv_roller_get_options(lv_obj_t* roller)
int luat_lv_roller_get_options(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_options");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_roller_get_options(roller);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_roller_get_anim_time(lv_obj_t* roller)
int luat_lv_roller_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_anim_time");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_roller_get_anim_time(roller);
    lua_pushinteger(L, ret);
    return 1;
}

