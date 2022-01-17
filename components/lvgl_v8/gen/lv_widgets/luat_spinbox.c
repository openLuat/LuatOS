
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_spinbox_create(lv_obj_t* parent)
int luat_lv_spinbox_create(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_spinbox_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_spinbox_set_value(lv_obj_t* obj, int32_t i)
int luat_lv_spinbox_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_set_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t i = (int32_t)luaL_checkinteger(L, 2);
    lv_spinbox_set_value(obj ,i);
    return 0;
}

//  void lv_spinbox_set_rollover(lv_obj_t* obj, bool b)
int luat_lv_spinbox_set_rollover(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_set_rollover");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool b = (bool)lua_toboolean(L, 2);
    lv_spinbox_set_rollover(obj ,b);
    return 0;
}

//  void lv_spinbox_set_digit_format(lv_obj_t* obj, uint8_t digit_count, uint8_t separator_position)
int luat_lv_spinbox_set_digit_format(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_set_digit_format");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t digit_count = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t separator_position = (uint8_t)luaL_checkinteger(L, 3);
    lv_spinbox_set_digit_format(obj ,digit_count ,separator_position);
    return 0;
}

//  void lv_spinbox_set_step(lv_obj_t* obj, uint32_t step)
int luat_lv_spinbox_set_step(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_set_step");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t step = (uint32_t)luaL_checkinteger(L, 2);
    lv_spinbox_set_step(obj ,step);
    return 0;
}

//  void lv_spinbox_set_range(lv_obj_t* obj, int32_t range_min, int32_t range_max)
int luat_lv_spinbox_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_set_range");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t range_min = (int32_t)luaL_checkinteger(L, 2);
    int32_t range_max = (int32_t)luaL_checkinteger(L, 3);
    lv_spinbox_set_range(obj ,range_min ,range_max);
    return 0;
}

//  void lv_spinbox_set_pos(lv_obj_t* obj, uint8_t pos)
int luat_lv_spinbox_set_pos(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_set_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t pos = (uint8_t)luaL_checkinteger(L, 2);
    lv_spinbox_set_pos(obj ,pos);
    return 0;
}

//  void lv_spinbox_set_digit_step_direction(lv_obj_t* obj, lv_dir_t direction)
int luat_lv_spinbox_set_digit_step_direction(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_set_digit_step_direction");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dir_t direction = (lv_dir_t)luaL_checkinteger(L, 2);
    lv_spinbox_set_digit_step_direction(obj ,direction);
    return 0;
}

//  bool lv_spinbox_get_rollover(lv_obj_t* obj)
int luat_lv_spinbox_get_rollover(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_get_rollover");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_spinbox_get_rollover(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  int32_t lv_spinbox_get_value(lv_obj_t* obj)
int luat_lv_spinbox_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_get_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_spinbox_get_value(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_spinbox_get_step(lv_obj_t* obj)
int luat_lv_spinbox_get_step(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_get_step");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_spinbox_get_step(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_spinbox_step_next(lv_obj_t* obj)
int luat_lv_spinbox_step_next(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_step_next");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spinbox_step_next(obj);
    return 0;
}

//  void lv_spinbox_step_prev(lv_obj_t* obj)
int luat_lv_spinbox_step_prev(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_step_prev");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spinbox_step_prev(obj);
    return 0;
}

//  void lv_spinbox_increment(lv_obj_t* obj)
int luat_lv_spinbox_increment(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_increment");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spinbox_increment(obj);
    return 0;
}

//  void lv_spinbox_decrement(lv_obj_t* obj)
int luat_lv_spinbox_decrement(lua_State *L) {
    LV_DEBUG("CALL lv_spinbox_decrement");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spinbox_decrement(obj);
    return 0;
}

