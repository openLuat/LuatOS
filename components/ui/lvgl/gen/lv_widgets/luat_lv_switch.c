
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_switch_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_switch_create(lua_State *L) {
    LV_DEBUG("CALL lv_switch_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_switch_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_switch_on(lv_obj_t* sw, lv_anim_enable_t anim)
int luat_lv_switch_on(lua_State *L) {
    LV_DEBUG("CALL lv_switch_on");
    lv_obj_t* sw = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 2);
    lv_switch_on(sw ,anim);
    return 0;
}

//  void lv_switch_off(lv_obj_t* sw, lv_anim_enable_t anim)
int luat_lv_switch_off(lua_State *L) {
    LV_DEBUG("CALL lv_switch_off");
    lv_obj_t* sw = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 2);
    lv_switch_off(sw ,anim);
    return 0;
}

//  bool lv_switch_toggle(lv_obj_t* sw, lv_anim_enable_t anim)
int luat_lv_switch_toggle(lua_State *L) {
    LV_DEBUG("CALL lv_switch_toggle");
    lv_obj_t* sw = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 2);
    bool ret;
    ret = lv_switch_toggle(sw ,anim);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_switch_set_anim_time(lv_obj_t* sw, uint16_t anim_time)
int luat_lv_switch_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_switch_set_anim_time");
    lv_obj_t* sw = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_switch_set_anim_time(sw ,anim_time);
    return 0;
}

//  bool lv_switch_get_state(lv_obj_t* sw)
int luat_lv_switch_get_state(lua_State *L) {
    LV_DEBUG("CALL lv_switch_get_state");
    lv_obj_t* sw = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_switch_get_state(sw);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_switch_get_anim_time(lv_obj_t* sw)
int luat_lv_switch_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_switch_get_anim_time");
    lv_obj_t* sw = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_switch_get_anim_time(sw);
    lua_pushinteger(L, ret);
    return 1;
}

