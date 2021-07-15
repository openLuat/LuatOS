
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_arc_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_arc_create(lua_State *L) {
    LV_DEBUG("CALL lv_arc_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_arc_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_arc_set_start_angle(lv_obj_t* arc, uint16_t start)
int luat_lv_arc_set_start_angle(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_start_angle");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t start = (uint16_t)luaL_checknumber(L, 2);
    lv_arc_set_start_angle(arc ,start);
    return 0;
}

//  void lv_arc_set_end_angle(lv_obj_t* arc, uint16_t end)
int luat_lv_arc_set_end_angle(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_end_angle");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t end = (uint16_t)luaL_checknumber(L, 2);
    lv_arc_set_end_angle(arc ,end);
    return 0;
}

//  void lv_arc_set_angles(lv_obj_t* arc, uint16_t start, uint16_t end)
int luat_lv_arc_set_angles(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_angles");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t start = (uint16_t)luaL_checknumber(L, 2);
    uint16_t end = (uint16_t)luaL_checknumber(L, 3);
    lv_arc_set_angles(arc ,start ,end);
    return 0;
}

//  void lv_arc_set_bg_start_angle(lv_obj_t* arc, uint16_t start)
int luat_lv_arc_set_bg_start_angle(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_bg_start_angle");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t start = (uint16_t)luaL_checknumber(L, 2);
    lv_arc_set_bg_start_angle(arc ,start);
    return 0;
}

//  void lv_arc_set_bg_end_angle(lv_obj_t* arc, uint16_t end)
int luat_lv_arc_set_bg_end_angle(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_bg_end_angle");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t end = (uint16_t)luaL_checknumber(L, 2);
    lv_arc_set_bg_end_angle(arc ,end);
    return 0;
}

//  void lv_arc_set_bg_angles(lv_obj_t* arc, uint16_t start, uint16_t end)
int luat_lv_arc_set_bg_angles(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_bg_angles");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t start = (uint16_t)luaL_checknumber(L, 2);
    uint16_t end = (uint16_t)luaL_checknumber(L, 3);
    lv_arc_set_bg_angles(arc ,start ,end);
    return 0;
}

//  void lv_arc_set_rotation(lv_obj_t* arc, uint16_t rotation_angle)
int luat_lv_arc_set_rotation(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_rotation");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t rotation_angle = (uint16_t)luaL_checknumber(L, 2);
    lv_arc_set_rotation(arc ,rotation_angle);
    return 0;
}

//  void lv_arc_set_type(lv_obj_t* arc, lv_arc_type_t type)
int luat_lv_arc_set_type(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_type");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    lv_arc_type_t type = (lv_arc_type_t)luaL_checkinteger(L, 2);
    lv_arc_set_type(arc ,type);
    return 0;
}

//  void lv_arc_set_value(lv_obj_t* arc, int16_t value)
int luat_lv_arc_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_value");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t value = (int16_t)luaL_checknumber(L, 2);
    lv_arc_set_value(arc ,value);
    return 0;
}

//  void lv_arc_set_range(lv_obj_t* arc, int16_t min, int16_t max)
int luat_lv_arc_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_range");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t min = (int16_t)luaL_checknumber(L, 2);
    int16_t max = (int16_t)luaL_checknumber(L, 3);
    lv_arc_set_range(arc ,min ,max);
    return 0;
}

//  void lv_arc_set_chg_rate(lv_obj_t* arc, uint16_t threshold)
int luat_lv_arc_set_chg_rate(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_chg_rate");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t threshold = (uint16_t)luaL_checknumber(L, 2);
    lv_arc_set_chg_rate(arc ,threshold);
    return 0;
}

//  void lv_arc_set_adjustable(lv_obj_t* arc, bool adjustable)
int luat_lv_arc_set_adjustable(lua_State *L) {
    LV_DEBUG("CALL lv_arc_set_adjustable");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    bool adjustable = (bool)lua_toboolean(L, 2);
    lv_arc_set_adjustable(arc ,adjustable);
    return 0;
}

//  uint16_t lv_arc_get_angle_start(lv_obj_t* arc)
int luat_lv_arc_get_angle_start(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_angle_start");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_arc_get_angle_start(arc);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_arc_get_angle_end(lv_obj_t* arc)
int luat_lv_arc_get_angle_end(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_angle_end");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_arc_get_angle_end(arc);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_arc_get_bg_angle_start(lv_obj_t* arc)
int luat_lv_arc_get_bg_angle_start(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_bg_angle_start");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_arc_get_bg_angle_start(arc);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_arc_get_bg_angle_end(lv_obj_t* arc)
int luat_lv_arc_get_bg_angle_end(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_bg_angle_end");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_arc_get_bg_angle_end(arc);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_arc_type_t lv_arc_get_type(lv_obj_t* arc)
int luat_lv_arc_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_type");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    lv_arc_type_t ret;
    ret = lv_arc_get_type(arc);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_arc_get_value(lv_obj_t* arc)
int luat_lv_arc_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_value");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_arc_get_value(arc);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_arc_get_min_value(lv_obj_t* arc)
int luat_lv_arc_get_min_value(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_min_value");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_arc_get_min_value(arc);
    lua_pushinteger(L, ret);
    return 1;
}

//  int16_t lv_arc_get_max_value(lv_obj_t* arc)
int luat_lv_arc_get_max_value(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_max_value");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t ret;
    ret = lv_arc_get_max_value(arc);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_arc_is_dragged(lv_obj_t* arc)
int luat_lv_arc_is_dragged(lua_State *L) {
    LV_DEBUG("CALL lv_arc_is_dragged");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_arc_is_dragged(arc);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_arc_get_adjustable(lv_obj_t* arc)
int luat_lv_arc_get_adjustable(lua_State *L) {
    LV_DEBUG("CALL lv_arc_get_adjustable");
    lv_obj_t* arc = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_arc_get_adjustable(arc);
    lua_pushboolean(L, ret);
    return 1;
}

