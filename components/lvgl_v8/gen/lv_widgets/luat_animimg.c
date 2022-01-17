
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_animimg_create(lv_obj_t* parent)
int luat_lv_animimg_create(lua_State *L) {
    LV_DEBUG("CALL lv_animimg_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_animimg_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_animimg_start(lv_obj_t* obj)
int luat_lv_animimg_start(lua_State *L) {
    LV_DEBUG("CALL lv_animimg_start");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_animimg_start(obj);
    return 0;
}

//  void lv_animimg_set_duration(lv_obj_t* img, uint32_t duration)
int luat_lv_animimg_set_duration(lua_State *L) {
    LV_DEBUG("CALL lv_animimg_set_duration");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t duration = (uint32_t)luaL_checkinteger(L, 2);
    lv_animimg_set_duration(img ,duration);
    return 0;
}

//  void lv_animimg_set_repeat_count(lv_obj_t* img, uint16_t count)
int luat_lv_animimg_set_repeat_count(lua_State *L) {
    LV_DEBUG("CALL lv_animimg_set_repeat_count");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t count = (uint16_t)luaL_checkinteger(L, 2);
    lv_animimg_set_repeat_count(img ,count);
    return 0;
}

