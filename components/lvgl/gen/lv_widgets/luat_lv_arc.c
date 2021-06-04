
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_arc_create(lv_obj_t* parent)
int luat_lv_arc_create(lua_State *L) {
    LV_DEBUG("CALL lv_arc_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_arc_create(parent);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_arc_set_start_angle(lv_obj_t* arc, uint16_t start)
int luat_lv_arc_set_start_angle(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_start_angle");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t start = (uint16_t)luaL_checkinteger(L, 2);
    lv_arc_set_start_angle(arc ,start);
    return 0;
}

//  void lv_arc_set_end_angle(lv_obj_t* arc, uint16_t end)
int luat_lv_arc_set_end_angle(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_end_angle");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t end = (uint16_t)luaL_checkinteger(L, 2);
    lv_arc_set_end_angle(arc ,end);
    return 0;
}

//  void lv_arc_set_angles(lv_obj_t* arc, uint16_t start, uint16_t end)
int luat_lv_arc_set_angles(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_angles");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t start = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t end = (uint16_t)luaL_checkinteger(L, 3);
    lv_arc_set_angles(arc ,start ,end);
    return 0;
}

//  void lv_arc_set_bg_start_angle(lv_obj_t* arc, uint16_t start)
int luat_lv_arc_set_bg_start_angle(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_bg_start_angle");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t start = (uint16_t)luaL_checkinteger(L, 2);
    lv_arc_set_bg_start_angle(arc ,start);
    return 0;
}

//  void lv_arc_set_bg_end_angle(lv_obj_t* arc, uint16_t end)
int luat_lv_arc_set_bg_end_angle(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_bg_end_angle");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t end = (uint16_t)luaL_checkinteger(L, 2);
    lv_arc_set_bg_end_angle(arc ,end);
    return 0;
}

//  void lv_arc_set_bg_angles(lv_obj_t* arc, uint16_t start, uint16_t end)
int luat_lv_arc_set_bg_angles(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_bg_angles");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t start = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t end = (uint16_t)luaL_checkinteger(L, 3);
    lv_arc_set_bg_angles(arc ,start ,end);
    return 0;
}

//  void lv_arc_set_rotation(lv_obj_t* arc, uint16_t rotation)
int luat_lv_arc_set_rotation(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_rotation");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t rotation = (uint16_t)luaL_checkinteger(L, 2);
    lv_arc_set_rotation(arc ,rotation);
    return 0;
}

//  void lv_arc_set_mode(lv_obj_t* arc, lv_arc_mode_t type)
int luat_lv_arc_set_mode(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_mode");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    lv_arc_mode_t type = (lv_arc_mode_t)luaL_checkinteger(L, 2);
    lv_arc_set_mode(arc ,type);
    return 0;
}

//  void lv_arc_set_value(lv_obj_t* arc, int16_t value)
int luat_lv_arc_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_value");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t value = (int16_t)luaL_checkinteger(L, 2);
    lv_arc_set_value(arc ,value);
    return 0;
}

//  void lv_arc_set_range(lv_obj_t* arc, int16_t min, int16_t max)
int luat_lv_arc_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_range");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t min = (int16_t)luaL_checkinteger(L, 2);
    int16_t max = (int16_t)luaL_checkinteger(L, 3);
    lv_arc_set_range(arc ,min ,max);
    return 0;
}

//  void lv_arc_set_change_rate(lv_obj_t* arc, uint16_t rate)
int luat_lv_arc_set_change_rate(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_change_rate");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t rate = (uint16_t)luaL_checkinteger(L, 2);
    lv_arc_set_change_rate(arc ,rate);
    return 0;
}

//  uint16_t lv_arc_get_angle_start(lv_obj_t* obj)
int luat_lv_arc_get_angle_start(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_angle_start");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_arc_get_angle_start(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_arc_get_angle_end(lv_obj_t* obj)
int luat_lv_arc_get_angle_end(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_angle_end");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_arc_get_angle_end(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_arc_get_bg_angle_start(lv_obj_t* obj)
int luat_lv_arc_get_bg_angle_start(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_bg_angle_start");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_arc_get_bg_angle_start(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_arc_get_bg_angle_end(lv_obj_t* obj)
int luat_lv_arc_get_bg_angle_end(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_bg_angle_end");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_arc_get_bg_angle_end(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_arc_get_value(lv_obj_t* obj)
int luat_lv_arc_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_arc_get_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_arc_get_min_value(lv_obj_t* obj)
int luat_lv_arc_get_min_value(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_min_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_arc_get_min_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_arc_get_max_value(lv_obj_t* obj)
int luat_lv_arc_get_max_value(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_max_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_arc_get_max_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_arc_mode_t lv_arc_get_mode(lv_obj_t* obj)
int luat_lv_arc_get_mode(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_arc_mode_t ret;
    ret = lv_arc_get_mode(obj);
    lua_pushinteger(L, ret);
    return 1;
}

