
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_anim_timeline_t* lv_anim_timeline_create()
int luat_lv_anim_timeline_create(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_create");
    lv_anim_timeline_t* ret = NULL;
    ret = lv_anim_timeline_create();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_anim_timeline_del(lv_anim_timeline_t* at)
int luat_lv_anim_timeline_del(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_del");
    lv_anim_timeline_t* at = (lv_anim_timeline_t*)lua_touserdata(L, 1);
    lv_anim_timeline_del(at);
    return 0;
}

//  void lv_anim_timeline_add(lv_anim_timeline_t* at, uint32_t start_time, lv_anim_t* a)
int luat_lv_anim_timeline_add(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_add");
    lv_anim_timeline_t* at = (lv_anim_timeline_t*)lua_touserdata(L, 1);
    uint32_t start_time = (uint32_t)luaL_checkinteger(L, 2);
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 3);
    lv_anim_timeline_add(at ,start_time ,a);
    return 0;
}

//  uint32_t lv_anim_timeline_start(lv_anim_timeline_t* at)
int luat_lv_anim_timeline_start(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_start");
    lv_anim_timeline_t* at = (lv_anim_timeline_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_anim_timeline_start(at);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_anim_timeline_stop(lv_anim_timeline_t* at)
int luat_lv_anim_timeline_stop(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_stop");
    lv_anim_timeline_t* at = (lv_anim_timeline_t*)lua_touserdata(L, 1);
    lv_anim_timeline_stop(at);
    return 0;
}

//  void lv_anim_timeline_set_reverse(lv_anim_timeline_t* at, bool reverse)
int luat_lv_anim_timeline_set_reverse(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_set_reverse");
    lv_anim_timeline_t* at = (lv_anim_timeline_t*)lua_touserdata(L, 1);
    bool reverse = (bool)lua_toboolean(L, 2);
    lv_anim_timeline_set_reverse(at ,reverse);
    return 0;
}

//  void lv_anim_timeline_set_progress(lv_anim_timeline_t* at, uint16_t progress)
int luat_lv_anim_timeline_set_progress(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_set_progress");
    lv_anim_timeline_t* at = (lv_anim_timeline_t*)lua_touserdata(L, 1);
    uint16_t progress = (uint16_t)luaL_checkinteger(L, 2);
    lv_anim_timeline_set_progress(at ,progress);
    return 0;
}

//  uint32_t lv_anim_timeline_get_playtime(lv_anim_timeline_t* at)
int luat_lv_anim_timeline_get_playtime(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_get_playtime");
    lv_anim_timeline_t* at = (lv_anim_timeline_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_anim_timeline_get_playtime(at);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_anim_timeline_get_reverse(lv_anim_timeline_t* at)
int luat_lv_anim_timeline_get_reverse(lua_State *L) {
    LV_DEBUG("CALL lv_anim_timeline_get_reverse");
    lv_anim_timeline_t* at = (lv_anim_timeline_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_anim_timeline_get_reverse(at);
    lua_pushboolean(L, ret);
    return 1;
}

