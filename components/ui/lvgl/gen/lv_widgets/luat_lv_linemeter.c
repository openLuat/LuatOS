
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_linemeter_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_linemeter_create(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_linemeter_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_linemeter_set_value(lv_obj_t* lmeter, int32_t value)
int luat_lv_linemeter_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_set_value");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t value = (int32_t)luaL_checkinteger(L, 2);
    lv_linemeter_set_value(lmeter ,value);
    return 0;
}

//  void lv_linemeter_set_range(lv_obj_t* lmeter, int32_t min, int32_t max)
int luat_lv_linemeter_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_set_range");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t min = (int32_t)luaL_checkinteger(L, 2);
    int32_t max = (int32_t)luaL_checkinteger(L, 3);
    lv_linemeter_set_range(lmeter ,min ,max);
    return 0;
}

//  void lv_linemeter_set_scale(lv_obj_t* lmeter, uint16_t angle, uint16_t line_cnt)
int luat_lv_linemeter_set_scale(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_set_scale");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t angle = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t line_cnt = (uint16_t)luaL_checkinteger(L, 3);
    lv_linemeter_set_scale(lmeter ,angle ,line_cnt);
    return 0;
}

//  void lv_linemeter_set_angle_offset(lv_obj_t* lmeter, uint16_t angle)
int luat_lv_linemeter_set_angle_offset(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_set_angle_offset");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t angle = (uint16_t)luaL_checkinteger(L, 2);
    lv_linemeter_set_angle_offset(lmeter ,angle);
    return 0;
}

//  void lv_linemeter_set_mirror(lv_obj_t* lmeter, bool mirror)
int luat_lv_linemeter_set_mirror(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_set_mirror");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    bool mirror = (bool)lua_toboolean(L, 2);
    lv_linemeter_set_mirror(lmeter ,mirror);
    return 0;
}

//  int32_t lv_linemeter_get_value(lv_obj_t* lmeter)
int luat_lv_linemeter_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_get_value");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_linemeter_get_value(lmeter);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_linemeter_get_min_value(lv_obj_t* lmeter)
int luat_lv_linemeter_get_min_value(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_get_min_value");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_linemeter_get_min_value(lmeter);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_linemeter_get_max_value(lv_obj_t* lmeter)
int luat_lv_linemeter_get_max_value(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_get_max_value");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_linemeter_get_max_value(lmeter);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_linemeter_get_line_count(lv_obj_t* lmeter)
int luat_lv_linemeter_get_line_count(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_get_line_count");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_linemeter_get_line_count(lmeter);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_linemeter_get_scale_angle(lv_obj_t* lmeter)
int luat_lv_linemeter_get_scale_angle(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_get_scale_angle");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_linemeter_get_scale_angle(lmeter);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_linemeter_get_angle_offset(lv_obj_t* lmeter)
int luat_lv_linemeter_get_angle_offset(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_get_angle_offset");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_linemeter_get_angle_offset(lmeter);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_linemeter_draw_scale(lv_obj_t* lmeter, lv_area_t* clip_area, uint8_t part)
int luat_lv_linemeter_draw_scale(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_draw_scale");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* clip_area = (lv_area_t*)lua_touserdata(L, 2);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 3);
    lv_linemeter_draw_scale(lmeter ,clip_area ,part);
    return 0;
}

//  bool lv_linemeter_get_mirror(lv_obj_t* lmeter)
int luat_lv_linemeter_get_mirror(lua_State *L) {
    LV_DEBUG("CALL lv_linemeter_get_mirror");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_linemeter_get_mirror(lmeter);
    lua_pushboolean(L, ret);
    return 1;
}

